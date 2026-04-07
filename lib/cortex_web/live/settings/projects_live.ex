defmodule CortexWeb.Settings.ProjectsLive do
  use CortexWeb, :live_view

  alias Cortex.Projects
  alias Cortex.Projects.UserProject

  import CortexWeb.Settings.SettingsLayout

  @impl true
  def mount(_params, _session, socket) do
    # TODO: Replace with real user_id from auth session
    user_id = get_user_id(socket)

    projects = Projects.list_user_projects(user_id)

    socket =
      socket
      |> assign(:page_title, "Projects - Settings")
      |> assign(:user_id, user_id)
      |> assign(:projects, projects)
      |> assign(:show_form, false)
      |> assign(:editing_project, nil)
      |> assign(:changeset, Projects.change_user_project(%UserProject{}))
      |> assign(:scanning, false)
      |> assign(:scan_results, [])
      |> assign(:importing, false)

    {:ok, socket}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <.settings_layout current_page={:projects}>
      <div class="max-w-4xl">
        <!-- Header -->
        <div class="flex items-center justify-between mb-6">
          <div>
            <h1 class="text-xl font-semibold text-[#ffd04a]">Projects</h1>
            <p class="text-xs text-[#5a5a5a] mt-1">
              Configure projects for terminal sessions and priority scoring
            </p>
          </div>
          <div class="flex gap-2">
            <button
              phx-click="import_claude_md"
              disabled={@importing}
              class="px-3 py-1.5 text-xs rounded-md border border-[#1a1a1a] text-[#e8dcc0] hover:border-[#ffd04a] hover:text-[#ffd04a] transition-colors disabled:opacity-50"
            >
              {if @importing, do: "Importing...", else: "Import from CLAUDE.md"}
            </button>
            <button
              phx-click="scan_filesystem"
              disabled={@scanning}
              class="px-3 py-1.5 text-xs rounded-md border border-[#1a1a1a] text-[#e8dcc0] hover:border-[#ffd04a] hover:text-[#ffd04a] transition-colors disabled:opacity-50"
            >
              {if @scanning, do: "Scanning...", else: "Scan Filesystem"}
            </button>
            <button
              phx-click="show_add_form"
              class="px-3 py-1.5 text-xs rounded-md bg-[#ffd04a] text-[#050505] font-medium hover:opacity-90 transition-opacity"
            >
              Add Project
            </button>
          </div>
        </div>
        
    <!-- Scan Results -->
        <%= if @scan_results != [] do %>
          <div class="mb-6 border border-[#1a1a1a] rounded-md bg-[#0a0a0a] p-4">
            <div class="flex items-center justify-between mb-3">
              <h3 class="text-sm font-medium text-[#ffd04a]">
                Found {@scan_results |> length()} repositories
              </h3>
              <button
                phx-click="clear_scan"
                class="text-xs text-[#5a5a5a] hover:text-[#e8dcc0]"
              >
                Dismiss
              </button>
            </div>
            <div class="space-y-1 max-h-48 overflow-y-auto">
              <%= for result <- @scan_results do %>
                <div class="flex items-center justify-between py-1.5 px-2 rounded hover:bg-[#1a1a1a]">
                  <div class="flex items-center gap-3">
                    <span class={"text-xs px-1.5 py-0.5 rounded #{type_badge_class(result.type)}"}>
                      {result.type}
                    </span>
                    <span class="text-sm">{result.name}</span>
                    <span class="text-xs text-[#3a3a3a]">{result.path}</span>
                  </div>
                  <button
                    phx-click="add_scanned"
                    phx-value-name={result.name}
                    phx-value-path={result.path}
                    phx-value-type={result.type}
                    class="text-xs text-[#ffd04a] hover:underline"
                  >
                    Add
                  </button>
                </div>
              <% end %>
            </div>
          </div>
        <% end %>
        
    <!-- Add/Edit Form -->
        <%= if @show_form do %>
          <div class="mb-6 border border-[#1a1a1a] rounded-md bg-[#0a0a0a] p-4">
            <h3 class="text-sm font-medium text-[#ffd04a] mb-4">
              {if @editing_project, do: "Edit Project", else: "Add Project"}
            </h3>
            <.form
              for={@changeset}
              phx-submit={if @editing_project, do: "update_project", else: "create_project"}
              phx-change="validate"
              class="space-y-4"
            >
              <div class="grid grid-cols-2 gap-4">
                <!-- Name -->
                <div>
                  <label class="block text-xs text-[#5a5a5a] mb-1">Name</label>
                  <input
                    type="text"
                    name="user_project[name]"
                    value={Phoenix.HTML.Form.input_value(@changeset, :name)}
                    class="w-full bg-[#050505] border border-[#1a1a1a] rounded-md px-3 py-2 text-sm text-[#e8dcc0] focus:border-[#ffd04a] focus:outline-none"
                    placeholder="My Project"
                  />
                  <.form_error changeset={@changeset} field={:name} />
                </div>
                
    <!-- Path -->
                <div>
                  <label class="block text-xs text-[#5a5a5a] mb-1">Path</label>
                  <div class="flex gap-2">
                    <input
                      type="text"
                      name="user_project[path]"
                      value={Phoenix.HTML.Form.input_value(@changeset, :path)}
                      class="flex-1 bg-[#050505] border border-[#1a1a1a] rounded-md px-3 py-2 text-sm text-[#e8dcc0] focus:border-[#ffd04a] focus:outline-none"
                      placeholder="~/my-project"
                    />
                    <button
                      type="button"
                      phx-click="auto_detect"
                      class="px-2 py-2 text-xs border border-[#1a1a1a] rounded-md text-[#5a5a5a] hover:text-[#ffd04a] hover:border-[#ffd04a] transition-colors"
                      title="Auto-detect type and dev command"
                    >
                      Detect
                    </button>
                  </div>
                  <.form_error changeset={@changeset} field={:path} />
                </div>
                
    <!-- Status -->
                <div>
                  <label class="block text-xs text-[#5a5a5a] mb-1">Status</label>
                  <select
                    name="user_project[status]"
                    class="w-full bg-[#050505] border border-[#1a1a1a] rounded-md px-3 py-2 text-sm text-[#e8dcc0] focus:border-[#ffd04a] focus:outline-none"
                  >
                    <%= for status <- UserProject.statuses() do %>
                      <option
                        value={status}
                        selected={Phoenix.HTML.Form.input_value(@changeset, :status) == status}
                      >
                        {String.capitalize(status)}
                      </option>
                    <% end %>
                  </select>
                </div>
                
    <!-- Port -->
                <div>
                  <label class="block text-xs text-[#5a5a5a] mb-1">Port</label>
                  <input
                    type="number"
                    name="user_project[port]"
                    value={Phoenix.HTML.Form.input_value(@changeset, :port)}
                    class="w-full bg-[#050505] border border-[#1a1a1a] rounded-md px-3 py-2 text-sm text-[#e8dcc0] focus:border-[#ffd04a] focus:outline-none"
                    placeholder="3000"
                    min="1"
                  />
                  <.form_error changeset={@changeset} field={:port} />
                </div>
                
    <!-- Project Type -->
                <div>
                  <label class="block text-xs text-[#5a5a5a] mb-1">Type</label>
                  <select
                    name="user_project[project_type]"
                    class="w-full bg-[#050505] border border-[#1a1a1a] rounded-md px-3 py-2 text-sm text-[#e8dcc0] focus:border-[#ffd04a] focus:outline-none"
                  >
                    <option value="">Auto</option>
                    <%= for type <- UserProject.project_types() do %>
                      <option
                        value={type}
                        selected={Phoenix.HTML.Form.input_value(@changeset, :project_type) == type}
                      >
                        {type}
                      </option>
                    <% end %>
                  </select>
                </div>
                
    <!-- Dev Command -->
                <div>
                  <label class="block text-xs text-[#5a5a5a] mb-1">Dev Command</label>
                  <input
                    type="text"
                    name="user_project[dev_command]"
                    value={Phoenix.HTML.Form.input_value(@changeset, :dev_command)}
                    class="w-full bg-[#050505] border border-[#1a1a1a] rounded-md px-3 py-2 text-sm text-[#e8dcc0] focus:border-[#ffd04a] focus:outline-none"
                    placeholder="mix phx.server"
                  />
                </div>
              </div>
              
    <!-- Priority Weight -->
              <div>
                <label class="block text-xs text-[#5a5a5a] mb-1">
                  Priority Weight: {Phoenix.HTML.Form.input_value(@changeset, :priority_weight) || 50}
                </label>
                <input
                  type="range"
                  name="user_project[priority_weight]"
                  value={Phoenix.HTML.Form.input_value(@changeset, :priority_weight) || 50}
                  min="1"
                  max="100"
                  class="w-full accent-[#ffd04a]"
                />
                <div class="flex justify-between text-[10px] text-[#3a3a3a]">
                  <span>Low</span>
                  <span>High</span>
                </div>
              </div>
              
    <!-- Description -->
              <div>
                <label class="block text-xs text-[#5a5a5a] mb-1">Description</label>
                <input
                  type="text"
                  name="user_project[description]"
                  value={Phoenix.HTML.Form.input_value(@changeset, :description)}
                  class="w-full bg-[#050505] border border-[#1a1a1a] rounded-md px-3 py-2 text-sm text-[#e8dcc0] focus:border-[#ffd04a] focus:outline-none"
                  placeholder="Brief description"
                />
              </div>
              
    <!-- Actions -->
              <div class="flex gap-2 pt-2">
                <button
                  type="submit"
                  class="px-4 py-2 text-xs rounded-md bg-[#ffd04a] text-[#050505] font-medium hover:opacity-90 transition-opacity"
                >
                  {if @editing_project, do: "Update", else: "Create"}
                </button>
                <button
                  type="button"
                  phx-click="cancel_form"
                  class="px-4 py-2 text-xs rounded-md border border-[#1a1a1a] text-[#5a5a5a] hover:text-[#e8dcc0] transition-colors"
                >
                  Cancel
                </button>
              </div>
            </.form>
          </div>
        <% end %>
        
    <!-- Projects Table -->
        <%= if @projects == [] do %>
          <div class="border border-[#1a1a1a] rounded-md bg-[#0a0a0a] p-12 text-center">
            <p class="text-[#5a5a5a] text-sm mb-4">No projects configured</p>
            <p class="text-[#3a3a3a] text-xs">
              Add projects manually, import from CLAUDE.md, or scan your filesystem
            </p>
          </div>
        <% else %>
          <div class="border border-[#1a1a1a] rounded-md overflow-hidden">
            <table class="w-full">
              <thead>
                <tr class="border-b border-[#1a1a1a] bg-[#0a0a0a]">
                  <th class="text-left px-4 py-2 text-xs font-medium text-[#5a5a5a]">Name</th>
                  <th class="text-left px-4 py-2 text-xs font-medium text-[#5a5a5a]">Path</th>
                  <th class="text-left px-4 py-2 text-xs font-medium text-[#5a5a5a]">Status</th>
                  <th class="text-left px-4 py-2 text-xs font-medium text-[#5a5a5a]">Port</th>
                  <th class="text-left px-4 py-2 text-xs font-medium text-[#5a5a5a]">Type</th>
                  <th class="text-left px-4 py-2 text-xs font-medium text-[#5a5a5a]">Priority</th>
                  <th class="text-right px-4 py-2 text-xs font-medium text-[#5a5a5a]"></th>
                </tr>
              </thead>
              <tbody>
                <%= for project <- @projects do %>
                  <tr class="border-b border-[#1a1a1a] hover:bg-[#0a0a0a] transition-colors">
                    <td class="px-4 py-3">
                      <span class="text-sm font-medium text-[#e8dcc0]">{project.name}</span>
                    </td>
                    <td class="px-4 py-3">
                      <span class="text-xs text-[#5a5a5a] font-mono">{project.path}</span>
                    </td>
                    <td class="px-4 py-3">
                      <span class={"text-xs px-2 py-0.5 rounded-md #{status_badge_class(project.status)}"}>
                        {project.status}
                      </span>
                    </td>
                    <td class="px-4 py-3">
                      <span class="text-xs text-[#5a5a5a]">
                        {project.port || "-"}
                      </span>
                    </td>
                    <td class="px-4 py-3">
                      <span class={"text-xs px-1.5 py-0.5 rounded #{type_badge_class(project.project_type)}"}>
                        {project.project_type || "-"}
                      </span>
                    </td>
                    <td class="px-4 py-3">
                      <div class="flex items-center gap-2">
                        <div class="w-16 h-1.5 bg-[#1a1a1a] rounded-full overflow-hidden">
                          <div
                            class="h-full bg-[#ffd04a] rounded-full"
                            style={"width: #{project.priority_weight}%"}
                          >
                          </div>
                        </div>
                        <span class="text-[10px] text-[#3a3a3a]">{project.priority_weight}</span>
                      </div>
                    </td>
                    <td class="px-4 py-3 text-right">
                      <div class="flex items-center justify-end gap-2">
                        <button
                          phx-click="edit_project"
                          phx-value-id={project.id}
                          class="text-xs text-[#5a5a5a] hover:text-[#ffd04a] transition-colors"
                        >
                          Edit
                        </button>
                        <button
                          phx-click="delete_project"
                          phx-value-id={project.id}
                          data-confirm="Delete this project?"
                          class="text-xs text-[#5a5a5a] hover:text-[#e05252] transition-colors"
                        >
                          Delete
                        </button>
                      </div>
                    </td>
                  </tr>
                <% end %>
              </tbody>
            </table>
          </div>
        <% end %>
      </div>
    </.settings_layout>
    """
  end

  # -- Form error component --

  defp form_error(assigns) do
    errors =
      case assigns.changeset do
        %Ecto.Changeset{} = cs ->
          Ecto.Changeset.traverse_errors(cs, fn {msg, _opts} -> msg end)
          |> Map.get(assigns.field, [])

        _ ->
          []
      end

    assigns = assign(assigns, :errors, errors)

    ~H"""
    <%= for error <- @errors do %>
      <p class="text-xs text-[#e05252] mt-1">{error}</p>
    <% end %>
    """
  end

  # -- Events --

  @impl true
  def handle_event("show_add_form", _params, socket) do
    {:noreply,
     socket
     |> assign(:show_form, true)
     |> assign(:editing_project, nil)
     |> assign(:changeset, Projects.change_user_project(%UserProject{}))}
  end

  def handle_event("cancel_form", _params, socket) do
    {:noreply,
     socket
     |> assign(:show_form, false)
     |> assign(:editing_project, nil)}
  end

  def handle_event("validate", %{"user_project" => params}, socket) do
    changeset =
      case socket.assigns.editing_project do
        nil -> %UserProject{}
        project -> project
      end
      |> Projects.change_user_project(params)
      |> Map.put(:action, :validate)

    {:noreply, assign(socket, :changeset, changeset)}
  end

  def handle_event("create_project", %{"user_project" => params}, socket) do
    case Projects.create_user_project(socket.assigns.user_id, params) do
      {:ok, _project} ->
        projects = Projects.list_user_projects(socket.assigns.user_id)

        {:noreply,
         socket
         |> assign(:projects, projects)
         |> assign(:show_form, false)
         |> put_flash(:info, "Project created")}

      {:error, changeset} ->
        {:noreply, assign(socket, :changeset, changeset)}
    end
  end

  def handle_event("update_project", %{"user_project" => params}, socket) do
    case Projects.update_user_project(socket.assigns.editing_project, params) do
      {:ok, _project} ->
        projects = Projects.list_user_projects(socket.assigns.user_id)

        {:noreply,
         socket
         |> assign(:projects, projects)
         |> assign(:show_form, false)
         |> assign(:editing_project, nil)
         |> put_flash(:info, "Project updated")}

      {:error, changeset} ->
        {:noreply, assign(socket, :changeset, changeset)}
    end
  end

  def handle_event("edit_project", %{"id" => id}, socket) do
    project = Projects.get_user_project!(id)
    changeset = Projects.change_user_project(project)

    {:noreply,
     socket
     |> assign(:show_form, true)
     |> assign(:editing_project, project)
     |> assign(:changeset, changeset)}
  end

  def handle_event("delete_project", %{"id" => id}, socket) do
    project = Projects.get_user_project!(id)
    {:ok, _} = Projects.delete_user_project(project)
    projects = Projects.list_user_projects(socket.assigns.user_id)

    {:noreply,
     socket
     |> assign(:projects, projects)
     |> put_flash(:info, "Project deleted")}
  end

  def handle_event("import_claude_md", _params, socket) do
    results = Projects.import_from_claude_md(socket.assigns.user_id)
    imported = Enum.count(results, fn {status, _} -> status == :ok end)
    projects = Projects.list_user_projects(socket.assigns.user_id)

    {:noreply,
     socket
     |> assign(:projects, projects)
     |> assign(:importing, false)
     |> put_flash(:info, "Imported #{imported} projects from CLAUDE.md")}
  end

  def handle_event("scan_filesystem", _params, socket) do
    existing_names =
      socket.assigns.projects
      |> Enum.map(& &1.name)
      |> MapSet.new()

    results =
      Projects.scan_filesystem()
      |> Enum.reject(fn r -> MapSet.member?(existing_names, r.name) end)

    {:noreply,
     socket
     |> assign(:scan_results, results)
     |> assign(:scanning, false)}
  end

  def handle_event("clear_scan", _params, socket) do
    {:noreply, assign(socket, :scan_results, [])}
  end

  def handle_event("add_scanned", %{"name" => name, "path" => path, "type" => type}, socket) do
    dev_cmd = Projects.suggest_dev_command(type)

    case Projects.create_user_project(socket.assigns.user_id, %{
           "name" => name,
           "path" => path,
           "project_type" => type,
           "dev_command" => dev_cmd,
           "status" => "active"
         }) do
      {:ok, _} ->
        projects = Projects.list_user_projects(socket.assigns.user_id)
        scan_results = Enum.reject(socket.assigns.scan_results, fn r -> r.name == name end)

        {:noreply,
         socket
         |> assign(:projects, projects)
         |> assign(:scan_results, scan_results)
         |> put_flash(:info, "Added #{name}")}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Failed to add #{name}")}
    end
  end

  def handle_event("auto_detect", _params, socket) do
    path =
      case socket.assigns.changeset do
        %Ecto.Changeset{} = cs -> Ecto.Changeset.get_field(cs, :path)
        _ -> nil
      end

    if path && path != "" do
      expanded = String.replace(path, "~", System.user_home!())
      type = Projects.detect_project_type(expanded)
      dev_cmd = Projects.suggest_dev_command(type)

      changeset =
        socket.assigns.changeset
        |> Ecto.Changeset.put_change(:project_type, type)
        |> Ecto.Changeset.put_change(:dev_command, dev_cmd)

      {:noreply, assign(socket, :changeset, changeset)}
    else
      {:noreply, put_flash(socket, :error, "Enter a path first")}
    end
  end

  # -- Helpers --

  defp get_user_id(socket) do
    case socket.assigns[:current_user] do
      %{id: id} -> id
      _ -> "00000000-0000-0000-0000-000000000001"
    end
  end

  defp status_badge_class("active"), do: "bg-[#5ea85e]/20 text-[#5ea85e]"
  defp status_badge_class("building"), do: "bg-[#ffd04a]/20 text-[#ffd04a]"
  defp status_badge_class("maintenance"), do: "bg-[#5a9bcf]/20 text-[#5a9bcf]"
  defp status_badge_class("archived"), do: "bg-[#3a3a3a]/20 text-[#3a3a3a]"
  defp status_badge_class(_), do: "bg-[#1a1a1a] text-[#5a5a5a]"

  defp type_badge_class("elixir"), do: "bg-[#6b4c9a]/20 text-[#a97cdf]"
  defp type_badge_class("node"), do: "bg-[#5ea85e]/20 text-[#5ea85e]"
  defp type_badge_class("python"), do: "bg-[#3b7dd8]/20 text-[#5a9bcf]"
  defp type_badge_class("rust"), do: "bg-[#ce5c33]/20 text-[#e8835a]"
  defp type_badge_class("go"), do: "bg-[#00add8]/20 text-[#00add8]"
  defp type_badge_class(_), do: "bg-[#1a1a1a] text-[#5a5a5a]"
end
