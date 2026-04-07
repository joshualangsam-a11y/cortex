defmodule CortexWeb.Onboarding.WizardLive do
  use CortexWeb, :live_view

  @default_commands %{
    "elixir" => "mix phx.server",
    "node" => "npm run dev",
    "rust" => "cargo run",
    "python" => "python -m flask run",
    "go" => "go run .",
    "other" => ""
  }

  @impl true
  def mount(_params, _session, socket) do
    home = System.user_home!()

    socket =
      socket
      |> assign(:step, 1)
      |> assign(:scan_path, home)
      |> assign(:scanning, false)
      |> assign(:found_projects, [])
      |> assign(:configured_projects, [])

    {:ok, socket, layout: false}
  end

  @impl true
  def render(%{step: 1} = assigns) do
    ~H"""
    <.wizard_shell step={1}>
      <div class="flex flex-col items-center justify-center py-16 px-8">
        <div class="text-[#ffd04a] text-5xl font-mono font-bold tracking-tight mb-4">
          Cortex
        </div>
        <div class="text-[#e8dcc0]/60 text-lg font-mono mb-2">
          Terminal mission control for multi-project developers
        </div>
        <div class="text-[#5a5a5a] text-sm font-mono mb-12">
          Manage concurrent terminal sessions from one dashboard
        </div>
        <button
          phx-click="next_step"
          class="px-8 py-3 rounded-lg border border-[#ffd04a]/20 text-[#ffd04a] font-mono text-sm
                 hover:border-[#ffd04a]/40 hover:bg-[#ffd04a]/5 transition-all duration-200"
        >
          Set up your workspace &rarr;
        </button>
      </div>
    </.wizard_shell>
    """
  end

  def render(%{step: 2} = assigns) do
    ~H"""
    <.wizard_shell step={2}>
      <div class="px-8 py-8">
        <h2 class="text-[#ffd04a] text-xl font-mono font-bold mb-1">Scan Projects</h2>
        <p class="text-[#5a5a5a] text-sm font-mono mb-6">Where do your projects live?</p>

        <div class="flex gap-3 mb-6">
          <input
            type="text"
            value={@scan_path}
            phx-change="update_path"
            phx-target={@myself || nil}
            name="path"
            class="flex-1 bg-[#0a0a0a] border border-[#1a1a1a] rounded-lg px-4 py-2.5
                   text-[#e8dcc0] font-mono text-sm focus:border-[#ffd04a]/40 focus:outline-none
                   placeholder-[#3a3a3a]"
            placeholder="~/projects"
          />
          <button
            phx-click="scan"
            disabled={@scanning}
            class="px-6 py-2.5 rounded-lg border border-[#ffd04a]/20 text-[#ffd04a] font-mono text-sm
                   hover:border-[#ffd04a]/40 hover:bg-[#ffd04a]/5 transition-all duration-200
                   disabled:opacity-40 disabled:cursor-not-allowed"
          >
            {if @scanning, do: "Scanning...", else: "Scan"}
          </button>
        </div>

        <%= if @found_projects != [] do %>
          <div class="flex items-center justify-between mb-3">
            <span class="text-[#5a5a5a] text-xs font-mono">
              Found {length(@found_projects)} projects
            </span>
            <button
              phx-click="select_all"
              class="text-[#ffd04a]/60 text-xs font-mono hover:text-[#ffd04a] transition-colors"
            >
              {if all_selected?(@found_projects), do: "Deselect all", else: "Select all"}
            </button>
          </div>

          <div class="space-y-1.5 max-h-[360px] overflow-y-auto pr-1">
            <div
              :for={{project, idx} <- Enum.with_index(@found_projects)}
              phx-click="toggle_project"
              phx-value-index={idx}
              class={"flex items-center gap-3 px-4 py-3 rounded-lg border cursor-pointer transition-all duration-150 #{if project.selected, do: "border-[#ffd04a]/30 bg-[#ffd04a]/5", else: "border-[#1a1a1a] bg-[#080808] hover:border-[#1a1a1a]/80"}"}
            >
              <input
                type="checkbox"
                checked={project.selected}
                class="accent-[#ffd04a] cursor-pointer"
                tabindex="-1"
              />
              <div class="flex-1 min-w-0">
                <div class="flex items-center gap-2">
                  <span class="text-[#e8dcc0] font-mono text-sm font-medium">{project.name}</span>
                  <span class={"px-1.5 py-0.5 rounded text-[10px] font-mono #{type_color(project.type)}"}>
                    {project.type}
                  </span>
                </div>
                <div class="text-[#3a3a3a] text-xs font-mono truncate">{project.path}</div>
              </div>
            </div>
          </div>
        <% end %>

        <div class="flex justify-between mt-8">
          <button
            phx-click="prev_step"
            class="px-6 py-2.5 rounded-lg border border-[#1a1a1a] text-[#5a5a5a] font-mono text-sm
                   hover:border-[#3a3a3a] hover:text-[#e8dcc0] transition-all duration-200"
          >
            &larr; Back
          </button>
          <button
            phx-click="next_step"
            disabled={selected_count(@found_projects) == 0}
            class="px-6 py-2.5 rounded-lg border border-[#ffd04a]/20 text-[#ffd04a] font-mono text-sm
                   hover:border-[#ffd04a]/40 hover:bg-[#ffd04a]/5 transition-all duration-200
                   disabled:opacity-40 disabled:cursor-not-allowed"
          >
            Add {selected_count(@found_projects)} selected &rarr;
          </button>
        </div>
      </div>
    </.wizard_shell>
    """
  end

  def render(%{step: 3} = assigns) do
    ~H"""
    <.wizard_shell step={3}>
      <div class="px-8 py-8">
        <h2 class="text-[#ffd04a] text-xl font-mono font-bold mb-1">Configure Projects</h2>
        <p class="text-[#5a5a5a] text-sm font-mono mb-6">Adjust settings for each project</p>

        <div class="space-y-4 max-h-[400px] overflow-y-auto pr-1">
          <div
            :for={{project, idx} <- Enum.with_index(@configured_projects)}
            class="border border-[#1a1a1a] bg-[#080808] rounded-lg p-4"
          >
            <div class="flex items-center gap-2 mb-3">
              <span class={"px-1.5 py-0.5 rounded text-[10px] font-mono #{type_color(project.type)}"}>
                {project.type}
              </span>
              <span class="text-[#3a3a3a] text-xs font-mono truncate">{project.path}</span>
            </div>

            <div class="grid grid-cols-2 gap-3">
              <div>
                <label class="text-[#5a5a5a] text-xs font-mono mb-1 block">Name</label>
                <input
                  type="text"
                  value={project.name}
                  phx-change="update_project"
                  phx-value-index={idx}
                  phx-value-field="name"
                  name={"project_#{idx}_name"}
                  class="w-full bg-[#0a0a0a] border border-[#1a1a1a] rounded-lg px-3 py-2
                         text-[#e8dcc0] font-mono text-sm focus:border-[#ffd04a]/40 focus:outline-none"
                />
              </div>
              <div>
                <label class="text-[#5a5a5a] text-xs font-mono mb-1 block">Port</label>
                <input
                  type="text"
                  value={project.port || ""}
                  phx-change="update_project"
                  phx-value-index={idx}
                  phx-value-field="port"
                  name={"project_#{idx}_port"}
                  placeholder="optional"
                  class="w-full bg-[#0a0a0a] border border-[#1a1a1a] rounded-lg px-3 py-2
                         text-[#e8dcc0] font-mono text-sm focus:border-[#ffd04a]/40 focus:outline-none
                         placeholder-[#3a3a3a]"
                />
              </div>
            </div>

            <div class="mt-3">
              <label class="text-[#5a5a5a] text-xs font-mono mb-1 block">Dev command</label>
              <input
                type="text"
                value={project.dev_command}
                phx-change="update_project"
                phx-value-index={idx}
                phx-value-field="dev_command"
                name={"project_#{idx}_dev_command"}
                class="w-full bg-[#0a0a0a] border border-[#1a1a1a] rounded-lg px-3 py-2
                       text-[#e8dcc0] font-mono text-sm focus:border-[#ffd04a]/40 focus:outline-none"
              />
            </div>

            <div class="mt-3">
              <label class="text-[#5a5a5a] text-xs font-mono mb-1 flex justify-between">
                <span>Priority weight</span>
                <span class="text-[#ffd04a]">{project.priority}</span>
              </label>
              <input
                type="range"
                min="1"
                max="100"
                value={project.priority}
                phx-change="update_project"
                phx-value-index={idx}
                phx-value-field="priority"
                name={"project_#{idx}_priority"}
                class="w-full accent-[#ffd04a] cursor-pointer"
              />
            </div>
          </div>
        </div>

        <div class="flex justify-between mt-8">
          <button
            phx-click="prev_step"
            class="px-6 py-2.5 rounded-lg border border-[#1a1a1a] text-[#5a5a5a] font-mono text-sm
                   hover:border-[#3a3a3a] hover:text-[#e8dcc0] transition-all duration-200"
          >
            &larr; Back
          </button>
          <button
            phx-click="finish"
            class="px-8 py-2.5 rounded-lg border border-[#ffd04a]/20 text-[#ffd04a] font-mono text-sm
                   hover:border-[#ffd04a]/40 hover:bg-[#ffd04a]/5 transition-all duration-200"
          >
            Save & Launch Cortex
          </button>
        </div>
      </div>
    </.wizard_shell>
    """
  end

  # -- Events --

  @impl true
  def handle_event("next_step", _params, socket) do
    socket =
      case socket.assigns.step do
        2 ->
          configured =
            socket.assigns.found_projects
            |> Enum.filter(& &1.selected)
            |> Enum.map(fn p ->
              Map.merge(p, %{
                dev_command: Map.get(@default_commands, p.type, ""),
                priority: 50,
                port: nil
              })
            end)

          socket
          |> assign(:configured_projects, configured)
          |> assign(:step, 3)

        step ->
          assign(socket, :step, step + 1)
      end

    {:noreply, socket}
  end

  def handle_event("prev_step", _params, socket) do
    {:noreply, assign(socket, :step, max(socket.assigns.step - 1, 1))}
  end

  def handle_event("update_path", %{"path" => path}, socket) do
    {:noreply, assign(socket, :scan_path, path)}
  end

  def handle_event("scan", _params, socket) do
    socket = assign(socket, :scanning, true)
    send(self(), :do_scan)
    {:noreply, socket}
  end

  def handle_event("toggle_project", %{"index" => idx_str}, socket) do
    idx = String.to_integer(idx_str)

    projects =
      List.update_at(socket.assigns.found_projects, idx, fn p ->
        %{p | selected: !p.selected}
      end)

    {:noreply, assign(socket, :found_projects, projects)}
  end

  def handle_event("select_all", _params, socket) do
    all_selected = all_selected?(socket.assigns.found_projects)
    projects = Enum.map(socket.assigns.found_projects, &%{&1 | selected: !all_selected})
    {:noreply, assign(socket, :found_projects, projects)}
  end

  def handle_event("update_project", params, socket) do
    idx = params |> Map.get("index") |> String.to_integer()
    field = params |> Map.get("field") |> String.to_existing_atom()

    value =
      case field do
        :priority ->
          params |> Map.get("project_#{idx}_priority", "50") |> String.to_integer()

        :port ->
          case params |> Map.get("project_#{idx}_port", "") do
            "" -> nil
            v -> v
          end

        :name ->
          Map.get(params, "project_#{idx}_name", "")

        :dev_command ->
          Map.get(params, "project_#{idx}_dev_command", "")
      end

    projects =
      List.update_at(socket.assigns.configured_projects, idx, fn p ->
        Map.put(p, field, value)
      end)

    {:noreply, assign(socket, :configured_projects, projects)}
  end

  def handle_event("finish", _params, socket) do
    user_id = get_user_id(socket)
    save_projects_to_db(socket.assigns.configured_projects, user_id)
    {:noreply, push_navigate(socket, to: "/dashboard")}
  end

  @impl true
  def handle_info(:do_scan, socket) do
    projects = scan_for_projects(socket.assigns.scan_path)

    socket =
      socket
      |> assign(:found_projects, projects)
      |> assign(:scanning, false)

    {:noreply, socket}
  end

  # -- Scanning --

  defp scan_for_projects(base_path) do
    base_path
    |> File.ls!()
    |> Enum.filter(fn name ->
      path = Path.join(base_path, name)
      File.dir?(path) && File.exists?(Path.join(path, ".git")) && !String.starts_with?(name, ".")
    end)
    |> Enum.map(fn name ->
      path = Path.join(base_path, name)
      type = detect_type(path)
      %{name: name, path: path, type: type, selected: false}
    end)
    |> Enum.sort_by(& &1.name)
  rescue
    _ -> []
  end

  defp detect_type(path) do
    cond do
      File.exists?(Path.join(path, "mix.exs")) -> "elixir"
      File.exists?(Path.join(path, "package.json")) -> "node"
      File.exists?(Path.join(path, "Cargo.toml")) -> "rust"
      File.exists?(Path.join(path, "pyproject.toml")) -> "python"
      File.exists?(Path.join(path, "go.mod")) -> "go"
      true -> "other"
    end
  end

  # -- Persistence --

  defp save_projects_to_db(projects, user_id) do
    Enum.each(projects, fn p ->
      Cortex.Projects.create_user_project(user_id, %{
        "name" => p.name,
        "path" => p.path,
        "project_type" => p.type,
        "dev_command" => p.dev_command,
        "priority_weight" => p.priority,
        "port" => p.port,
        "status" => "active"
      })
    end)
  end

  defp get_user_id(socket) do
    case socket.assigns[:current_user] do
      %{id: id} -> id
      _ -> "00000000-0000-0000-0000-000000000001"
    end
  end

  # -- Helpers --

  defp all_selected?([]), do: false
  defp all_selected?(projects), do: Enum.all?(projects, & &1.selected)

  defp selected_count(projects), do: Enum.count(projects, & &1.selected)

  defp type_color("elixir"), do: "bg-purple-500/20 text-purple-400"
  defp type_color("node"), do: "bg-green-500/20 text-green-400"
  defp type_color("rust"), do: "bg-orange-500/20 text-orange-400"
  defp type_color("python"), do: "bg-blue-500/20 text-blue-400"
  defp type_color("go"), do: "bg-cyan-500/20 text-cyan-400"
  defp type_color(_), do: "bg-[#3a3a3a]/30 text-[#5a5a5a]"

  # -- Shell component --

  defp wizard_shell(assigns) do
    ~H"""
    <div class="min-h-screen bg-[#050505] flex items-center justify-center p-4">
      <div class="w-full max-w-2xl">
        <%!-- Steps indicator --%>
        <div class="flex items-center justify-center gap-2 mb-8">
          <.step_dot num={1} current={@step} label="Welcome" />
          <div class="w-8 h-px bg-[#1a1a1a]" />
          <.step_dot num={2} current={@step} label="Scan" />
          <div class="w-8 h-px bg-[#1a1a1a]" />
          <.step_dot num={3} current={@step} label="Configure" />
        </div>

        <%!-- Card --%>
        <div class="bg-[#080808] border border-[#1a1a1a] rounded-lg overflow-hidden">
          {render_slot(@inner_block)}
        </div>
      </div>
    </div>
    """
  end

  defp step_dot(assigns) do
    ~H"""
    <div class="flex items-center gap-2">
      <div class={"w-7 h-7 rounded-full flex items-center justify-center text-xs font-mono font-bold transition-all duration-200 #{if @num == @current, do: "bg-[#ffd04a]/15 text-[#ffd04a] border border-[#ffd04a]/40", else: if(@num < @current, do: "bg-[#ffd04a]/10 text-[#ffd04a]/60 border border-[#ffd04a]/20", else: "bg-[#0a0a0a] text-[#3a3a3a] border border-[#1a1a1a]")}"}>
        <%= if @num < @current do %>
          &#10003;
        <% else %>
          {@num}
        <% end %>
      </div>
      <span class={"text-xs font-mono #{if @num == @current, do: "text-[#e8dcc0]", else: "text-[#3a3a3a]"}"}>
        {@label}
      </span>
    </div>
    """
  end
end
