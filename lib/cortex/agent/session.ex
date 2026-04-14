defmodule Cortex.Agent.Session do
  @moduledoc false

  use GenServer, restart: :temporary
  require Logger

  alias Cortex.Agent.{ClaudeClient, Tool}

  defstruct [
    :id,
    :model,
    :cwd,
    :system_prompt,
    :task_pid,
    messages: [],
    content_blocks: [],
    current_block_index: nil,
    current_text: "",
    current_tool: nil,
    tool_input_buffer: "",
    stop_reason: nil,
    streaming: false,
    auto_approve: true
  ]

  # ── Client API ──

  def start_link(opts) do
    id = Keyword.fetch!(opts, :id)
    GenServer.start_link(__MODULE__, opts, name: via(id))
  end

  def send_message(id, content) do
    GenServer.cast(via(id), {:send_message, content})
  end

  def approve_tool(id, tool_call_id) do
    GenServer.cast(via(id), {:approve_tool, tool_call_id})
  end

  def deny_tool(id, tool_call_id) do
    GenServer.cast(via(id), {:deny_tool, tool_call_id})
  end

  def get_state(id) do
    GenServer.call(via(id), :get_state)
  end

  def stop(id) do
    GenServer.stop(via(id), :normal)
  end

  defp via(id), do: {:via, Registry, {Cortex.Agent.SessionRegistry, id}}

  # ── Server Callbacks ──

  @impl true
  def init(opts) do
    id = Keyword.fetch!(opts, :id)
    cwd = Keyword.get(opts, :cwd, System.user_home!())
    model = Keyword.get(opts, :model, "claude-sonnet-4-6")
    auto_approve = Keyword.get(opts, :auto_approve, true)

    system_prompt = build_system_prompt(cwd, opts)

    state = %__MODULE__{
      id: id,
      model: model,
      cwd: cwd,
      system_prompt: system_prompt,
      auto_approve: auto_approve
    }

    broadcast(id, {:session_started, id})
    {:ok, state}
  end

  @impl true
  def handle_cast({:send_message, content}, state) do
    user_msg = %{"role" => "user", "content" => content}
    messages = state.messages ++ [user_msg]

    broadcast(state.id, {:user_message, content})

    state = %{state | messages: messages}
    state = start_streaming(state)

    {:noreply, state}
  end

  def handle_cast({:approve_tool, tool_call_id}, state) do
    case find_pending_tool(state, tool_call_id) do
      nil ->
        {:noreply, state}

      tool_call ->
        state = execute_single_tool_and_continue(tool_call, state)
        {:noreply, state}
    end
  end

  def handle_cast({:deny_tool, tool_call_id}, state) do
    tool_result = %{
      "type" => "tool_result",
      "tool_use_id" => tool_call_id,
      "content" => "Tool execution denied by user.",
      "is_error" => true
    }

    state = send_tool_results_and_continue([tool_result], state)
    {:noreply, state}
  end

  @impl true
  def handle_call(:get_state, _from, state) do
    info = %{
      id: state.id,
      model: state.model,
      cwd: state.cwd,
      streaming: state.streaming,
      message_count: length(state.messages),
      auto_approve: state.auto_approve
    }

    {:reply, info, state}
  end

  # ── Streaming Event Handlers ──

  @impl true
  def handle_info({:claude_event, %{event: "message_start"}}, state) do
    broadcast(state.id, :assistant_start)

    {:noreply,
     %{state | content_blocks: [], current_text: "", current_tool: nil, stop_reason: nil}}
  end

  def handle_info(
        {:claude_event,
         %{event: "content_block_start", data: %{"index" => idx, "content_block" => block}}},
        state
      ) do
    case block["type"] do
      "text" ->
        broadcast(state.id, {:text_start, idx})
        {:noreply, %{state | current_block_index: idx, current_text: ""}}

      "tool_use" ->
        tool = %{id: block["id"], name: block["name"], input: nil}
        broadcast(state.id, {:tool_start, tool})

        {:noreply,
         %{state | current_block_index: idx, current_tool: tool, tool_input_buffer: ""}}

      _ ->
        {:noreply, state}
    end
  end

  def handle_info(
        {:claude_event, %{event: "content_block_delta", data: %{"delta" => delta}}},
        state
      ) do
    case delta["type"] do
      "text_delta" ->
        text = delta["text"]
        broadcast(state.id, {:text_delta, text})
        {:noreply, %{state | current_text: state.current_text <> text}}

      "input_json_delta" ->
        json = delta["partial_json"]
        {:noreply, %{state | tool_input_buffer: state.tool_input_buffer <> json}}

      _ ->
        {:noreply, state}
    end
  end

  def handle_info({:claude_event, %{event: "content_block_stop"}}, state) do
    cond do
      # Text block finished — finalize and add to content_blocks
      state.current_tool == nil and state.current_text != "" ->
        block = %{"type" => "text", "text" => state.current_text}
        blocks = state.content_blocks ++ [block]
        broadcast(state.id, :text_done)
        {:noreply, %{state | content_blocks: blocks, current_text: ""}}

      # Tool use block finished — finalize block but DON'T execute yet.
      # Execution happens in message_stop to avoid race with remaining SSE events.
      state.current_tool != nil ->
        input =
          case Jason.decode(state.tool_input_buffer) do
            {:ok, parsed} -> parsed
            _ -> %{}
          end

        tool_call = %{state.current_tool | input: input}

        block = %{
          "type" => "tool_use",
          "id" => tool_call.id,
          "name" => tool_call.name,
          "input" => input
        }

        blocks = state.content_blocks ++ [block]
        broadcast(state.id, {:tool_ready, tool_call})

        {:noreply, %{state | content_blocks: blocks, current_tool: nil, tool_input_buffer: ""}}

      true ->
        {:noreply, state}
    end
  end

  def handle_info(
        {:claude_event,
         %{event: "message_delta", data: %{"delta" => %{"stop_reason" => reason}}}},
        state
      ) do
    {:noreply, %{state | stop_reason: reason}}
  end

  def handle_info({:claude_event, %{event: "message_stop"}}, state) do
    # Finalize assistant message
    assistant_msg = %{"role" => "assistant", "content" => state.content_blocks}
    messages = state.messages ++ [assistant_msg]
    state = %{state | messages: messages, content_blocks: []}

    case state.stop_reason do
      "tool_use" ->
        # Extract all tool_use blocks and execute them
        tool_blocks =
          assistant_msg["content"]
          |> Enum.filter(&(&1["type"] == "tool_use"))

        if state.auto_approve do
          state = execute_tools_and_continue(tool_blocks, state)
          {:noreply, state}
        else
          # Tools need manual approval — UI will show approve/deny buttons
          {:noreply, %{state | streaming: false}}
        end

      _ ->
        # end_turn or other — conversation turn is complete
        broadcast(state.id, :message_complete)
        {:noreply, %{state | streaming: false}}
    end
  end

  def handle_info({:claude_done, :ok}, state) do
    {:noreply, state}
  end

  def handle_info({:claude_error, reason}, state) do
    Logger.error("Claude API error in session #{state.id}: #{inspect(reason)}")
    broadcast(state.id, {:error, "Claude API error: #{inspect(reason)}"})
    {:noreply, %{state | streaming: false}}
  end

  def handle_info({:DOWN, _ref, :process, _pid, :normal}, state), do: {:noreply, state}

  def handle_info({:DOWN, _ref, :process, _pid, reason}, state) do
    Logger.error("Streaming process crashed in session #{state.id}: #{inspect(reason)}")
    broadcast(state.id, {:error, "Streaming process crashed"})
    {:noreply, %{state | streaming: false}}
  end

  def handle_info(_msg, state), do: {:noreply, state}

  # ── Private ──

  defp start_streaming(state) do
    me = self()

    pid =
      spawn(fn ->
        try do
          ClaudeClient.stream_message(me, state.messages,
            model: state.model,
            tools: Tool.claude_format(),
            system: state.system_prompt
          )
        rescue
          e ->
            send(me, {:claude_error, Exception.message(e)})
        end
      end)

    Process.monitor(pid)
    %{state | streaming: true, task_pid: pid}
  end

  defp execute_tools_and_continue(tool_blocks, state) do
    tool_results =
      Enum.map(tool_blocks, fn block ->
        tool_call = %{id: block["id"], name: block["name"], input: block["input"]}
        broadcast(state.id, {:tool_executing, tool_call})

        context = %{cwd: state.cwd}
        result = Tool.execute(tool_call.name, tool_call.input, context)

        {content, is_error} =
          case result do
            {:ok, output} -> {output, false}
            {:error, error} -> {error, true}
          end

        broadcast(state.id, {:tool_result, tool_call.id, content, is_error})

        %{
          "type" => "tool_result",
          "tool_use_id" => tool_call.id,
          "content" => truncate_result(content),
          "is_error" => is_error
        }
      end)

    send_tool_results_and_continue(tool_results, state)
  end

  defp execute_single_tool_and_continue(tool_call, state) do
    broadcast(state.id, {:tool_executing, tool_call})

    context = %{cwd: state.cwd}
    result = Tool.execute(tool_call.name, tool_call.input, context)

    {content, is_error} =
      case result do
        {:ok, output} -> {output, false}
        {:error, error} -> {error, true}
      end

    broadcast(state.id, {:tool_result, tool_call.id, content, is_error})

    tool_result = %{
      "type" => "tool_result",
      "tool_use_id" => tool_call.id,
      "content" => truncate_result(content),
      "is_error" => is_error
    }

    send_tool_results_and_continue([tool_result], state)
  end

  defp send_tool_results_and_continue(tool_results, state) do
    tool_result_msg = %{"role" => "user", "content" => tool_results}
    messages = state.messages ++ [tool_result_msg]

    state = %{state | messages: messages}
    start_streaming(state)
  end

  defp find_pending_tool(state, tool_call_id) do
    state.messages
    |> Enum.reverse()
    |> Enum.find_value(fn
      %{"role" => "assistant", "content" => blocks} when is_list(blocks) ->
        Enum.find_value(blocks, fn
          %{"type" => "tool_use", "id" => ^tool_call_id, "name" => name, "input" => input} ->
            %{id: tool_call_id, name: name, input: input}

          _ ->
            nil
        end)

      _ ->
        nil
    end)
  end

  @max_result_bytes 50_000

  defp truncate_result(content) when byte_size(content) > @max_result_bytes do
    binary_part(content, 0, @max_result_bytes) <> "\n... (truncated)"
  end

  defp truncate_result(content), do: content

  defp build_system_prompt(cwd, opts) do
    project_name = Keyword.get(opts, :project_name, Path.basename(cwd))
    claude_md = read_claude_md(cwd)

    """
    You are Cortex, an AI coding agent running inside a terminal mission control dashboard.
    You have tools to read, write, and edit files, search codebases, and execute bash commands.

    Working directory: #{cwd}
    Project: #{project_name}

    ## Rules
    - Read files before editing them. Understand the pattern first.
    - Be concise in explanations, thorough in code.
    - Use the bash tool for git, build, and test commands.
    - Use grep/glob to find files before making assumptions.
    #{if claude_md, do: "\n## Project Context (from CLAUDE.md)\n\n#{claude_md}", else: ""}
    """
  end

  defp read_claude_md(cwd) do
    path = Path.join(cwd, "CLAUDE.md")

    case File.read(path) do
      {:ok, content} -> String.slice(content, 0, 4000)
      _ -> nil
    end
  end

  defp broadcast(session_id, event) do
    Phoenix.PubSub.broadcast(
      Cortex.PubSub,
      "agent:#{session_id}",
      {:agent_event, session_id, event}
    )
  end
end
