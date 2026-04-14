defmodule CortexWeb.AgentLive.Index do
  use CortexWeb, :live_view

  alias Cortex.Agent
  alias Cortex.Agent.ModelRouter

  @impl true
  def mount(_params, _session, socket) do
    socket =
      socket
      |> assign(:session_id, nil)
      |> assign(:messages, [])
      |> assign(:streaming, false)
      |> assign(:current_text, "")
      |> assign(:input, "")
      |> assign(:tool_calls, [])
      |> assign(:tool_count, 0)
      |> assign(:page_title, "Cortex Agent")
      |> assign(:cwd, System.user_home!())
      |> assign(:current_model, ModelRouter.sonnet())
      |> assign(:model_override, nil)
      |> assign(:input_tokens, 0)
      |> assign(:output_tokens, 0)
      |> assign(:cost, 0.0)
      |> assign(:projects, [])
      |> assign(:conversations, [])
      |> assign(:conversation_id, nil)

    if connected?(socket) do
      cwd = System.user_home!()
      {:ok, session_id} = Agent.start_session(cwd: cwd)
      Phoenix.PubSub.subscribe(Cortex.PubSub, "agent:#{session_id}")

      projects = load_projects()
      conversations = Agent.list_conversations(15)

      {:ok,
       assign(socket,
         session_id: session_id,
         cwd: cwd,
         projects: projects,
         conversations: conversations,
         conversation_id: session_id
       )}
    else
      {:ok, socket}
    end
  end

  @impl true
  def terminate(_reason, socket) do
    if socket.assigns[:session_id], do: Agent.stop_session(socket.assigns.session_id)
    :ok
  end

  # ── Events from UI ──

  @impl true
  def handle_event("submit", %{"message" => message}, socket) when message != "" do
    case socket.assigns.session_id do
      nil -> {:noreply, socket}
      session_id ->
        Agent.send_message(session_id, String.trim(message))
        messages = socket.assigns.messages ++ [%{role: :user, content: String.trim(message)}]
        {:noreply, assign(socket, messages: messages, input: "", streaming: true)}
    end
  end

  def handle_event("submit", _params, socket), do: {:noreply, socket}

  def handle_event("update_input", %{"message" => value}, socket) do
    {:noreply, assign(socket, :input, value)}
  end

  def handle_event("approve_tool", %{"id" => tool_id}, socket) do
    if socket.assigns.session_id, do: Agent.approve_tool(socket.assigns.session_id, tool_id)
    {:noreply, socket}
  end

  def handle_event("deny_tool", %{"id" => tool_id}, socket) do
    if socket.assigns.session_id, do: Agent.deny_tool(socket.assigns.session_id, tool_id)
    {:noreply, socket}
  end

  def handle_event("change_project", %{"project" => path}, socket) do
    if socket.assigns.session_id, do: Agent.stop_session(socket.assigns.session_id)

    {:ok, session_id} = Agent.start_session(cwd: path)
    Phoenix.PubSub.subscribe(Cortex.PubSub, "agent:#{session_id}")

    {:noreply,
     assign(socket,
       session_id: session_id,
       cwd: path,
       messages: [],
       streaming: false,
       current_text: "",
       tool_calls: [],
       tool_count: 0,
       input_tokens: 0,
       output_tokens: 0,
       cost: 0.0,
       conversation_id: session_id
     )}
  end

  def handle_event("change_model", %{"model" => model}, socket) do
    if socket.assigns.session_id do
      Agent.set_model(socket.assigns.session_id, model)
    end

    override = if model == "auto", do: nil, else: model
    {:noreply, assign(socket, model_override: override)}
  end

  def handle_event("load_conversation", %{"id" => "new"}, socket) do
    if socket.assigns.session_id, do: Agent.stop_session(socket.assigns.session_id)

    {:ok, session_id} = Agent.start_session(cwd: socket.assigns.cwd)
    Phoenix.PubSub.subscribe(Cortex.PubSub, "agent:#{session_id}")

    {:noreply,
     assign(socket,
       session_id: session_id,
       messages: [],
       streaming: false,
       current_text: "",
       tool_calls: [],
       tool_count: 0,
       input_tokens: 0,
       output_tokens: 0,
       cost: 0.0,
       conversation_id: session_id
     )}
  end

  def handle_event("load_conversation", %{"id" => conv_id}, socket) do
    if socket.assigns.session_id, do: Agent.stop_session(socket.assigns.session_id)

    case Agent.resume_conversation(conv_id, cwd: socket.assigns.cwd) do
      {:ok, session_id} ->
        Phoenix.PubSub.subscribe(Cortex.PubSub, "agent:#{session_id}")
        conv = Agent.get_conversation(conv_id)

        # Rebuild display messages from raw API messages
        display_messages = rebuild_display_messages(conv.messages)

        {:noreply,
         assign(socket,
           session_id: session_id,
           messages: display_messages,
           streaming: false,
           current_text: "",
           tool_calls: [],
           input_tokens: conv.input_tokens || 0,
           output_tokens: conv.output_tokens || 0,
           cost: ModelRouter.estimate_cost(conv.model || ModelRouter.sonnet(), conv.input_tokens || 0, conv.output_tokens || 0),
           conversation_id: conv_id
         )}

      {:error, _} ->
        {:noreply, socket}
    end
  end

  def handle_event("toggle_tool_result", %{"id" => id}, socket) do
    messages =
      Enum.map(socket.assigns.messages, fn msg ->
        if Map.get(msg, :tool_id) == id do
          Map.update(msg, :collapsed, false, &(!&1))
        else
          msg
        end
      end)

    {:noreply, assign(socket, :messages, messages)}
  end

  def handle_event("keydown", _params, socket), do: {:noreply, socket}

  # ── Events from Agent Session ──

  @impl true
  def handle_info({:agent_event, _id, {:user_message, _}}, socket), do: {:noreply, socket}
  def handle_info({:agent_event, _id, {:session_started, _}}, socket), do: {:noreply, socket}

  def handle_info({:agent_event, _id, :assistant_start}, socket) do
    {:noreply, assign(socket, streaming: true, current_text: "")}
  end

  def handle_info({:agent_event, _id, {:text_start, _}}, socket) do
    {:noreply, assign(socket, current_text: "")}
  end

  def handle_info({:agent_event, _id, {:text_delta, text}}, socket) do
    new_text = socket.assigns.current_text <> text
    {:noreply, socket |> assign(current_text: new_text) |> push_event("text-delta", %{text: text})}
  end

  def handle_info({:agent_event, _id, :text_done}, socket) do
    messages = socket.assigns.messages ++ [%{role: :assistant, content: socket.assigns.current_text}]
    {:noreply, assign(socket, messages: messages, current_text: "")}
  end

  def handle_info({:agent_event, _id, {:tool_start, tool}}, socket) do
    tool_calls = socket.assigns.tool_calls ++ [%{id: tool.id, name: tool.name, status: :pending}]
    {:noreply, assign(socket, tool_calls: tool_calls)}
  end

  def handle_info({:agent_event, _id, {:tool_ready, tool}}, socket) do
    {:noreply, assign(socket, tool_calls: update_tool_status(socket.assigns.tool_calls, tool.id, :ready, tool.input))}
  end

  def handle_info({:agent_event, _id, {:tool_executing, tool}}, socket) do
    {:noreply, assign(socket, tool_calls: update_tool_status(socket.assigns.tool_calls, tool.id, :executing))}
  end

  def handle_info({:agent_event, _id, {:tool_result, tool_id, content, is_error}}, socket) do
    status = if is_error, do: :error, else: :done
    tool_calls = update_tool_status(socket.assigns.tool_calls, tool_id, status, nil, content)
    messages = socket.assigns.messages ++ [%{role: :tool, tool_id: tool_id, content: content, is_error: is_error, collapsed: true}]
    {:noreply, assign(socket, tool_calls: tool_calls, messages: messages, tool_count: socket.assigns.tool_count + 1)}
  end

  def handle_info({:agent_event, _id, :message_complete}, socket) do
    socket =
      if socket.assigns.current_text != "" do
        messages = socket.assigns.messages ++ [%{role: :assistant, content: socket.assigns.current_text}]
        assign(socket, messages: messages, current_text: "")
      else
        socket
      end

    conversations = Agent.list_conversations(15)
    {:noreply, assign(socket, streaming: false, tool_calls: [], conversations: conversations)}
  end

  def handle_info({:agent_event, _id, {:model_selected, model}}, socket) do
    {:noreply, assign(socket, current_model: model)}
  end

  def handle_info({:agent_event, _id, {:model_override, override}}, socket) do
    {:noreply, assign(socket, model_override: override)}
  end

  def handle_info({:agent_event, _id, {:usage_update, input_tokens, output_tokens, model}}, socket) do
    cost = ModelRouter.estimate_cost(model, input_tokens, output_tokens)
    {:noreply, assign(socket, input_tokens: input_tokens, output_tokens: output_tokens, cost: cost)}
  end

  def handle_info({:agent_event, _id, {:error, error_msg}}, socket) do
    messages = socket.assigns.messages ++ [%{role: :error, content: error_msg}]
    {:noreply, assign(socket, messages: messages, streaming: false)}
  end

  def handle_info(_msg, socket), do: {:noreply, socket}

  # ── Helpers ──

  defp update_tool_status(tool_calls, id, status, input \\ nil, result \\ nil) do
    Enum.map(tool_calls, fn tc ->
      if tc.id == id do
        tc
        |> Map.put(:status, status)
        |> then(fn tc -> if input, do: Map.put(tc, :input, input), else: tc end)
        |> then(fn tc -> if result, do: Map.put(tc, :result, result), else: tc end)
      else
        tc
      end
    end)
  end

  defp load_projects do
    try do
      Cortex.Projects.list_projects()
      |> Enum.map(fn p -> %{name: p.name, path: p.path} end)
    rescue
      _ -> []
    end
  end

  defp rebuild_display_messages(api_messages) do
    Enum.flat_map(api_messages, fn
      %{"role" => "user", "content" => content} when is_binary(content) ->
        [%{role: :user, content: content}]

      %{"role" => "user", "content" => blocks} when is_list(blocks) ->
        # Tool results
        Enum.map(blocks, fn
          %{"type" => "tool_result", "tool_use_id" => id, "content" => content} ->
            %{role: :tool, tool_id: id, content: content || "", is_error: false, collapsed: true}
          _ -> nil
        end)
        |> Enum.reject(&is_nil/1)

      %{"role" => "assistant", "content" => blocks} when is_list(blocks) ->
        Enum.map(blocks, fn
          %{"type" => "text", "text" => text} ->
            %{role: :assistant, content: text}
          _ -> nil
        end)
        |> Enum.reject(&is_nil/1)

      _ -> []
    end)
  end

  defp message_count(messages, role), do: Enum.count(messages, &(&1.role == role))

  defp format_cwd(path) do
    home = System.user_home!()
    if String.starts_with?(path, home), do: "~" <> String.trim_leading(path, home), else: path
  end

  defp render_text(text) do
    text
    |> String.split(~r/```(\w*)\n(.*?)```/s, include_captures: true)
    |> Enum.map(fn part ->
      case Regex.run(~r/^```(\w*)\n(.*?)```$/s, part) do
        [_, lang, code] ->
          lang_label = if lang != "", do: lang, else: "code"
          {:safe,
           ~s(<div class="my-2 rounded-md border border-[#1a1a1a] overflow-hidden">) <>
             ~s(<div class="flex items-center px-3 py-1.5 bg-[#111] border-b border-[#1a1a1a]">) <>
             ~s(<span class="font-mono text-[10px] text-[#5a5a5a] uppercase tracking-wider">#{lang_label}</span>) <>
             ~s(</div>) <>
             ~s(<pre class="px-3 py-2.5 font-mono text-xs text-[#c8b890] overflow-x-auto leading-relaxed">#{escape_html(code)}</pre>) <>
             ~s(</div>)}
        _ ->
          {:safe, format_inline_text(part)}
      end
    end)
  end

  defp format_inline_text(text) do
    text
    |> escape_html()
    |> String.replace(~r/`([^`]+)`/, ~s(<code class="px-1.5 py-0.5 rounded bg-[#111] border border-[#1a1a1a] text-[#ffd04a] text-xs">\\1</code>))
    |> String.replace(~r/\*\*(.+?)\*\*/, "<strong class=\"text-[#e8dcc0]\">\\1</strong>")
  end

  defp escape_html(text) do
    text
    |> String.replace("&", "&amp;")
    |> String.replace("<", "&lt;")
    |> String.replace(">", "&gt;")
    |> String.replace("\"", "&quot;")
  end

  defp tool_icon("file_read"), do: "R"
  defp tool_icon("file_write"), do: "W"
  defp tool_icon("file_edit"), do: "E"
  defp tool_icon("bash"), do: "$"
  defp tool_icon("grep"), do: "?"
  defp tool_icon("glob"), do: "*"
  defp tool_icon(_), do: ">"

  defp tool_status_color(:pending), do: "bg-[#5a5a5a]"
  defp tool_status_color(:ready), do: "bg-[#ffd04a]"
  defp tool_status_color(:executing), do: "bg-[#ffd04a] animate-pulse"
  defp tool_status_color(:done), do: "bg-[#5ea85e]"
  defp tool_status_color(:error), do: "bg-[#e05252]"

  defp tool_status_label(:pending), do: "preparing..."
  defp tool_status_label(:ready), do: "awaiting approval"
  defp tool_status_label(:executing), do: "running"
  defp tool_status_label(:done), do: "done"
  defp tool_status_label(:error), do: "failed"

  defp inspect_input(input) when is_map(input) do
    Enum.map_join(input, "  ", fn {k, v} ->
      val = if is_binary(v) and byte_size(v) > 80, do: String.slice(v, 0, 80) <> "...", else: v
      "#{k}: #{inspect(val)}"
    end)
  end

  defp inspect_input(other), do: inspect(other)

  defp truncate_display(c) when byte_size(c) > 3000, do: String.slice(c, 0, 3000) <> "\n... (truncated)"
  defp truncate_display(c), do: c

  defp tool_result_preview(content) do
    lines = String.split(content, "\n")
    preview = lines |> Enum.take(2) |> Enum.join(" ") |> String.slice(0, 120)
    if length(lines) > 2 or String.length(content) > 120, do: preview <> "...", else: preview
  end

  # ── Render ──

  @impl true
  def render(assigns) do
    ~H"""
    <div id="agent-root" class="flex flex-col h-screen bg-[#050505] text-[#e8dcc0]">
      <%!-- Header --%>
      <header class="flex items-center justify-between px-5 py-2.5 border-b border-[#1a1a1a]">
        <div class="flex items-center gap-3">
          <a href="/dashboard" class="w-7 h-7 rounded-md bg-[#0a0a0a] border border-[#1a1a1a] flex items-center justify-center text-[#5a5a5a] hover:text-[#ffd04a] hover:border-[#ffd04a]/30 transition-all text-sm">
            &larr;
          </a>
          <h1 class="text-[#ffd04a] font-mono text-base font-bold tracking-tight">cortex agent</h1>
          <span
            class="px-1.5 py-0.5 rounded font-mono text-[10px] font-medium uppercase tracking-wider"
            style={"background: #{ModelRouter.color(@current_model)}15; color: #{ModelRouter.color(@current_model)}"}
          >
            {ModelRouter.label(@current_model)}
          </span>
        </div>
        <div class="flex items-center gap-3">
          <div :if={@streaming} class="flex items-center gap-0.5">
            <span class="w-1 h-1 rounded-full bg-[#ffd04a] animate-bounce" style="animation-delay: 0ms" />
            <span class="w-1 h-1 rounded-full bg-[#ffd04a] animate-bounce" style="animation-delay: 150ms" />
            <span class="w-1 h-1 rounded-full bg-[#ffd04a] animate-bounce" style="animation-delay: 300ms" />
          </div>
          <span :if={@input_tokens > 0} class="font-mono text-[10px] text-[#3a3a3a]">
            {ModelRouter.format_tokens(@input_tokens)}↑ {ModelRouter.format_tokens(@output_tokens)}↓
          </span>
          <span :if={@cost > 0} class="font-mono text-[10px] text-[#ffd04a]/60">
            {ModelRouter.format_cost(@cost)}
          </span>
          <span class="font-mono text-[10px] text-[#2a2a2a]">{message_count(@messages, :user)} turns</span>
        </div>
      </header>

      <%!-- Controls bar --%>
      <div class="flex items-center gap-2 px-5 py-1.5 border-b border-[#0f0f0f] bg-[#080808]">
        <%!-- Project picker --%>
        <select
          :if={@projects != []}
          name="project"
          phx-change="change_project"
          class="bg-[#0a0a0a] border border-[#1a1a1a] rounded px-2 py-0.5 font-mono text-[10px] text-[#5a5a5a] focus:outline-none focus:border-[#ffd04a]/30 cursor-pointer"
        >
          <option value={System.user_home!()} selected={@cwd == System.user_home!()}>~ (home)</option>
          <option :for={p <- @projects} value={p.path} selected={@cwd == p.path}>
            {p.name}
          </option>
        </select>

        <span class="text-[#1a1a1a]">|</span>

        <%!-- Model selector --%>
        <select
          name="model"
          phx-change="change_model"
          class="bg-[#0a0a0a] border border-[#1a1a1a] rounded px-2 py-0.5 font-mono text-[10px] text-[#5a5a5a] focus:outline-none focus:border-[#ffd04a]/30 cursor-pointer"
        >
          <option value="auto" selected={@model_override == nil}>auto-route</option>
          <option value={ModelRouter.haiku()} selected={@model_override == ModelRouter.haiku()}>haiku</option>
          <option value={ModelRouter.sonnet()} selected={@model_override == ModelRouter.sonnet()}>sonnet</option>
          <option value={ModelRouter.opus()} selected={@model_override == ModelRouter.opus()}>opus</option>
        </select>

        <span class="text-[#1a1a1a]">|</span>

        <%!-- Conversation picker --%>
        <select
          name="id"
          phx-change="load_conversation"
          class="bg-[#0a0a0a] border border-[#1a1a1a] rounded px-2 py-0.5 font-mono text-[10px] text-[#5a5a5a] focus:outline-none focus:border-[#ffd04a]/30 cursor-pointer max-w-[200px]"
        >
          <option value="new">+ new conversation</option>
          <option :for={conv <- @conversations} value={conv.id} selected={conv.id == @conversation_id}>
            {String.slice(conv.title || "untitled", 0, 40)}
          </option>
        </select>
      </div>

      <%!-- Messages --%>
      <div id="chat-messages" phx-hook="AgentChat" class="flex-1 overflow-y-auto px-5 py-6 scroll-smooth">
        <div :if={@messages == []} class="flex items-center justify-center h-full">
          <div class="text-center max-w-lg">
            <div class="w-12 h-12 rounded-lg bg-[#ffd04a]/10 border border-[#ffd04a]/20 flex items-center justify-center mx-auto mb-4">
              <span class="text-[#ffd04a] text-xl font-bold font-mono">C</span>
            </div>
            <p class="text-[#e8dcc0] font-mono text-lg mb-1.5">cortex agent</p>
            <p class="text-[#5a5a5a] font-mono text-xs mb-6 leading-relaxed">
              AI coding agent with full filesystem access. Auto-routes to the right model.
            </p>
            <div class="grid grid-cols-3 gap-2 max-w-sm mx-auto">
              <div class="px-2 py-2 rounded-md bg-[#0a0a0a] border border-[#1a1a1a]">
                <span class="text-[#5ea85e] font-mono text-[10px] font-bold block mb-0.5">HAIKU</span>
                <span class="text-[#3a3a3a] font-mono text-[10px]">lookups</span>
              </div>
              <div class="px-2 py-2 rounded-md bg-[#0a0a0a] border border-[#1a1a1a]">
                <span class="text-[#ffd04a] font-mono text-[10px] font-bold block mb-0.5">SONNET</span>
                <span class="text-[#3a3a3a] font-mono text-[10px]">code gen</span>
              </div>
              <div class="px-2 py-2 rounded-md bg-[#0a0a0a] border border-[#1a1a1a]">
                <span class="text-[#c084fc] font-mono text-[10px] font-bold block mb-0.5">OPUS</span>
                <span class="text-[#3a3a3a] font-mono text-[10px]">architecture</span>
              </div>
            </div>
          </div>
        </div>

        <div class="max-w-3xl mx-auto space-y-5">
          <div :for={msg <- @messages}><.message_bubble msg={msg} /></div>
          <div :for={tc <- @tool_calls}><.tool_card tool={tc} /></div>
          <div :if={@current_text != ""}>
            <div class="flex gap-3">
              <div class="w-6 h-6 rounded-md bg-[#ffd04a] flex items-center justify-center flex-shrink-0 mt-0.5">
                <span class="text-[#050505] text-[10px] font-bold font-mono">C</span>
              </div>
              <div class="flex-1 min-w-0 font-mono text-sm leading-relaxed" id="streaming-text">
                {render_text(@current_text)}
                <span class="inline-block w-1.5 h-4 bg-[#ffd04a] animate-pulse ml-0.5 align-text-bottom" />
              </div>
            </div>
          </div>
        </div>
        <div id="scroll-anchor" class="h-4" />
      </div>

      <%!-- Status bar --%>
      <div class="px-5 py-1 border-t border-[#0f0f0f] bg-[#080808]">
        <div class="max-w-3xl mx-auto flex items-center justify-between">
          <span class="font-mono text-[10px] text-[#2a2a2a] tracking-wider">{format_cwd(@cwd)}</span>
          <span class="font-mono text-[10px] text-[#2a2a2a] tracking-wider">
            {if @tool_count > 0, do: "#{@tool_count} tools  ·  ", else: ""}cortex v0.1
          </span>
        </div>
      </div>

      <%!-- Input --%>
      <div class="border-t border-[#1a1a1a] px-5 py-3 bg-[#080808]">
        <form phx-submit="submit" phx-change="update_input" class="max-w-3xl mx-auto">
          <div class="flex gap-2 items-end">
            <div class="flex-1 relative">
              <textarea
                id="agent-input"
                name="message"
                phx-hook="AgentInput"
                rows="1"
                placeholder={if @streaming, do: "Waiting for response...", else: "Message Cortex..."}
                disabled={@streaming}
                autocomplete="off"
                class={[
                  "w-full bg-[#0a0a0a] border border-[#1a1a1a] rounded-lg px-4 py-2.5 pr-12",
                  "font-mono text-sm text-[#e8dcc0] placeholder-[#2a2a2a]",
                  "focus:outline-none focus:border-[#ffd04a]/50 focus:ring-1 focus:ring-[#ffd04a]/20",
                  "disabled:opacity-40 disabled:cursor-not-allowed",
                  "transition-all resize-none overflow-hidden",
                  "min-h-[42px] max-h-[200px]"
                ]}
              >{@input}</textarea>
              <div class="absolute right-2 bottom-2">
                <span :if={!@streaming} class="text-[#2a2a2a] font-mono text-[10px]">enter</span>
              </div>
            </div>
            <button
              type="submit"
              disabled={@streaming || @input == ""}
              class={[
                "w-9 h-9 rounded-lg flex items-center justify-center flex-shrink-0",
                "bg-[#ffd04a] text-[#050505]",
                "hover:bg-[#ffe07a] active:scale-95",
                "disabled:opacity-20 disabled:cursor-not-allowed disabled:active:scale-100",
                "transition-all"
              ]}
            >
              <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 20 20" fill="currentColor" class="w-4 h-4">
                <path d="M3.105 2.288a.75.75 0 0 0-.826.95l1.414 4.926A1.5 1.5 0 0 0 5.135 9.25h6.115a.75.75 0 0 1 0 1.5H5.135a1.5 1.5 0 0 0-1.442 1.086l-1.414 4.926a.75.75 0 0 0 .826.95 28.897 28.897 0 0 0 15.293-7.155.75.75 0 0 0 0-1.114A28.897 28.897 0 0 0 3.105 2.288Z" />
              </svg>
            </button>
          </div>
        </form>
      </div>
    </div>
    """
  end

  # ── Components ──

  defp message_bubble(%{msg: %{role: :user}} = assigns) do
    ~H"""
    <div class="flex justify-end">
      <div class="bg-[#111] border border-[#1a1a1a] rounded-lg px-4 py-2.5 max-w-lg">
        <p class="font-mono text-sm whitespace-pre-wrap leading-relaxed">{@msg.content}</p>
      </div>
    </div>
    """
  end

  defp message_bubble(%{msg: %{role: :assistant}} = assigns) do
    ~H"""
    <div class="flex gap-3">
      <div class="w-6 h-6 rounded-md bg-[#ffd04a] flex items-center justify-center flex-shrink-0 mt-0.5">
        <span class="text-[#050505] text-[10px] font-bold font-mono">C</span>
      </div>
      <div class="flex-1 min-w-0 font-mono text-sm leading-relaxed">{render_text(@msg.content)}</div>
    </div>
    """
  end

  defp message_bubble(%{msg: %{role: :tool}} = assigns) do
    collapsed = Map.get(assigns.msg, :collapsed, true)
    assigns = assign(assigns, :collapsed, collapsed)

    ~H"""
    <div class="ml-9">
      <button
        phx-click="toggle_tool_result"
        phx-value-id={@msg.tool_id}
        class={[
          "w-full text-left font-mono text-xs px-3 py-1.5 rounded-md border transition-colors",
          if(@msg.is_error,
            do: "bg-[#0f0808] border-[#e05252]/20 text-[#e05252]/70 hover:border-[#e05252]/40",
            else: "bg-[#080f08] border-[#5ea85e]/20 text-[#5ea85e]/70 hover:border-[#5ea85e]/40"
          )
        ]}
      >
        <div class="flex items-center justify-between">
          <span class="truncate">{if @collapsed, do: tool_result_preview(@msg.content), else: "collapse"}</span>
          <span class="text-[#3a3a3a] ml-2 flex-shrink-0">{if @collapsed, do: "+", else: "-"}</span>
        </div>
        <pre :if={!@collapsed} class="mt-2 whitespace-pre-wrap break-all text-[11px] leading-relaxed border-t border-current/10 pt-2">{truncate_display(@msg.content)}</pre>
      </button>
    </div>
    """
  end

  defp message_bubble(%{msg: %{role: :error}} = assigns) do
    ~H"""
    <div class="flex gap-3">
      <div class="w-6 h-6 rounded-md bg-[#e05252] flex items-center justify-center flex-shrink-0 mt-0.5">
        <span class="text-[#050505] text-[10px] font-bold font-mono">!</span>
      </div>
      <div class="font-mono text-sm text-[#e05252]/80 leading-relaxed">{@msg.content}</div>
    </div>
    """
  end

  defp tool_card(assigns) do
    ~H"""
    <div class="ml-9">
      <div class="border border-[#1a1a1a] rounded-md px-3 py-2 bg-[#080808]">
        <div class="flex items-center justify-between">
          <div class="flex items-center gap-2">
            <div class={[
              "w-5 h-5 rounded flex items-center justify-center font-mono text-[10px] font-bold",
              if(@tool.status == :executing, do: "bg-[#ffd04a]/20 text-[#ffd04a] animate-pulse", else: "bg-[#1a1a1a] text-[#5a5a5a]")
            ]}>
              {tool_icon(@tool.name)}
            </div>
            <span class="font-mono text-xs text-[#e8dcc0]/60">{@tool.name}</span>
            <span class={["w-1.5 h-1.5 rounded-full", tool_status_color(@tool.status)]} />
            <span class="font-mono text-[10px] text-[#3a3a3a]">{tool_status_label(@tool.status)}</span>
          </div>
          <div :if={@tool.status == :ready} class="flex gap-1">
            <button phx-click="approve_tool" phx-value-id={@tool.id} class="px-2 py-0.5 rounded text-[10px] font-mono font-medium bg-[#5ea85e]/10 text-[#5ea85e] hover:bg-[#5ea85e]/20 transition-colors">run</button>
            <button phx-click="deny_tool" phx-value-id={@tool.id} class="px-2 py-0.5 rounded text-[10px] font-mono font-medium bg-[#e05252]/10 text-[#e05252] hover:bg-[#e05252]/20 transition-colors">skip</button>
          </div>
        </div>
        <div :if={Map.get(@tool, :input)} class="mt-1.5 pl-7">
          <span class="font-mono text-[10px] text-[#3a3a3a] leading-relaxed">{inspect_input(@tool.input)}</span>
        </div>
      </div>
    </div>
    """
  end
end
