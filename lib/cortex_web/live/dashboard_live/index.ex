defmodule CortexWeb.DashboardLive.Index do
  use CortexWeb, :live_view

  alias Cortex.Terminals
  alias Cortex.Projects

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket) do
      Phoenix.PubSub.subscribe(Cortex.PubSub, "terminal:sessions")
    end

    sessions = Terminals.list_sessions()
    session_map = Map.new(sessions, fn s -> {s.id, s} end)
    session_order = Enum.map(sessions, & &1.id)

    if connected?(socket) do
      Enum.each(session_order, fn id ->
        Phoenix.PubSub.subscribe(Cortex.PubSub, "terminal:#{id}:output")
      end)
    end

    socket =
      socket
      |> assign(:sessions, session_map)
      |> assign(:session_order, session_order)
      |> assign(:focused_id, nil)
      |> assign(:command_palette_open, false)
      |> assign(:projects, Projects.list_projects())
      |> assign(:search_query, "")
      |> assign(:page_title, "Cortex")

    {:ok, socket}
  end

  # Events

  @impl true
  def handle_event("new_session", _params, socket) do
    Terminals.create_session()
    {:noreply, assign(socket, command_palette_open: false, search_query: "")}
  end

  def handle_event("new_project_session", %{"name" => name}, socket) do
    project = Projects.get_project(name)

    if project do
      Terminals.create_session(%{project: project, title: project.name})
    end

    {:noreply, assign(socket, command_palette_open: false, search_query: "")}
  end

  def handle_event("kill_session", %{"id" => id}, socket) do
    Terminals.kill_session(id)
    remove_session(socket, id)
  end

  def handle_event("kill_focused", _params, socket) do
    case socket.assigns.focused_id do
      nil ->
        {:noreply, socket}

      id ->
        Terminals.kill_session(id)

        remove_session(socket, id)
        |> then(fn {:noreply, s} -> {:noreply, assign(s, :focused_id, nil)} end)
    end
  end

  def handle_event("focus", %{"id" => id}, socket) do
    {:noreply, assign(socket, :focused_id, id)}
  end

  def handle_event("unfocus", _params, socket) do
    {:noreply, assign(socket, :focused_id, nil)}
  end

  def handle_event("focus_by_index", %{"index" => index}, socket) do
    case Enum.at(socket.assigns.session_order, index) do
      nil -> {:noreply, socket}
      id -> {:noreply, assign(socket, :focused_id, id)}
    end
  end

  def handle_event("toggle_command_palette", _params, socket) do
    open = !socket.assigns.command_palette_open
    {:noreply, assign(socket, command_palette_open: open, search_query: "")}
  end

  def handle_event("close_command_palette", _params, socket) do
    {:noreply, assign(socket, command_palette_open: false, search_query: "")}
  end

  def handle_event("search_projects", %{"query" => query}, socket) do
    {:noreply, assign(socket, :search_query, query)}
  end

  def handle_event("terminal_input", %{"session_id" => id, "data" => data}, socket) do
    decoded = Base.decode64!(data)
    Terminals.write(id, decoded)
    {:noreply, socket}
  end

  def handle_event("resize", %{"session_id" => id, "cols" => cols, "rows" => rows}, socket) do
    Terminals.resize(id, cols, rows)
    {:noreply, socket}
  end

  # PubSub

  @impl true
  def handle_info({:session_started, id, info}, socket) do
    Phoenix.PubSub.subscribe(Cortex.PubSub, "terminal:#{id}:output")

    case Terminals.get_scrollback(id) do
      data when is_binary(data) and byte_size(data) > 0 ->
        send(self(), {:send_scrollback, id, data})

      _ ->
        :ok
    end

    sessions = Map.put(socket.assigns.sessions, id, info)
    order = socket.assigns.session_order ++ [id]

    {:noreply, assign(socket, sessions: sessions, session_order: order)}
  end

  def handle_info({:session_exited, id, exit_code}, socket) do
    sessions =
      Map.update(socket.assigns.sessions, id, %{}, fn s ->
        Map.merge(s, %{status: :exited, exit_code: exit_code})
      end)

    # Auto-remove dead sessions after 3 seconds
    Process.send_after(self(), {:remove_session, id}, 3000)

    {:noreply, assign(socket, :sessions, sessions)}
  end

  def handle_info({:remove_session, id}, socket) do
    remove_session(socket, id)
  end

  def handle_info({:terminal_output, id, data}, socket) do
    {:noreply, push_event(socket, "terminal_output:#{id}", %{data: Base.encode64(data)})}
  end

  def handle_info({:send_scrollback, id, data}, socket) do
    {:noreply, push_event(socket, "terminal_scrollback:#{id}", %{data: Base.encode64(data)})}
  end

  # Helpers

  defp remove_session(socket, id) do
    sessions = Map.delete(socket.assigns.sessions, id)
    order = List.delete(socket.assigns.session_order, id)

    focused =
      if socket.assigns.focused_id == id, do: nil, else: socket.assigns.focused_id

    {:noreply, assign(socket, sessions: sessions, session_order: order, focused_id: focused)}
  end

  defp grid_class(count) when count <= 1, do: "grid-cols-1"
  defp grid_class(count) when count <= 2, do: "grid-cols-2"
  defp grid_class(count) when count <= 4, do: "grid-cols-2"
  defp grid_class(count) when count <= 6, do: "grid-cols-3"
  defp grid_class(_count), do: "grid-cols-3"

  defp filtered_projects(projects, ""), do: projects

  defp filtered_projects(projects, query) do
    q = String.downcase(query)
    Enum.filter(projects, fn p -> String.contains?(String.downcase(p.name), q) end)
  end

  defp session_title(session) do
    session[:title] || "terminal"
  end

  defp status_color(:running), do: "bg-[#5ea85e]"
  defp status_color(_), do: "bg-[#e05252]"

  @impl true
  def render(assigns) do
    ~H"""
    <div
      id="cortex-root"
      phx-hook="CommandPalette"
      class="h-screen bg-[#050505] flex flex-col select-none"
    >
      <%!-- Header --%>
      <header class="flex items-center justify-between px-4 py-2 border-b border-[#1a1a1a] shrink-0">
        <div class="flex items-center gap-3">
          <span class="text-[#ffd04a] font-bold text-sm tracking-wide">CORTEX</span>
          <span class="text-[#3a3a3a] text-xs font-mono">
            {length(@session_order)} sessions
          </span>
        </div>
        <div class="flex items-center gap-3">
          <button
            phx-click="new_session"
            class="text-xs text-[#5a5a5a] hover:text-[#e8dcc0] px-2.5 py-1 rounded-[7px] border border-[#1a1a1a] hover:border-[#2a2a2a] transition-colors cursor-pointer"
          >
            + New
          </button>
          <button
            phx-click="toggle_command_palette"
            class="text-xs text-[#5a5a5a] hover:text-[#e8dcc0] transition-colors cursor-pointer"
          >
            <kbd class="px-1.5 py-0.5 rounded-[6px] bg-[#0a0a0a] border border-[#1a1a1a] text-[10px] font-mono">
              Cmd+K
            </kbd>
          </button>
        </div>
      </header>

      <%!-- Terminal Grid --%>
      <div
        :if={@session_order != []}
        class={"flex-1 grid gap-1.5 p-1.5 min-h-0 auto-rows-fr #{grid_class(length(@session_order))}"}
      >
        <%= for {id, idx} <- Enum.with_index(@session_order) do %>
          <% session = @sessions[id] %>
          <div
            :if={@focused_id == nil || @focused_id == id}
            id={"terminal-container-#{id}"}
            class={[
              "relative rounded-[8px] border overflow-hidden flex flex-col min-h-0",
              "border-[#1a1a1a] transition-colors",
              @focused_id == nil && "hover:border-[#2a2a2a]",
              @focused_id == id && "col-span-full row-span-full"
            ]}
          >
            <%!-- Title bar --%>
            <div class="flex items-center justify-between px-3 py-1 bg-[#080808] border-b border-[#1a1a1a] shrink-0">
              <div class="flex items-center gap-2 min-w-0">
                <span class={"w-2 h-2 rounded-full shrink-0 #{status_color(session[:status])}"} />
                <span class="text-[11px] text-[#5a5a5a] truncate font-medium">
                  {session_title(session)}
                </span>
                <span class="text-[10px] text-[#2a2a2a] font-mono shrink-0">{idx + 1}</span>
              </div>
              <div class="flex items-center gap-0.5 shrink-0">
                <button
                  :if={@focused_id == id}
                  phx-click="unfocus"
                  class="text-[10px] text-[#3a3a3a] hover:text-[#e8dcc0] px-1.5 py-0.5 rounded-[5px] hover:bg-[#1a1a1a] transition-colors cursor-pointer"
                >
                  grid
                </button>
                <button
                  :if={@focused_id != id}
                  phx-click="focus"
                  phx-value-id={id}
                  class="text-[10px] text-[#3a3a3a] hover:text-[#e8dcc0] px-1.5 py-0.5 rounded-[5px] hover:bg-[#1a1a1a] transition-colors cursor-pointer"
                >
                  focus
                </button>
                <button
                  phx-click="kill_session"
                  phx-value-id={id}
                  class="text-[10px] text-[#3a3a3a] hover:text-[#e05252] px-1.5 py-0.5 rounded-[5px] hover:bg-[#1a1a1a] transition-colors cursor-pointer"
                >
                  x
                </button>
              </div>
            </div>
            <%!-- xterm.js mounts here --%>
            <div
              id={"terminal-#{id}"}
              phx-hook="Terminal"
              phx-update="ignore"
              data-session-id={id}
              class="flex-1 min-h-0 bg-[#050505]"
            />
          </div>
        <% end %>
      </div>

      <%!-- Empty state --%>
      <div :if={@session_order == []} class="flex-1 flex items-center justify-center">
        <div class="text-center space-y-4">
          <div class="text-[#ffd04a] text-2xl font-bold tracking-wide">CORTEX</div>
          <p class="text-[#3a3a3a] text-sm">Terminal mission control</p>
          <button
            phx-click="new_session"
            class="text-sm text-[#ffd04a] hover:text-[#ffe47a] px-5 py-2.5 rounded-[8px] border border-[#ffd04a]/20 hover:border-[#ffd04a]/40 transition-colors cursor-pointer"
          >
            Open Terminal
          </button>
          <p class="text-[#2a2a2a] text-xs">
            <kbd class="px-1 py-0.5 rounded-[5px] bg-[#0a0a0a] border border-[#1a1a1a] font-mono text-[10px]">
              Cmd+K
            </kbd>
            command palette
          </p>
        </div>
      </div>

      <%!-- Command Palette --%>
      <div
        :if={@command_palette_open}
        id="command-palette-backdrop"
        class="fixed inset-0 z-50 flex items-start justify-center pt-[18vh]"
        phx-click="close_command_palette"
      >
        <div class="absolute inset-0 bg-black/70" />
        <div
          class="relative w-full max-w-lg bg-[#0a0a0a] border border-[#1a1a1a] rounded-[8px] shadow-2xl overflow-hidden"
          phx-click-away="close_command_palette"
        >
          <div class="px-4 py-3 border-b border-[#1a1a1a]">
            <form phx-change="search_projects" class="flex items-center gap-2">
              <span class="text-[#3a3a3a] text-sm">></span>
              <input
                type="text"
                name="query"
                placeholder="Search projects or type a command..."
                value={@search_query}
                autofocus
                phx-debounce="100"
                class="flex-1 bg-transparent text-[#e8dcc0] text-sm placeholder-[#2a2a2a] outline-none font-mono"
              />
            </form>
          </div>
          <div class="max-h-72 overflow-y-auto py-1">
            <button
              phx-click="new_session"
              class="w-full px-4 py-2.5 text-left text-sm text-[#e8dcc0] hover:bg-[#141414] flex items-center gap-3 transition-colors cursor-pointer"
            >
              <span class="text-[#ffd04a] font-mono text-xs">+</span>
              <span>New blank terminal</span>
              <span class="ml-auto text-[10px] text-[#2a2a2a] font-mono">Cmd+T</span>
            </button>
            <div class="h-px bg-[#1a1a1a] mx-3 my-1" />
            <%= for project <- filtered_projects(@projects, @search_query) do %>
              <button
                phx-click="new_project_session"
                phx-value-name={project.name}
                class="w-full px-4 py-2 text-left text-sm text-[#e8dcc0] hover:bg-[#141414] flex items-center justify-between transition-colors cursor-pointer group"
              >
                <div class="flex items-center gap-3 min-w-0">
                  <span class={"w-1.5 h-1.5 rounded-full shrink-0 " <> project_status_color(project.status)} />
                  <span class="truncate">{project.name}</span>
                </div>
                <span class="text-[10px] text-[#2a2a2a] font-mono shrink-0 group-hover:text-[#3a3a3a]">
                  {project.status}
                </span>
              </button>
            <% end %>
          </div>
        </div>
      </div>
    </div>
    """
  end

  defp project_status_color("ACTIVE"), do: "bg-[#5ea85e]"
  defp project_status_color("BUILDING"), do: "bg-[#ffd04a]"
  defp project_status_color("MAINTENANCE"), do: "bg-[#3a3a3a]"
  defp project_status_color(_), do: "bg-[#2a2a2a]"
end
