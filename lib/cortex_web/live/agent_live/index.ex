defmodule CortexWeb.AgentLive.Index do
  use CortexWeb, :live_view

  alias Cortex.Agent

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
      |> assign(:page_title, "Cortex Agent")

    if connected?(socket) do
      {:ok, session_id} = Agent.start_session(cwd: System.user_home!())
      Phoenix.PubSub.subscribe(Cortex.PubSub, "agent:#{session_id}")
      {:ok, assign(socket, :session_id, session_id)}
    else
      {:ok, socket}
    end
  end

  @impl true
  def terminate(_reason, socket) do
    if socket.assigns[:session_id] do
      Agent.stop_session(socket.assigns.session_id)
    end

    :ok
  end

  # ── Events from UI ──

  @impl true
  def handle_event("submit", %{"message" => message}, socket)
      when message != "" do
    case socket.assigns.session_id do
      nil ->
        {:noreply, socket}

      session_id ->
        Agent.send_message(session_id, message)
        messages = socket.assigns.messages ++ [%{role: :user, content: message}]
        {:noreply, assign(socket, messages: messages, input: "", streaming: true)}
    end
  end

  def handle_event("submit", _params, socket), do: {:noreply, socket}

  def handle_event("update_input", %{"message" => value}, socket) do
    {:noreply, assign(socket, :input, value)}
  end

  def handle_event("approve_tool", %{"id" => tool_id}, socket) do
    if socket.assigns.session_id do
      Agent.approve_tool(socket.assigns.session_id, tool_id)
    end

    {:noreply, socket}
  end

  def handle_event("deny_tool", %{"id" => tool_id}, socket) do
    if socket.assigns.session_id do
      Agent.deny_tool(socket.assigns.session_id, tool_id)
    end

    {:noreply, socket}
  end

  def handle_event("keydown", %{"key" => "Enter", "shiftKey" => false}, socket) do
    {:noreply, push_event(socket, "submit-form", %{})}
  end

  def handle_event("keydown", _params, socket), do: {:noreply, socket}

  # ── Events from Agent Session (via PubSub) ──

  @impl true
  def handle_info({:agent_event, _id, {:user_message, _content}}, socket) do
    {:noreply, socket}
  end

  def handle_info({:agent_event, _id, :assistant_start}, socket) do
    {:noreply, assign(socket, streaming: true, current_text: "")}
  end

  def handle_info({:agent_event, _id, {:text_start, _idx}}, socket) do
    {:noreply, assign(socket, current_text: "")}
  end

  def handle_info({:agent_event, _id, {:text_delta, text}}, socket) do
    new_text = socket.assigns.current_text <> text
    socket = assign(socket, current_text: new_text)
    {:noreply, push_event(socket, "text-delta", %{text: text})}
  end

  def handle_info({:agent_event, _id, :text_done}, socket) do
    messages =
      socket.assigns.messages ++ [%{role: :assistant, content: socket.assigns.current_text}]

    {:noreply, assign(socket, messages: messages, current_text: "")}
  end

  def handle_info({:agent_event, _id, {:tool_start, tool}}, socket) do
    tool_calls = socket.assigns.tool_calls ++ [%{id: tool.id, name: tool.name, status: :pending}]
    {:noreply, assign(socket, tool_calls: tool_calls)}
  end

  def handle_info({:agent_event, _id, {:tool_ready, tool}}, socket) do
    tool_calls = update_tool_status(socket.assigns.tool_calls, tool.id, :ready, tool.input)
    {:noreply, assign(socket, tool_calls: tool_calls)}
  end

  def handle_info({:agent_event, _id, {:tool_executing, tool}}, socket) do
    tool_calls = update_tool_status(socket.assigns.tool_calls, tool.id, :executing)
    {:noreply, assign(socket, tool_calls: tool_calls)}
  end

  def handle_info({:agent_event, _id, {:tool_result, tool_id, content, is_error}}, socket) do
    status = if is_error, do: :error, else: :done
    tool_calls = update_tool_status(socket.assigns.tool_calls, tool_id, status, nil, content)

    messages =
      socket.assigns.messages ++
        [%{role: :tool, tool_id: tool_id, content: content, is_error: is_error}]

    {:noreply, assign(socket, tool_calls: tool_calls, messages: messages)}
  end

  def handle_info({:agent_event, _id, :message_complete}, socket) do
    socket =
      if socket.assigns.current_text != "" do
        messages =
          socket.assigns.messages ++
            [%{role: :assistant, content: socket.assigns.current_text}]

        assign(socket, messages: messages, current_text: "")
      else
        socket
      end

    {:noreply, assign(socket, streaming: false, tool_calls: [])}
  end

  def handle_info({:agent_event, _id, {:error, error_msg}}, socket) do
    messages = socket.assigns.messages ++ [%{role: :error, content: error_msg}]
    {:noreply, assign(socket, messages: messages, streaming: false)}
  end

  def handle_info({:agent_event, _id, {:session_started, _}}, socket) do
    {:noreply, socket}
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

  # ── Render ──

  @impl true
  def render(assigns) do
    ~H"""
    <div id="agent-root" class="flex flex-col h-screen bg-[#050505] text-[#e8dcc0]">
      <%!-- Header --%>
      <header class="flex items-center justify-between px-4 py-3 border-b border-[#1a1a1a]">
        <div class="flex items-center gap-3">
          <a href="/dashboard" class="text-[#5a5a5a] hover:text-[#ffd04a] transition-colors">
            &larr;
          </a>
          <h1 class="text-[#ffd04a] font-mono text-lg font-bold tracking-tight">
            cortex agent
          </h1>
          <span class="text-[#3a3a3a] font-mono text-xs">
            sonnet 4.6
          </span>
        </div>
        <div class="flex items-center gap-2">
          <span :if={@streaming} class="text-[#ffd04a] text-xs font-mono animate-pulse">
            thinking...
          </span>
          <span class="text-[#3a3a3a] font-mono text-xs">
            {length(@messages)} msgs
          </span>
        </div>
      </header>

      <%!-- Messages --%>
      <div
        id="chat-messages"
        phx-hook="AgentChat"
        class="flex-1 overflow-y-auto px-4 py-4 space-y-4 scroll-smooth"
      >
        <%!-- Welcome --%>
        <div :if={@messages == []} class="flex items-center justify-center h-full">
          <div class="text-center max-w-md">
            <p class="text-[#ffd04a] font-mono text-xl mb-2">cortex agent</p>
            <p class="text-[#5a5a5a] font-mono text-sm">
              Your AI coding agent. Has file read/write/edit, bash, grep, and glob tools.
              Working directory: ~
            </p>
          </div>
        </div>

        <%!-- Message history --%>
        <div :for={msg <- @messages} class="max-w-3xl mx-auto">
          <.message_bubble msg={msg} />
        </div>

        <%!-- Active tool calls --%>
        <div :for={tc <- @tool_calls} class="max-w-3xl mx-auto">
          <.tool_card tool={tc} />
        </div>

        <%!-- Streaming text --%>
        <div :if={@current_text != ""} class="max-w-3xl mx-auto">
          <div class="flex gap-3">
            <div class="w-6 h-6 rounded bg-[#ffd04a] flex items-center justify-center flex-shrink-0 mt-0.5">
              <span class="text-[#050505] text-xs font-bold">C</span>
            </div>
            <div class="font-mono text-sm whitespace-pre-wrap flex-1" id="streaming-text">
              {@current_text}<span class="animate-pulse text-[#ffd04a]">&#x2588;</span>
            </div>
          </div>
        </div>

        <div id="scroll-anchor" class="h-1" />
      </div>

      <%!-- Input --%>
      <div class="border-t border-[#1a1a1a] px-4 py-3">
        <form phx-submit="submit" phx-change="update_input" class="max-w-3xl mx-auto flex gap-2">
          <input
            type="text"
            name="message"
            value={@input}
            phx-keydown="keydown"
            placeholder={if @streaming, do: "Waiting for response...", else: "Ask Cortex anything..."}
            disabled={@streaming}
            autocomplete="off"
            class={[
              "flex-1 bg-[#0a0a0a] border border-[#1a1a1a] rounded-md px-4 py-2.5",
              "font-mono text-sm text-[#e8dcc0] placeholder-[#3a3a3a]",
              "focus:outline-none focus:border-[#ffd04a] focus:ring-1 focus:ring-[#ffd04a]/30",
              "disabled:opacity-50 disabled:cursor-not-allowed",
              "transition-colors"
            ]}
          />
          <button
            type="submit"
            disabled={@streaming || @input == ""}
            class={[
              "px-4 py-2.5 rounded-md font-mono text-sm font-bold",
              "bg-[#ffd04a] text-[#050505]",
              "hover:bg-[#ffe07a] active:bg-[#ccb03b]",
              "disabled:opacity-30 disabled:cursor-not-allowed",
              "transition-colors"
            ]}
          >
            Send
          </button>
        </form>
      </div>
    </div>
    """
  end

  # ── Components ──

  defp message_bubble(%{msg: %{role: :user}} = assigns) do
    ~H"""
    <div class="flex gap-3 justify-end">
      <div class="bg-[#1a1a1a] border border-[#2a2a2a] rounded-md px-4 py-2 max-w-lg">
        <p class="font-mono text-sm whitespace-pre-wrap">{@msg.content}</p>
      </div>
      <div class="w-6 h-6 rounded bg-[#5a5a5a] flex items-center justify-center flex-shrink-0 mt-0.5">
        <span class="text-[#050505] text-xs font-bold">J</span>
      </div>
    </div>
    """
  end

  defp message_bubble(%{msg: %{role: :assistant}} = assigns) do
    ~H"""
    <div class="flex gap-3">
      <div class="w-6 h-6 rounded bg-[#ffd04a] flex items-center justify-center flex-shrink-0 mt-0.5">
        <span class="text-[#050505] text-xs font-bold">C</span>
      </div>
      <div class="font-mono text-sm whitespace-pre-wrap flex-1">
        {@msg.content}
      </div>
    </div>
    """
  end

  defp message_bubble(%{msg: %{role: :tool}} = assigns) do
    ~H"""
    <div class="flex gap-3">
      <div class="w-6 h-6 flex-shrink-0" />
      <div class={[
        "font-mono text-xs px-3 py-2 rounded-md border max-w-full overflow-x-auto",
        if(@msg.is_error,
          do: "bg-[#1a0a0a] border-[#e05252]/30 text-[#e05252]",
          else: "bg-[#0a1a0a] border-[#5ea85e]/30 text-[#5ea85e]"
        )
      ]}>
        <pre class="whitespace-pre-wrap break-all">{truncate_display(@msg.content)}</pre>
      </div>
    </div>
    """
  end

  defp message_bubble(%{msg: %{role: :error}} = assigns) do
    ~H"""
    <div class="flex gap-3">
      <div class="w-6 h-6 rounded bg-[#e05252] flex items-center justify-center flex-shrink-0 mt-0.5">
        <span class="text-[#050505] text-xs font-bold">!</span>
      </div>
      <div class="font-mono text-sm text-[#e05252]">
        {@msg.content}
      </div>
    </div>
    """
  end

  defp tool_card(assigns) do
    ~H"""
    <div class="flex gap-3">
      <div class="w-6 h-6 flex-shrink-0" />
      <div class="border border-[#1a1a1a] rounded-md px-3 py-2 bg-[#0a0a0a] w-full">
        <div class="flex items-center justify-between">
          <div class="flex items-center gap-2">
            <span class={[
              "w-2 h-2 rounded-full",
              tool_status_color(@tool.status)
            ]} />
            <span class="font-mono text-xs text-[#ffd04a]">{@tool.name}</span>
            <span class="font-mono text-xs text-[#3a3a3a]">{tool_status_label(@tool.status)}</span>
          </div>
          <div :if={@tool.status == :ready} class="flex gap-1">
            <button
              phx-click="approve_tool"
              phx-value-id={@tool.id}
              class="px-2 py-0.5 rounded text-xs font-mono bg-[#5ea85e]/20 text-[#5ea85e] hover:bg-[#5ea85e]/30"
            >
              run
            </button>
            <button
              phx-click="deny_tool"
              phx-value-id={@tool.id}
              class="px-2 py-0.5 rounded text-xs font-mono bg-[#e05252]/20 text-[#e05252] hover:bg-[#e05252]/30"
            >
              deny
            </button>
          </div>
        </div>
        <div :if={Map.get(@tool, :input)} class="mt-1">
          <pre class="font-mono text-xs text-[#5a5a5a] whitespace-pre-wrap break-all">{inspect_input(@tool.input)}</pre>
        </div>
      </div>
    </div>
    """
  end

  defp tool_status_color(:pending), do: "bg-[#5a5a5a]"
  defp tool_status_color(:ready), do: "bg-[#ffd04a]"
  defp tool_status_color(:executing), do: "bg-[#ffd04a] animate-pulse"
  defp tool_status_color(:done), do: "bg-[#5ea85e]"
  defp tool_status_color(:error), do: "bg-[#e05252]"

  defp tool_status_label(:pending), do: "preparing..."
  defp tool_status_label(:ready), do: "awaiting approval"
  defp tool_status_label(:executing), do: "executing..."
  defp tool_status_label(:done), do: "done"
  defp tool_status_label(:error), do: "failed"

  defp inspect_input(input) when is_map(input) do
    input
    |> Enum.map(fn {k, v} ->
      val = if is_binary(v) and byte_size(v) > 100, do: String.slice(v, 0, 100) <> "...", else: v
      "#{k}: #{inspect(val)}"
    end)
    |> Enum.join("\n")
  end

  defp inspect_input(other), do: inspect(other)

  defp truncate_display(content) when byte_size(content) > 2000 do
    String.slice(content, 0, 2000) <> "\n... (truncated)"
  end

  defp truncate_display(content), do: content
end
