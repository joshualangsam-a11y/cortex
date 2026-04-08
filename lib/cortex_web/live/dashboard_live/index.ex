defmodule CortexWeb.DashboardLive.Index do
  use CortexWeb, :live_view

  alias Cortex.Terminals
  alias Cortex.Projects
  alias Cortex.Workspaces
  alias Cortex.Intelligence

  alias Cortex.Intelligence.{
    DailyBrief,
    EnergyCycle,
    FlowCalibrator,
    FlowHistory,
    MomentumEngine,
    ResumePoint,
    SessionDNA,
    SmartResume,
    ThermalThrottle
  }

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket) do
      Phoenix.PubSub.subscribe(Cortex.PubSub, "terminal:sessions")
      Phoenix.PubSub.subscribe(Cortex.PubSub, Intelligence.Prioritizer.topic())
      Phoenix.PubSub.subscribe(Cortex.PubSub, "terminal:status")
      Phoenix.PubSub.subscribe(Cortex.PubSub, "terminal:notifications")
      Phoenix.PubSub.subscribe(Cortex.PubSub, MomentumEngine.topic())
      Phoenix.PubSub.subscribe(Cortex.PubSub, ThermalThrottle.topic())
    end

    sessions = Terminals.list_sessions()
    session_map = Map.new(sessions, fn s -> {s.id, s} end)
    session_order = Enum.map(sessions, & &1.id)

    if connected?(socket) do
      Enum.each(session_order, fn id ->
        Phoenix.PubSub.subscribe(Cortex.PubSub, "terminal:#{id}:output")
      end)
    end

    priorities = Intelligence.top_actions(5)
    all_priorities = Intelligence.ranked()
    priority_map = Map.new(all_priorities, fn r -> {r.project_name, r} end)

    projects = Projects.list_projects()

    git_statuses =
      projects
      |> Enum.map(fn p -> {p.name, Cortex.Projects.GitStatus.check(p.path)} end)
      |> Map.new()

    if connected?(socket) do
      Process.send_after(self(), :refresh_deploys, 60_000)
      Process.send_after(self(), :refresh_energy, 60_000)
    end

    socket =
      socket
      |> assign(:sessions, session_map)
      |> assign(:session_order, session_order)
      |> assign(:focused_id, nil)
      |> assign(:command_palette_open, false)
      |> assign(:projects, projects)
      |> assign(:search_query, "")
      |> assign(:page_title, "Cortex")
      |> assign(:priorities, priorities)
      |> assign(:priority_map, priority_map)
      |> assign(:show_priorities, false)
      |> assign(:brief, generate_brief())
      |> assign(:show_brief, true)
      |> assign(:completed, load_completed())
      |> assign(:workspaces, Workspaces.list_workspaces())
      |> assign(:session_statuses, %{})
      |> assign(:toasts, [])
      |> assign(:deploy_statuses, scan_deploys())
      |> assign(:git_statuses, git_statuses)
      |> assign(:started_at, DateTime.utc_now())
      |> assign(:flow_state, :idle)
      |> assign(:velocity, 0)
      |> assign(:resume_points, load_resume_points())
      |> assign(:smart_resume, load_smart_resume())
      |> assign(:energy, EnergyCycle.state())
      |> assign(:flow_stats, load_flow_stats())
      |> assign(:thermal_state, :normal)
      |> assign(:thermal_suggestion, nil)
      |> assign(:show_stats, false)

    {:ok, socket}
  end

  defp generate_brief do
    Task.async(fn -> DailyBrief.generate() end) |> Task.await(10_000)
  rescue
    _ -> nil
  end

  defp load_completed do
    DailyBrief.completed_today()
  rescue
    _ -> MapSet.new()
  end

  defp load_resume_points do
    ResumePoint.pending()
  rescue
    _ -> []
  end

  defp load_smart_resume do
    SmartResume.suggestions()
  rescue
    _ -> []
  end

  defp load_flow_stats do
    FlowHistory.today_stats()
  rescue
    _ -> %{sessions: 0, total_minutes: 0, longest_minutes: 0, peak_velocity: 0}
  end

  defp is_done?(completed, action) do
    MapSet.member?(completed, DailyBrief.action_hash(action))
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
    # Track context switches for thermal throttle detection
    if socket.assigns.focused_id && socket.assigns.focused_id != id do
      ThermalThrottle.record_context_switch()
    end

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

  def handle_event("focus_prev", _params, socket) do
    order = socket.assigns.session_order

    case socket.assigns.focused_id do
      nil ->
        case List.last(order) do
          nil -> {:noreply, socket}
          id -> {:noreply, assign(socket, :focused_id, id)}
        end

      current_id ->
        idx = Enum.find_index(order, &(&1 == current_id)) || 0
        prev_idx = rem(idx - 1 + length(order), length(order))

        case Enum.at(order, prev_idx) do
          nil -> {:noreply, socket}
          id -> {:noreply, assign(socket, :focused_id, id)}
        end
    end
  end

  def handle_event("focus_next", _params, socket) do
    order = socket.assigns.session_order

    case socket.assigns.focused_id do
      nil ->
        case List.first(order) do
          nil -> {:noreply, socket}
          id -> {:noreply, assign(socket, :focused_id, id)}
        end

      current_id ->
        idx = Enum.find_index(order, &(&1 == current_id)) || 0
        next_idx = rem(idx + 1, length(order))

        case Enum.at(order, next_idx) do
          nil -> {:noreply, socket}
          id -> {:noreply, assign(socket, :focused_id, id)}
        end
    end
  end

  def handle_event("reorder_sessions", %{"order" => new_order}, socket) do
    valid_ids = MapSet.new(Map.keys(socket.assigns.sessions))
    filtered_order = Enum.filter(new_order, &MapSet.member?(valid_ids, &1))

    if length(filtered_order) == length(socket.assigns.session_order) do
      Terminals.save_layout(filtered_order)
      {:noreply, assign(socket, :session_order, filtered_order)}
    else
      {:noreply, socket}
    end
  end

  def handle_event("toggle_priorities", _params, socket) do
    {:noreply, assign(socket, :show_priorities, !socket.assigns.show_priorities)}
  end

  def handle_event("refresh_priorities", _params, socket) do
    Intelligence.refresh()
    {:noreply, socket}
  end

  def handle_event("kill_all_sessions", _params, socket) do
    Enum.each(socket.assigns.session_order, fn id ->
      Terminals.kill_session(id)
    end)

    {:noreply, assign(socket, command_palette_open: false, search_query: "")}
  end

  def handle_event("launch_task", %{"project" => name, "task" => task}, socket) do
    project = Projects.get_project(name)

    if project do
      prompt = task |> String.replace("\"", "\\\"")
      cmd = "claude \"#{prompt}\""

      Terminals.create_session(%{
        project: project,
        title: "#{project.name}",
        auto_command: cmd
      })

      DailyBrief.mark_completed(task, "build")
    end

    completed = load_completed()

    {:noreply,
     assign(socket, show_brief: false, command_palette_open: false, completed: completed)}
  end

  def handle_event("launch_money", %{"action" => action}, socket) do
    cmd = "claude \"#{String.replace(action, "\"", "\\\"")}\""

    Terminals.create_session(%{
      cwd: Path.join(System.user_home!(), "roan-pi-platform"),
      title: "money",
      auto_command: cmd
    })

    DailyBrief.mark_completed(action, "money")
    completed = load_completed()
    {:noreply, assign(socket, show_brief: false, completed: completed)}
  end

  def handle_event("launch_pipeline", %{"action" => action}, socket) do
    cmd = "claude \"#{String.replace(action, "\"", "\\\"")}\""

    Terminals.create_session(%{
      cwd: Path.join(System.user_home!(), "roan-pi-platform"),
      title: "pipeline",
      auto_command: cmd
    })

    DailyBrief.mark_completed(action, "pipeline")
    completed = load_completed()
    {:noreply, assign(socket, show_brief: false, completed: completed)}
  end

  def handle_event("launch_quick_win", %{"task" => task}, socket) do
    cmd = "claude \"#{String.replace(task, "\"", "\\\"")}\""

    Terminals.create_session(%{
      cwd: System.user_home!(),
      title: "quick-win",
      auto_command: cmd
    })

    DailyBrief.mark_completed(task, "quick_win")
    completed = load_completed()
    {:noreply, assign(socket, show_brief: false, completed: completed)}
  end

  def handle_event("toggle_brief", _params, socket) do
    {:noreply, assign(socket, :show_brief, !socket.assigns.show_brief)}
  end

  def handle_event("dismiss_brief", _params, socket) do
    {:noreply, assign(socket, :show_brief, false)}
  end

  def handle_event("resume_point", %{"id" => id, "project" => name}, socket) do
    ResumePoint.mark_resumed(id)
    project = Projects.get_project(name)

    if project do
      Terminals.create_session(%{project: project, title: project.name})
    end

    {:noreply, assign(socket, resume_points: load_resume_points())}
  end

  def handle_event("dismiss_resume", %{"id" => id}, socket) do
    ResumePoint.mark_dismissed(id)
    {:noreply, assign(socket, resume_points: load_resume_points())}
  end

  def handle_event("burst_mode", %{"name" => name}, socket) do
    Cortex.Terminals.BurstMode.launch(name)
    {:noreply, assign(socket, command_palette_open: false, search_query: "")}
  end

  def handle_event(
        "smart_resume",
        %{"type" => "resume_point", "id" => id, "project" => name},
        socket
      ) do
    ResumePoint.mark_resumed(id)
    project = Projects.get_project(name)

    if project do
      Terminals.create_session(%{project: project, title: project.name})
    end

    {:noreply,
     assign(socket, resume_points: load_resume_points(), smart_resume: load_smart_resume())}
  end

  def handle_event("smart_resume", %{"type" => "workspace", "project" => name}, socket) do
    Workspaces.launch_workspace(name)
    {:noreply, assign(socket, smart_resume: load_smart_resume())}
  end

  def handle_event("dismiss_thermal", _params, socket) do
    {:noreply, assign(socket, thermal_state: :normal, thermal_suggestion: nil)}
  end

  def handle_event("toggle_stats", _params, socket) do
    {:noreply, assign(socket, :show_stats, !socket.assigns[:show_stats])}
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

  def handle_event("dismiss_toast_manual", %{"id" => id}, socket) do
    {int_id, _} = Integer.parse(id)
    toasts = Enum.reject(socket.assigns.toasts, &(&1.id == int_id))
    {:noreply, assign(socket, :toasts, toasts)}
  end

  def handle_event("launch_workspace", %{"name" => name}, socket) do
    Workspaces.launch_workspace(name)

    {:noreply,
     assign(socket,
       command_palette_open: false,
       search_query: ""
     )}
  end

  def handle_event("save_workspace", %{"name" => name}, socket) do
    Workspaces.save_current(name)

    {:noreply,
     assign(socket,
       workspaces: Workspaces.list_workspaces(),
       command_palette_open: false,
       search_query: ""
     )}
  end

  def handle_event("terminal_input", %{"session_id" => id, "data" => data}, socket) do
    decoded = Base.decode64!(data)
    Terminals.write(id, decoded)
    # Feed momentum engine — tracks keystroke velocity for flow detection
    MomentumEngine.record_input(id)
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

    # Persist layout for crash recovery
    Terminals.save_layout(order)

    {:noreply, assign(socket, sessions: sessions, session_order: order)}
  end

  def handle_info({:session_exited, id, exit_code}, socket) do
    sessions =
      Map.update(socket.assigns.sessions, id, %{}, fn s ->
        Map.merge(s, %{status: :exited, exit_code: exit_code})
      end)

    # Zeigarnik: generate resume point from last output buffer
    spawn(fn ->
      with data when is_binary(data) and byte_size(data) > 0 <- Terminals.get_scrollback(id),
           session when not is_nil(session) <- Map.get(socket.assigns.sessions, id) do
        project_name = session[:title] || session[:project_name]
        ResumePoint.from_output(id, project_name, data)
      end
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

  def handle_info({:priorities_updated, results}, socket) do
    priorities = results |> Enum.filter(& &1.top_action) |> Enum.take(5)
    priority_map = Map.new(results, fn r -> {r.project_name, r} end)

    {:noreply, assign(socket, priorities: priorities, priority_map: priority_map)}
  end

  def handle_info({:session_status_changed, id, status}, socket) do
    statuses = Map.put(socket.assigns.session_statuses, id, status)
    {:noreply, assign(socket, :session_statuses, statuses)}
  end

  def handle_info({:terminal_notification, _id, notification}, socket) do
    # Flow-aware toast suppression: during flow state, only show errors
    # Non-critical notifications (info, success) are suppressed to protect momentum
    if socket.assigns.flow_state == :flowing and notification.severity in [:info, :success] do
      {:noreply, socket}
    else
      toast = %{
        id: System.unique_integer([:positive]),
        severity: notification.severity,
        message: notification.message,
        action_hint: notification.action_hint,
        session_id: notification.session_id,
        timestamp: DateTime.utc_now()
      }

      Process.send_after(self(), {:dismiss_toast, toast.id}, 5000)
      toasts = [toast | socket.assigns.toasts] |> Enum.take(5)
      {:noreply, assign(socket, :toasts, toasts)}
    end
  end

  def handle_info({:momentum_changed, flow_state, velocity}, socket) do
    socket =
      socket
      |> assign(flow_state: flow_state, velocity: velocity)
      |> assign(:flow_stats, load_flow_stats())

    {:noreply, socket}
  end

  def handle_info({:thermal_throttle, thermal_state, suggestion}, socket) do
    {:noreply, assign(socket, thermal_state: thermal_state, thermal_suggestion: suggestion)}
  end

  def handle_info({:dismiss_toast, toast_id}, socket) do
    toasts = Enum.reject(socket.assigns.toasts, &(&1.id == toast_id))
    {:noreply, assign(socket, :toasts, toasts)}
  end

  def handle_info(:refresh_deploys, socket) do
    Process.send_after(self(), :refresh_deploys, 60_000)
    {:noreply, assign(socket, :deploy_statuses, scan_deploys())}
  end

  def handle_info(:refresh_energy, socket) do
    Process.send_after(self(), :refresh_energy, 60_000)

    {:noreply,
     socket
     |> assign(:energy, EnergyCycle.state())
     |> assign(:flow_stats, load_flow_stats())}
  end

  # Helpers

  defp remove_session(socket, id) do
    sessions = Map.delete(socket.assigns.sessions, id)
    order = List.delete(socket.assigns.session_order, id)

    # Persist layout for crash recovery
    Terminals.save_layout(order)

    focused =
      if socket.assigns.focused_id == id, do: nil, else: socket.assigns.focused_id

    {:noreply, assign(socket, sessions: sessions, session_order: order, focused_id: focused)}
  end

  defp scan_deploys do
    Cortex.Projects.list_projects()
    |> Enum.filter(fn p -> p.port && p.port > 0 end)
    |> Enum.map(fn p ->
      alive = port_alive?(p.port)
      %{name: p.name, port: p.port, alive: alive}
    end)
  end

  defp port_alive?(port) do
    case :gen_tcp.connect(~c"127.0.0.1", port, [], 200) do
      {:ok, socket} ->
        :gen_tcp.close(socket)
        true

      _ ->
        false
    end
  end

  defp format_uptime(started_at) do
    diff = DateTime.diff(DateTime.utc_now(), started_at, :second)

    cond do
      diff < 60 -> "#{diff}s"
      diff < 3600 -> "#{div(diff, 60)}m"
      true -> "#{div(diff, 3600)}h#{div(rem(diff, 3600), 60)}m"
    end
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

  defp stats_panel(assigns) do
    week = safe_week_stats()
    calibration = safe_calibration_status()
    dna = safe_dna_summary()
    thermal = safe_thermal_state()
    insights = safe_insights()

    assigns =
      assigns
      |> assign(:week, week)
      |> assign(:calibration, calibration)
      |> assign(:insights, insights)
      |> assign(:dna, dna)
      |> assign(:thermal, thermal)

    ~H"""
    <div class="border-b border-[#1a1a1a] bg-[#080808] px-4 py-3 shrink-0 animate-slide-in">
      <div class="flex items-center justify-between mb-3">
        <span class="text-[10px] text-[#ffd04a] uppercase tracking-wider font-medium">Evidence</span>
        <span class="text-[10px] text-[#2a2a2a] font-mono">Cmd+Shift+I</span>
      </div>

      <div class="grid grid-cols-4 gap-4">
        <%!-- Today --%>
        <div class="space-y-1">
          <span class="text-[9px] text-[#3a3a3a] uppercase tracking-wider">Today</span>
          <div class="text-sm text-[#e8dcc0] font-mono">
            {if @flow_stats.total_minutes > 0,
              do: format_flow_time(@flow_stats.total_minutes),
              else: "0m"} flow
          </div>
          <div class="text-[10px] text-[#5a5a5a] font-mono">{@flow_stats.sessions} flow sessions</div>
          <div :if={@flow_stats.longest_minutes > 0} class="text-[10px] text-[#5a5a5a] font-mono">
            longest: {format_flow_time(@flow_stats.longest_minutes)}
          </div>
        </div>

        <%!-- This Week --%>
        <div class="space-y-1">
          <span class="text-[9px] text-[#3a3a3a] uppercase tracking-wider">This Week</span>
          <div class="text-sm text-[#e8dcc0] font-mono">{@week.total_hours}h flow</div>
          <div class="text-[10px] text-[#5a5a5a] font-mono">{@week.sessions} sessions</div>
          <div :if={@week.streak > 0} class="text-[10px] text-[#ffd04a] font-mono">
            {@week.streak}d streak
          </div>
        </div>

        <%!-- Current State --%>
        <div class="space-y-1">
          <span class="text-[9px] text-[#3a3a3a] uppercase tracking-wider">State</span>
          <div class="flex items-center gap-1.5">
            <span class={"w-2 h-2 rounded-full " <> energy_dot_class(@energy.phase)} />
            <span class={"text-sm font-mono " <> energy_text_class(@energy.phase)}>
              {energy_label(@energy.phase)}
            </span>
            <span class="text-[10px] text-[#2a2a2a] font-mono">{@energy.level}/10</span>
          </div>
          <div class="text-[10px] text-[#5a5a5a] font-mono">
            {if @flow_state == :flowing, do: "IN FLOW", else: "#{@velocity}/s velocity"}
          </div>
          <div class={"text-[10px] font-mono " <> thermal_color(@thermal.thermal_state)}>
            {thermal_label(@thermal.thermal_state)}
          </div>
        </div>

        <%!-- Calibration --%>
        <div class="space-y-1">
          <span class="text-[9px] text-[#3a3a3a] uppercase tracking-wider">Brain Calibration</span>
          <div class="text-sm text-[#e8dcc0] font-mono">{@calibration.progress}%</div>
          <div class="text-[10px] text-[#5a5a5a] font-mono">
            {@calibration.sessions_recorded}/{@calibration.sessions_needed} flow sessions
          </div>
          <div class="w-full bg-[#1a1a1a] rounded-full h-1 mt-1">
            <div class="bg-[#ffd04a] h-1 rounded-full" style={"width: #{@calibration.progress}%"} />
          </div>
          <div :if={@calibration.ready} class="text-[10px] text-[#5ea85e] font-mono">
            auto-calibrating
          </div>
        </div>
      </div>

      <%!-- Activity DNA --%>
      <div :if={map_size(@dna.activity_breakdown) > 0} class="mt-3 pt-3 border-t border-[#1a1a1a]">
        <span class="text-[9px] text-[#3a3a3a] uppercase tracking-wider">Session DNA</span>
        <div class="flex items-center gap-3 mt-1">
          <%= for {activity, count} <- Enum.sort_by(@dna.activity_breakdown, fn {_k, v} -> -v end) do %>
            <span class={"text-[10px] font-mono " <> activity_color(activity)}>
              {activity_label(activity)} {count}
            </span>
          <% end %>
        </div>
      </div>

      <%!-- Work Pattern Insights --%>
      <div :if={@insights != []} class="mt-3 pt-3 border-t border-[#1a1a1a] space-y-2">
        <span class="text-[9px] text-[#ffd04a] uppercase tracking-wider">Insights</span>
        <%= for insight <- Enum.take(@insights, 3) do %>
          <div class="flex items-start gap-2">
            <span class="text-[10px] text-[#ffd04a] shrink-0 mt-0.5">*</span>
            <div>
              <span class="text-[11px] text-[#e8dcc0]">{insight.insight}</span>
              <span class="text-[9px] text-[#3a3a3a] ml-2">{insight.evidence}</span>
              <div :if={insight.suggestion} class="text-[10px] text-[#5a5a5a] mt-0.5">
                {insight.suggestion}
              </div>
            </div>
          </div>
        <% end %>
      </div>
    </div>
    """
  end

  defp safe_week_stats do
    FlowHistory.week_stats()
  rescue
    _ -> %{sessions: 0, total_hours: 0.0, avg_session_minutes: 0, peak_velocity: 0, streak: 0}
  end

  defp safe_calibration_status do
    FlowCalibrator.status()
  rescue
    _ -> %{sessions_recorded: 0, sessions_needed: 10, ready: false, progress: 0}
  end

  defp safe_dna_summary do
    SessionDNA.today_summary()
  rescue
    _ -> %{total_sessions: 0, activity_breakdown: %{}, primary_activity: :idle, total_events: 0}
  end

  defp safe_thermal_state do
    ThermalThrottle.state()
  rescue
    _ ->
      %{
        thermal_state: :normal,
        recent_errors: 0,
        recent_switches: 0,
        session_hours: 0,
        velocity: 0
      }
  end

  defp safe_insights do
    Cortex.Intelligence.WorkPatterns.generate()
  rescue
    _ -> []
  end

  defp thermal_color(:normal), do: "text-[#3a3a3a]"
  defp thermal_color(:elevated), do: "text-[#5a5a5a]"
  defp thermal_color(:warming), do: "text-[#e8b839]"
  defp thermal_color(:overheating), do: "text-[#e05252]"

  defp thermal_label(:normal), do: "thermal: normal"
  defp thermal_label(:elevated), do: "thermal: elevated"
  defp thermal_label(:warming), do: "thermal: warming"
  defp thermal_label(:overheating), do: "thermal: OVERHEATING"

  @impl true
  def render(assigns) do
    ~H"""
    <div
      id="cortex-root"
      phx-hook="CommandPalette"
      data-flow-state={@flow_state}
      class="h-screen bg-[#050505] flex flex-col select-none"
    >
      <%!-- Header --%>
      <header class="flex items-center justify-between px-4 py-2 border-b border-[#1a1a1a] shrink-0">
        <div class="flex items-center gap-3">
          <span class="text-[#ffd04a] font-bold text-sm tracking-wide">CORTEX</span>
          <span class="text-[#3a3a3a] text-xs font-mono">
            {length(@session_order)} sessions
          </span>
          <%!-- Energy phase indicator --%>
          <div class="flex items-center gap-1.5 ml-2 pl-3 border-l border-[#1a1a1a]">
            <div class={"w-1.5 h-1.5 rounded-full " <> energy_dot_class(@energy.phase)} />
            <span class={"text-[10px] font-mono " <> energy_text_class(@energy.phase)}>
              {energy_label(@energy.phase)}
            </span>
            <span class="text-[10px] text-[#2a2a2a] font-mono">{@energy.level}/10</span>
          </div>
          <%!-- Deploy status indicator --%>
          <div class="flex items-center gap-1.5 ml-2 pl-3 border-l border-[#1a1a1a]">
            <span class="text-[10px] text-[#3a3a3a] uppercase tracking-wider">Live</span>
            <%= for deploy <- @deploy_statuses do %>
              <span
                :if={deploy.alive}
                title={"#{deploy.name} :#{deploy.port}"}
                class="w-1.5 h-1.5 rounded-full bg-[#5ea85e]"
              />
            <% end %>
            <span class="text-[10px] text-[#3a3a3a] font-mono">
              {Enum.count(@deploy_statuses, & &1.alive)}/{length(@deploy_statuses)}
            </span>
          </div>
          <%!-- Momentum indicator --%>
          <div
            :if={@flow_state == :flowing || @velocity > 0}
            class="flex items-center gap-1.5 ml-2 pl-3 border-l border-[#1a1a1a]"
          >
            <span class={[
              "w-2 h-2 rounded-full shrink-0",
              @flow_state == :flowing && "bg-[#ffd04a] animate-pulse",
              @flow_state == :idle && @velocity > 0 && "bg-[#5a5a5a]"
            ]} />
            <span class={"text-[10px] font-mono " <> if(@flow_state == :flowing, do: "text-[#ffd04a]", else: "text-[#3a3a3a]")}>
              {if @flow_state == :flowing, do: "FLOW", else: "#{@velocity}/s"}
            </span>
            <span :if={@flow_stats.total_minutes > 0} class="text-[10px] text-[#2a2a2a] font-mono">
              {format_flow_time(@flow_stats.total_minutes)} today
            </span>
          </div>
          <%!-- Priority indicator --%>
          <div
            :if={@priorities != []}
            class="flex items-center gap-2 ml-2 pl-3 border-l border-[#1a1a1a]"
          >
            <span class="text-[10px] text-[#3a3a3a] uppercase tracking-wider">Next</span>
            <span class="text-xs text-[#e8dcc0] font-medium truncate max-w-xs">
              {hd(@priorities).project_name}
            </span>
            <span class="text-[10px] text-[#5a5a5a] truncate max-w-sm hidden lg:inline">
              {hd(@priorities).top_action}
            </span>
          </div>
        </div>
        <div class="flex items-center gap-3">
          <span :if={@current_user} class="text-[10px] text-[#3a3a3a] font-mono">
            {@current_user.email}
          </span>
          <a
            :if={@current_user}
            href="/auth/logout"
            method="delete"
            class="text-[10px] text-[#3a3a3a] hover:text-[#e05252] cursor-pointer"
          >
            logout
          </a>
          <span class="text-[10px] text-[#2a2a2a] font-mono">
            up {format_uptime(@started_at)}
          </span>
          <button
            :if={@priorities != []}
            phx-click="toggle_priorities"
            class="text-[10px] text-[#5a5a5a] hover:text-[#ffd04a] transition-colors cursor-pointer"
          >
            {length(@priorities)} actions
          </button>
          <button
            :if={@brief}
            phx-click="toggle_brief"
            class="text-[10px] text-[#5a5a5a] hover:text-[#ffd04a] transition-colors cursor-pointer"
          >
            brief
          </button>
          <button
            phx-click="toggle_stats"
            class={"text-[10px] transition-colors cursor-pointer " <> if(@show_stats, do: "text-[#ffd04a]", else: "text-[#5a5a5a] hover:text-[#ffd04a]")}
          >
            stats
          </button>
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

      <%!-- Priority Panel (slide-down) --%>
      <div
        :if={@show_priorities}
        class="border-b border-[#1a1a1a] bg-[#080808] px-4 py-3 space-y-1.5 shrink-0"
      >
        <div class="flex items-center justify-between mb-2">
          <span class="text-[10px] text-[#3a3a3a] uppercase tracking-wider font-medium">
            Priority Queue
          </span>
          <button
            phx-click="refresh_priorities"
            class="text-[10px] text-[#3a3a3a] hover:text-[#ffd04a] transition-colors cursor-pointer"
          >
            refresh
          </button>
        </div>
        <%= for {item, idx} <- Enum.with_index(@priorities) do %>
          <button
            phx-click="new_project_session"
            phx-value-name={item.project_name}
            class="w-full flex items-center gap-3 px-3 py-2 rounded-[7px] hover:bg-[#0f0f0f] transition-colors cursor-pointer text-left group"
          >
            <span class={"w-5 h-5 rounded-[6px] flex items-center justify-center text-[10px] font-bold shrink-0 " <> priority_rank_class(idx)}>
              {idx + 1}
            </span>
            <div class="flex-1 min-w-0">
              <span class="text-sm text-[#e8dcc0] font-medium">{item.project_name}</span>
              <span class="text-[11px] text-[#3a3a3a] ml-2">{item.top_action}</span>
            </div>
            <span class="text-[10px] text-[#2a2a2a] font-mono shrink-0 group-hover:text-[#3a3a3a]">
              {item.score}
            </span>
          </button>
        <% end %>
      </div>

      <%!-- Stats Evidence Panel (Cmd+Shift+I) --%>
      <.stats_panel
        :if={@show_stats}
        energy={@energy}
        flow_state={@flow_state}
        velocity={@velocity}
        flow_stats={@flow_stats}
      />

      <%!-- Thermal Throttle Banner --%>
      <div
        :if={@thermal_state == :overheating && @thermal_suggestion}
        class="mx-1.5 mt-1.5 px-4 py-2.5 rounded-[7px] border border-[#e05252]/20 bg-[#0a0505] flex items-center gap-3 shrink-0 animate-slide-in"
      >
        <span class="w-2 h-2 rounded-full bg-[#e05252] animate-pulse shrink-0" />
        <span class="text-[11px] text-[#e05252] font-mono flex-1">{@thermal_suggestion}</span>
        <span class="text-[9px] text-[#3a3a3a] font-mono shrink-0">
          not quitting — thermal throttling
        </span>
        <button
          phx-click="dismiss_thermal"
          class="text-[10px] text-[#3a3a3a] hover:text-[#e05252] ml-2 shrink-0 cursor-pointer"
        >
          dismiss
        </button>
      </div>

      <%!-- Terminal Grid --%>
      <div
        :if={@session_order != []}
        id="terminal-grid"
        phx-hook="Drag"
        class={"flex-1 grid gap-1.5 p-1.5 min-h-0 auto-rows-fr #{grid_class(length(@session_order))}"}
      >
        <%= for {id, idx} <- Enum.with_index(@session_order) do %>
          <% session = @sessions[id] %>
          <div
            :if={@focused_id == nil || @focused_id == id}
            id={"terminal-container-#{id}"}
            data-drag-id={id}
            draggable={if @focused_id == nil, do: "true", else: "false"}
            class={[
              "relative rounded-[8px] border overflow-hidden flex flex-col min-h-0",
              "border-[#1a1a1a] transition-colors",
              @focused_id == nil && "hover:border-[#2a2a2a]",
              @focused_id == id && "col-span-full row-span-full"
            ]}
          >
            <%!-- Title bar (drag handle) --%>
            <div class="flex items-center justify-between px-3 py-1 bg-[#080808] border-b border-[#1a1a1a] shrink-0 cursor-grab active:cursor-grabbing">
              <div class="flex items-center gap-2 min-w-0">
                <span class={"w-2 h-2 rounded-full shrink-0 #{status_color(session[:status])}"} />
                <span class="text-[11px] text-[#5a5a5a] truncate font-medium">
                  {session_title(session)}
                </span>
                <span
                  :if={status = @session_statuses[id]}
                  class={"text-[9px] font-mono px-1.5 py-0.5 rounded-[4px] " <> session_status_class(status)}
                >
                  {status_label(status)}
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

      <%!-- Daily Brief: fullscreen when no sessions, overlay when sessions exist --%>
      <div
        :if={@session_order == []}
        class="flex-1 flex items-start justify-center overflow-y-auto py-8"
      >
        <div :if={@brief} class="w-full max-w-2xl px-6 space-y-5">
          <div class="text-center mb-6">
            <div class="text-[#ffd04a] text-xl font-bold tracking-wide">CORTEX</div>
            <p class="text-[#3a3a3a] text-sm mt-1">{@brief.greeting}</p>
            <p :if={@brief.energy_suggestion} class="text-[#2a2a2a] text-[10px] font-mono mt-1.5">
              {@brief.energy_suggestion}
            </p>
          </div>

          <%!-- Today Recap — evidence of what you've built --%>
          <div
            :if={@brief.today_recap && @brief.today_recap.total_sessions > 0}
            class="rounded-[8px] border border-[#1a1a1a]/50 bg-[#080808] px-4 py-3"
          >
            <div class="flex items-center justify-between">
              <span class="text-[10px] text-[#3a3a3a] uppercase tracking-wider font-medium">
                Today
              </span>
              <span
                :if={@brief.today_recap.flow_minutes > 0}
                class="text-[10px] text-[#ffd04a] font-mono"
              >
                {format_flow_time(@brief.today_recap.flow_minutes)} flow
              </span>
            </div>
            <div class="flex items-center gap-4 mt-1.5">
              <span class="text-[10px] text-[#5a5a5a] font-mono">
                {@brief.today_recap.total_sessions} sessions
              </span>
              <span
                :if={@brief.today_recap.flow_sessions > 0}
                class="text-[10px] text-[#5a5a5a] font-mono"
              >
                {@brief.today_recap.flow_sessions} flow states
              </span>
              <span
                :if={@brief.today_recap.longest_flow_minutes > 0}
                class="text-[10px] text-[#5a5a5a] font-mono"
              >
                longest: {format_flow_time(@brief.today_recap.longest_flow_minutes)}
              </span>
              <%= for {activity, count} <- @brief.today_recap.activity_breakdown do %>
                <span class={"text-[10px] font-mono " <> activity_color(activity)}>
                  {activity_label(activity)} {count}
                </span>
              <% end %>
            </div>
          </div>

          <%!-- Smart Resume (Zeigarnik) — ranked by urgency, recency, energy --%>
          <div
            :if={@smart_resume != []}
            class="rounded-[8px] border border-[#ffd04a]/20 bg-[#080808] overflow-hidden"
          >
            <div class="px-4 py-2.5 border-b border-[#ffd04a]/10 flex items-center gap-2">
              <span class="w-2 h-2 rounded-full bg-[#ffd04a] animate-pulse" />
              <span class="text-[11px] text-[#ffd04a] uppercase tracking-wider font-medium">
                Pick Up Where You Left Off
              </span>
            </div>
            <div class="divide-y divide-[#111]">
              <%= for {suggestion, idx} <- Enum.with_index(@smart_resume) do %>
                <button
                  phx-click="smart_resume"
                  phx-value-type={suggestion.type}
                  phx-value-id={suggestion[:id]}
                  phx-value-project={suggestion.project_name}
                  class="w-full px-4 py-3 flex items-center justify-between hover:bg-[#0f0f0f] transition-colors cursor-pointer text-left group"
                >
                  <div class="flex items-start gap-2 min-w-0">
                    <span class={"text-[10px] shrink-0 mt-0.5 font-mono " <> if(idx == 0, do: "text-[#ffd04a]", else: "text-[#2a2a2a] group-hover:text-[#ffd04a]")}>
                      {if idx == 0, do: ">>", else: ">"}
                    </span>
                    <div class="min-w-0">
                      <div class="flex items-center gap-2">
                        <span class={"text-sm font-medium " <> if(idx == 0, do: "text-[#ffd04a]", else: "text-[#e8dcc0]")}>
                          {suggestion.project_name}
                        </span>
                        <span class="text-[9px] text-[#3a3a3a] font-mono">{suggestion.source}</span>
                      </div>
                      <span class="text-[11px] text-[#5a5a5a]">{suggestion.context}</span>
                      <div class="text-[10px] text-[#3a3a3a] mt-0.5">{suggestion.next_action}</div>
                    </div>
                  </div>
                  <span class={"text-[10px] font-mono shrink-0 " <> resume_urgency_color(suggestion.urgency_score)}>
                    {suggestion.urgency_score}
                  </span>
                </button>
              <% end %>
            </div>
          </div>

          <%!-- Money Moves --%>
          <div
            :if={@brief.money_moves != []}
            class="rounded-[8px] border border-[#1a1a1a] bg-[#080808] overflow-hidden"
          >
            <div class="px-4 py-2.5 border-b border-[#1a1a1a] flex items-center gap-2">
              <span class="w-2 h-2 rounded-full bg-[#ffd04a]" />
              <span class="text-[11px] text-[#ffd04a] uppercase tracking-wider font-medium">
                Money Moves
              </span>
            </div>
            <div class="divide-y divide-[#111]">
              <%= for move <- @brief.money_moves do %>
                <% done = is_done?(@completed, move.action) %>
                <button
                  phx-click={if(!done, do: "launch_money")}
                  phx-value-action={move.action}
                  class={"w-full px-4 py-3 flex items-center justify-between transition-colors text-left group " <> if(done, do: "opacity-50", else: "hover:bg-[#0f0f0f] cursor-pointer")}
                >
                  <div class="flex items-center gap-2 min-w-0">
                    <span :if={done} class="text-[10px] text-[#5ea85e] shrink-0">done</span>
                    <span
                      :if={!done}
                      class="text-[10px] text-[#2a2a2a] group-hover:text-[#ffd04a] transition-colors shrink-0"
                    >
                      >
                    </span>
                    <span class={"text-sm " <> if(done, do: "text-[#3a3a3a] line-through", else: "text-[#e8dcc0]")}>
                      {move.action}
                    </span>
                  </div>
                  <span
                    :if={!done}
                    class={"text-[10px] font-mono px-2 py-0.5 rounded-[5px] " <> urgency_class(move.priority)}
                  >
                    {move.priority}
                  </span>
                </button>
              <% end %>
            </div>
          </div>

          <%!-- Pipeline Actions --%>
          <div
            :if={@brief.pipeline_actions != []}
            class="rounded-[8px] border border-[#1a1a1a] bg-[#080808] overflow-hidden"
          >
            <div class="px-4 py-2.5 border-b border-[#1a1a1a] flex items-center gap-2">
              <span class="w-2 h-2 rounded-full bg-[#e05252]" />
              <span class="text-[11px] text-[#e05252] uppercase tracking-wider font-medium">
                Pipeline
              </span>
            </div>
            <div class="divide-y divide-[#111]">
              <%= for action <- @brief.pipeline_actions do %>
                <% done = is_done?(@completed, action.action) %>
                <button
                  phx-click={if(!done, do: "launch_pipeline")}
                  phx-value-action={action.action}
                  class={"w-full px-4 py-3 flex items-center justify-between transition-colors text-left group " <> if(done, do: "opacity-50", else: "hover:bg-[#0f0f0f] cursor-pointer")}
                >
                  <div class="flex items-center gap-2 min-w-0">
                    <span :if={done} class="text-[10px] text-[#5ea85e] shrink-0">done</span>
                    <span
                      :if={!done}
                      class="text-[10px] text-[#2a2a2a] group-hover:text-[#e05252] transition-colors shrink-0"
                    >
                      >
                    </span>
                    <span class={"text-sm " <> if(done, do: "text-[#3a3a3a] line-through", else: "text-[#e8dcc0]")}>
                      {action.action}
                    </span>
                  </div>
                  <span
                    :if={!done}
                    class={"text-[10px] font-mono px-2 py-0.5 rounded-[5px] " <> urgency_class(action.urgency)}
                  >
                    {action.urgency}
                  </span>
                </button>
              <% end %>
            </div>
          </div>

          <%!-- Build Tasks --%>
          <div
            :if={@brief.build_tasks != []}
            class="rounded-[8px] border border-[#1a1a1a] bg-[#080808] overflow-hidden"
          >
            <div class="px-4 py-2.5 border-b border-[#1a1a1a] flex items-center gap-2">
              <span class="w-2 h-2 rounded-full bg-[#5ea85e]" />
              <span class="text-[11px] text-[#5ea85e] uppercase tracking-wider font-medium">
                Build
              </span>
            </div>
            <div class="divide-y divide-[#111]">
              <%= for task <- @brief.build_tasks do %>
                <% done = is_done?(@completed, task.action) %>
                <button
                  phx-click={if(!done, do: "launch_task")}
                  phx-value-project={task.project}
                  phx-value-task={task.action}
                  class={"w-full px-4 py-3 flex items-center justify-between transition-colors text-left group " <> if(done, do: "opacity-50", else: "hover:bg-[#0f0f0f] cursor-pointer")}
                >
                  <div class="flex items-center gap-3 min-w-0">
                    <span :if={done} class="text-[10px] text-[#5ea85e] shrink-0">done</span>
                    <span
                      :if={!done}
                      class="text-[10px] text-[#2a2a2a] group-hover:text-[#5ea85e] transition-colors shrink-0"
                    >
                      >
                    </span>
                    <span class={"text-sm font-medium shrink-0 " <> if(done, do: "text-[#3a3a3a] line-through", else: "text-[#e8dcc0]")}>
                      {task.project}
                    </span>
                    <span class={"text-[11px] truncate " <> if(done, do: "text-[#2a2a2a]", else: "text-[#3a3a3a]")}>
                      {task.action}
                    </span>
                  </div>
                  <span :if={!done} class={"text-[10px] font-mono " <> score_color(task.score)}>
                    {task.score}
                  </span>
                </button>
              <% end %>
            </div>
          </div>

          <%!-- Quick Wins --%>
          <div
            :if={@brief.quick_wins != []}
            class="rounded-[8px] border border-[#1a1a1a] bg-[#080808] overflow-hidden"
          >
            <div class="px-4 py-2.5 border-b border-[#1a1a1a] flex items-center gap-2">
              <span class="w-2 h-2 rounded-full bg-[#5a9bcf]" />
              <span class="text-[11px] text-[#5a9bcf] uppercase tracking-wider font-medium">
                Quick Wins
              </span>
              <span class="text-[10px] text-[#2a2a2a]">under 5 min</span>
            </div>
            <div class="divide-y divide-[#111]">
              <%= for win <- @brief.quick_wins do %>
                <% done = is_done?(@completed, win) %>
                <button
                  phx-click={if(!done, do: "launch_quick_win")}
                  phx-value-task={win}
                  class={"w-full px-4 py-2.5 transition-colors text-left group flex items-center gap-2 " <> if(done, do: "opacity-50", else: "hover:bg-[#0f0f0f] cursor-pointer")}
                >
                  <span :if={done} class="text-[10px] text-[#5ea85e] shrink-0">done</span>
                  <span
                    :if={!done}
                    class="text-[10px] text-[#2a2a2a] group-hover:text-[#5a9bcf] transition-colors shrink-0"
                  >
                    >
                  </span>
                  <span class={"text-sm " <> if(done, do: "text-[#3a3a3a] line-through", else: "text-[#e8dcc0]")}>
                    {win}
                  </span>
                </button>
              <% end %>
            </div>
          </div>

          <%!-- Warnings --%>
          <div
            :if={@brief.warnings != []}
            class="rounded-[8px] border border-[#1a1a1a]/50 bg-[#080808] overflow-hidden"
          >
            <div class="px-4 py-2.5 border-b border-[#1a1a1a] flex items-center gap-2">
              <span class="text-[11px] text-[#3a3a3a] uppercase tracking-wider font-medium">
                Warnings
              </span>
            </div>
            <div class="divide-y divide-[#111]">
              <%= for warning <- @brief.warnings do %>
                <div class="px-4 py-2 text-[11px] text-[#5a5a5a] font-mono">{warning}</div>
              <% end %>
            </div>
          </div>

          <%!-- Open Terminal + Cmd+K --%>
          <div class="flex items-center justify-center gap-4 pt-2 pb-4">
            <button
              phx-click="toggle_command_palette"
              class="text-sm text-[#ffd04a] hover:text-[#ffe47a] px-5 py-2.5 rounded-[8px] border border-[#ffd04a]/20 hover:border-[#ffd04a]/40 transition-colors cursor-pointer"
            >
              Open Terminal
            </button>
            <span class="text-[#2a2a2a] text-xs">
              <kbd class="px-1 py-0.5 rounded-[5px] bg-[#0a0a0a] border border-[#1a1a1a] font-mono text-[10px]">
                Cmd+K
              </kbd>
            </span>
          </div>
        </div>

        <%!-- Fallback if brief failed --%>
        <div :if={!@brief} class="text-center space-y-4">
          <div class="text-[#ffd04a] text-2xl font-bold tracking-wide">CORTEX</div>
          <p class="text-[#3a3a3a] text-sm">Terminal mission control</p>
          <button
            phx-click="new_session"
            class="text-sm text-[#ffd04a] hover:text-[#ffe47a] px-5 py-2.5 rounded-[8px] border border-[#ffd04a]/20 hover:border-[#ffd04a]/40 transition-colors cursor-pointer"
          >
            Open Terminal
          </button>
        </div>
      </div>

      <%!-- Brief overlay when sessions are open --%>
      <div
        :if={@session_order != [] && @show_brief && @brief}
        class="fixed inset-0 z-40 flex items-start justify-center pt-[8vh] overflow-y-auto"
        phx-click="dismiss_brief"
      >
        <div class="absolute inset-0 bg-black/80" />
        <div
          class="relative w-full max-w-2xl px-6 py-6 space-y-5 mb-8"
          phx-click-away="dismiss_brief"
        >
          <div class="flex items-center justify-between">
            <div>
              <div class="text-[#ffd04a] text-xl font-bold tracking-wide">DAILY BRIEF</div>
              <p class="text-[#3a3a3a] text-sm mt-1">{@brief.greeting}</p>
              <p :if={@brief.energy_suggestion} class="text-[#2a2a2a] text-[10px] font-mono mt-1">
                {@brief.energy_suggestion}
              </p>
            </div>
            <button
              phx-click="dismiss_brief"
              class="text-[10px] text-[#3a3a3a] hover:text-[#e8dcc0] px-3 py-1.5 rounded-[6px] border border-[#1a1a1a] hover:border-[#2a2a2a] transition-colors cursor-pointer"
            >
              close
            </button>
          </div>

          <%!-- Reuse same cards — money, pipeline, build, quick wins, warnings --%>
          <div
            :if={@brief.money_moves != []}
            class="rounded-[8px] border border-[#1a1a1a] bg-[#080808] overflow-hidden"
          >
            <div class="px-4 py-2.5 border-b border-[#1a1a1a] flex items-center gap-2">
              <span class="w-2 h-2 rounded-full bg-[#ffd04a]" />
              <span class="text-[11px] text-[#ffd04a] uppercase tracking-wider font-medium">
                Money Moves
              </span>
            </div>
            <div class="divide-y divide-[#111]">
              <%= for move <- @brief.money_moves do %>
                <button
                  phx-click="launch_money"
                  phx-value-action={move.action}
                  class="w-full px-4 py-3 flex items-center justify-between hover:bg-[#0f0f0f] transition-colors cursor-pointer text-left group"
                >
                  <div class="flex items-center gap-2 min-w-0">
                    <span class="text-[10px] text-[#2a2a2a] group-hover:text-[#ffd04a] transition-colors shrink-0">
                      >
                    </span>
                    <span class="text-sm text-[#e8dcc0]">{move.action}</span>
                  </div>
                  <span class={"text-[10px] font-mono px-2 py-0.5 rounded-[5px] " <> urgency_class(move.priority)}>
                    {move.priority}
                  </span>
                </button>
              <% end %>
            </div>
          </div>

          <div
            :if={@brief.build_tasks != []}
            class="rounded-[8px] border border-[#1a1a1a] bg-[#080808] overflow-hidden"
          >
            <div class="px-4 py-2.5 border-b border-[#1a1a1a] flex items-center gap-2">
              <span class="w-2 h-2 rounded-full bg-[#5ea85e]" />
              <span class="text-[11px] text-[#5ea85e] uppercase tracking-wider font-medium">
                Build
              </span>
            </div>
            <div class="divide-y divide-[#111]">
              <%= for task <- @brief.build_tasks do %>
                <button
                  phx-click="launch_task"
                  phx-value-project={task.project}
                  phx-value-task={task.action}
                  class="w-full px-4 py-3 flex items-center justify-between hover:bg-[#0f0f0f] transition-colors cursor-pointer text-left group"
                >
                  <div class="flex items-center gap-3 min-w-0">
                    <span class="text-[10px] text-[#2a2a2a] group-hover:text-[#5ea85e] transition-colors shrink-0">
                      >
                    </span>
                    <span class="text-sm text-[#e8dcc0] font-medium shrink-0">{task.project}</span>
                    <span class="text-[11px] text-[#3a3a3a] truncate">{task.action}</span>
                  </div>
                  <span class={"text-[10px] font-mono " <> score_color(task.score)}>
                    {task.score}
                  </span>
                </button>
              <% end %>
            </div>
          </div>

          <div
            :if={@brief.quick_wins != []}
            class="rounded-[8px] border border-[#1a1a1a] bg-[#080808] overflow-hidden"
          >
            <div class="px-4 py-2.5 border-b border-[#1a1a1a] flex items-center gap-2">
              <span class="w-2 h-2 rounded-full bg-[#5a9bcf]" />
              <span class="text-[11px] text-[#5a9bcf] uppercase tracking-wider font-medium">
                Quick Wins
              </span>
            </div>
            <div class="divide-y divide-[#111]">
              <%= for win <- @brief.quick_wins do %>
                <button
                  phx-click="launch_quick_win"
                  phx-value-task={win}
                  class="w-full px-4 py-2.5 hover:bg-[#0f0f0f] transition-colors cursor-pointer text-left group flex items-center gap-2"
                >
                  <span class="text-[10px] text-[#2a2a2a] group-hover:text-[#5a9bcf] transition-colors shrink-0">
                    >
                  </span>
                  <span class="text-sm text-[#e8dcc0]">{win}</span>
                </button>
              <% end %>
            </div>
          </div>
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

            <%!-- Quick Actions --%>
            <div class="py-1">
              <button
                phx-click="refresh_priorities"
                class="w-full px-4 py-2 text-left text-sm text-[#e8dcc0] hover:bg-[#141414] flex items-center gap-3 transition-colors cursor-pointer"
              >
                <span class="text-[#5a9bcf] font-mono text-xs">~</span>
                <span>Refresh priorities</span>
              </button>
              <button
                phx-click="kill_all_sessions"
                class="w-full px-4 py-2 text-left text-sm text-[#e8dcc0] hover:bg-[#141414] flex items-center gap-3 transition-colors cursor-pointer"
              >
                <span class="text-[#e05252] font-mono text-xs">!</span>
                <span>Kill all sessions</span>
              </button>
            </div>
            <div class="h-px bg-[#1a1a1a] mx-3 my-1" />

            <%!-- Workspaces section --%>
            <div :if={@workspaces != [] && @search_query == ""}>
              <div class="h-px bg-[#1a1a1a] mx-3 my-1" />
              <div class="px-4 py-1.5 flex items-center justify-between">
                <span class="text-[10px] text-[#3a3a3a] uppercase tracking-wider font-medium">
                  Workspaces
                </span>
                <span class="text-[10px] text-[#2a2a2a] font-mono">Cmd+Shift+S to save</span>
              </div>
              <%= for ws <- @workspaces do %>
                <button
                  phx-click="launch_workspace"
                  phx-value-name={ws.name}
                  class="w-full px-4 py-2 text-left text-sm text-[#e8dcc0] hover:bg-[#141414] flex items-center justify-between transition-colors cursor-pointer group"
                >
                  <div class="flex items-center gap-3 min-w-0">
                    <span class="text-[#ffd04a] font-mono text-xs shrink-0">W</span>
                    <span class="truncate">{ws.name}</span>
                    <span :if={ws.description} class="text-[10px] text-[#3a3a3a] truncate max-w-48">
                      {ws.description}
                    </span>
                  </div>
                  <span class="text-[10px] text-[#2a2a2a] font-mono group-hover:text-[#3a3a3a]">
                    {length(ws.sessions)} sessions
                  </span>
                </button>
              <% end %>
            </div>

            <%!-- Save current workspace (shown when sessions are open) --%>
            <div :if={@session_order != [] && @search_query == ""}>
              <button
                phx-click="save_workspace"
                phx-value-name={"snapshot-#{Date.to_iso8601(Date.utc_today())}"}
                class="w-full px-4 py-2 text-left text-sm text-[#5a5a5a] hover:text-[#e8dcc0] hover:bg-[#141414] flex items-center gap-3 transition-colors cursor-pointer"
              >
                <span class="text-[#5a9bcf] font-mono text-xs">S</span>
                <span>Save current as workspace</span>
              </button>
            </div>

            <div class="h-px bg-[#1a1a1a] mx-3 my-1" />
            <%= for project <- sorted_projects(filtered_projects(@projects, @search_query), @priority_map) do %>
              <% prio = Map.get(@priority_map, project.name) %>
              <div class="flex items-center group">
                <button
                  phx-click="new_project_session"
                  phx-value-name={project.name}
                  class="flex-1 px-4 py-2 text-left text-sm text-[#e8dcc0] hover:bg-[#141414] flex items-center justify-between transition-colors cursor-pointer"
                >
                  <div class="flex items-center gap-3 min-w-0">
                    <span class={"w-1.5 h-1.5 rounded-full shrink-0 " <> project_status_color(project.status)} />
                    <span class="truncate">{project.name}</span>
                    <span
                      :if={prio && prio.top_action}
                      class="text-[10px] text-[#ffd04a]/60 truncate max-w-48 hidden sm:inline"
                    >
                      {prio.top_action}
                    </span>
                  </div>
                  <div class="flex items-center gap-2 shrink-0">
                    <span :if={git = @git_statuses[project.name]} class="flex items-center gap-1">
                      <span class="text-[10px] text-[#3a3a3a] font-mono">{git.branch}</span>
                      <span
                        :if={git.dirty}
                        class="w-1.5 h-1.5 rounded-full bg-[#ffd04a]"
                        title={"#{git.changes} changes"}
                      />
                    </span>
                    <span :if={prio} class={"text-[10px] font-mono " <> score_color(prio.score)}>
                      {prio.score}
                    </span>
                    <span class="text-[10px] text-[#2a2a2a] font-mono group-hover:text-[#3a3a3a]">
                      {project.status}
                    </span>
                  </div>
                </button>
                <button
                  phx-click="burst_mode"
                  phx-value-name={project.name}
                  title="Burst Mode: spawn full project context"
                  class="px-2 py-2 text-[10px] text-[#2a2a2a] hover:text-[#ffd04a] hover:bg-[#141414] transition-colors cursor-pointer opacity-0 group-hover:opacity-100 font-mono shrink-0"
                >
                  BURST
                </button>
              </div>
            <% end %>
          </div>
        </div>
      </div>

      <%!-- Toast Notifications — errors reframed as attack surfaces --%>
      <div class="fixed bottom-4 right-4 z-50 space-y-2 pointer-events-none">
        <%= for toast <- @toasts do %>
          <div class={"pointer-events-auto animate-slide-in px-4 py-2.5 rounded-[7px] border shadow-lg font-mono " <> toast_class(toast.severity)}>
            <div class="flex items-center gap-2 text-sm">
              <span class={"w-2 h-2 rounded-full shrink-0 " <> toast_dot_class(toast.severity)} />
              <span class="truncate max-w-sm">{toast.message}</span>
              <button
                phx-click="dismiss_toast_manual"
                phx-value-id={toast.id}
                class="text-[10px] opacity-50 hover:opacity-100 ml-2 shrink-0 cursor-pointer"
              >
                x
              </button>
            </div>
            <div :if={toast[:action_hint]} class="text-[10px] text-[#5a5a5a] mt-1 ml-4 pl-0.5">
              {toast.action_hint}
            </div>
          </div>
        <% end %>
      </div>
    </div>
    """
  end

  defp project_status_color("ACTIVE"), do: "bg-[#5ea85e]"
  defp project_status_color("BUILDING"), do: "bg-[#ffd04a]"
  defp project_status_color("MAINTENANCE"), do: "bg-[#3a3a3a]"
  defp project_status_color(_), do: "bg-[#2a2a2a]"

  defp priority_rank_class(0), do: "bg-[#ffd04a] text-[#050505]"
  defp priority_rank_class(1), do: "bg-[#ffd04a]/60 text-[#050505]"
  defp priority_rank_class(_), do: "bg-[#1a1a1a] text-[#5a5a5a]"

  defp score_color(score) when score >= 100, do: "text-[#ffd04a]"
  defp score_color(score) when score >= 50, do: "text-[#e8dcc0]/60"
  defp score_color(_), do: "text-[#3a3a3a]"

  defp urgency_class(:critical), do: "bg-[#e05252]/20 text-[#e05252]"
  defp urgency_class(:high), do: "bg-[#ffd04a]/20 text-[#ffd04a]"
  defp urgency_class(:medium), do: "bg-[#5a9bcf]/20 text-[#5a9bcf]"
  defp urgency_class(_), do: "bg-[#1a1a1a] text-[#5a5a5a]"

  defp sorted_projects(projects, priority_map) do
    Enum.sort_by(projects, fn p ->
      case Map.get(priority_map, p.name) do
        nil -> 0
        prio -> -prio.score
      end
    end)
  end

  defp session_status_class(:active), do: "bg-[#1a2a1a] text-[#5ea85e]"
  defp session_status_class(:idle), do: "bg-[#1a1a1a] text-[#5a5a5a]"
  defp session_status_class(:errored), do: "bg-[#2a1a1a] text-[#e05252]"
  defp session_status_class(:completed), do: "bg-[#1a2a1a] text-[#5ea85e]"
  defp session_status_class(_), do: "bg-[#1a1a1a] text-[#5a5a5a]"

  defp status_label(:active), do: "active"
  defp status_label(:idle), do: "idle"
  defp status_label(:errored), do: "error"
  defp status_label(:completed), do: "done"
  defp status_label(:exited), do: "exited"
  defp status_label(status), do: to_string(status)

  defp toast_class(:error), do: "bg-[#0a0a0a] border-[#e05252]/30 text-[#e05252]"
  defp toast_class(:warning), do: "bg-[#0a0a0a] border-[#ffd04a]/30 text-[#ffd04a]"
  defp toast_class(:success), do: "bg-[#0a0a0a] border-[#5ea85e]/30 text-[#5ea85e]"
  defp toast_class(_), do: "bg-[#0a0a0a] border-[#1a1a1a] text-[#e8dcc0]"

  defp toast_dot_class(:error), do: "bg-[#e05252]"
  defp toast_dot_class(:warning), do: "bg-[#ffd04a]"
  defp toast_dot_class(:success), do: "bg-[#5ea85e]"
  defp toast_dot_class(_), do: "bg-[#5a5a5a]"

  # Energy cycle helpers
  defp energy_dot_class(:mud), do: "bg-[#5a5a5a]"
  defp energy_dot_class(:rising), do: "bg-[#e8b839]"
  defp energy_dot_class(:peak), do: "bg-[#5ea85e]"
  defp energy_dot_class(:winding_down), do: "bg-[#5a9bcf]"
  defp energy_dot_class(_), do: "bg-[#2a2a2a]"

  defp energy_text_class(:mud), do: "text-[#5a5a5a]"
  defp energy_text_class(:rising), do: "text-[#e8b839]"
  defp energy_text_class(:peak), do: "text-[#5ea85e]"
  defp energy_text_class(:winding_down), do: "text-[#5a9bcf]"
  defp energy_text_class(_), do: "text-[#2a2a2a]"

  defp energy_label(:mud), do: "MUD"
  defp energy_label(:rising), do: "RISING"
  defp energy_label(:peak), do: "PEAK"
  defp energy_label(:winding_down), do: "WIND"
  defp energy_label(:rest), do: "REST"

  defp format_flow_time(minutes) when minutes < 60, do: "#{minutes}m"
  defp format_flow_time(minutes), do: "#{div(minutes, 60)}h#{rem(minutes, 60)}m"

  # Activity DNA labels and colors
  defp activity_label(:build), do: "build"
  defp activity_label(:test), do: "test"
  defp activity_label(:deploy), do: "deploy"
  defp activity_label(:debug), do: "debug"
  defp activity_label(:agent), do: "agent"
  defp activity_label(:git), do: "git"
  defp activity_label(:flow), do: "flow"
  defp activity_label(:idle), do: "idle"
  defp activity_label(other), do: to_string(other)

  defp resume_urgency_color(score) when score >= 80, do: "text-[#ffd04a]"
  defp resume_urgency_color(score) when score >= 50, do: "text-[#e8dcc0]/60"
  defp resume_urgency_color(_), do: "text-[#3a3a3a]"

  defp activity_color(:build), do: "text-[#5ea85e]"
  defp activity_color(:test), do: "text-[#5a9bcf]"
  defp activity_color(:deploy), do: "text-[#ffd04a]"
  defp activity_color(:debug), do: "text-[#e05252]"
  defp activity_color(:agent), do: "text-[#b07aff]"
  defp activity_color(:flow), do: "text-[#ffd04a]"
  defp activity_color(_), do: "text-[#3a3a3a]"
end
