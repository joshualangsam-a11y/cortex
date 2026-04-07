defmodule Cortex.Workspaces do
  @moduledoc """
  Context for workspace presets and auto-launch.
  Workspaces capture a set of sessions that can be saved and restored.
  """

  alias Cortex.Repo
  alias Cortex.Workspaces.Workspace
  alias Cortex.Terminals
  alias Cortex.Projects
  import Ecto.Query

  @doc "Upsert a workspace by name."
  def save_workspace(name, sessions, grid_cols \\ 3) do
    case Repo.one(from(w in Workspace, where: w.name == ^name)) do
      nil ->
        %Workspace{}
        |> Workspace.changeset(%{name: name, sessions: sessions, grid_cols: grid_cols})
        |> Repo.insert()

      existing ->
        existing
        |> Workspace.changeset(%{sessions: sessions, grid_cols: grid_cols})
        |> Repo.update()
    end
  end

  @doc "Get a workspace by name."
  def load_workspace(name) do
    Repo.one(from(w in Workspace, where: w.name == ^name))
  end

  @doc "List all workspaces."
  def list_workspaces do
    Repo.all(from(w in Workspace, order_by: [asc: w.name]))
  end

  @doc "Delete a workspace by name."
  def delete_workspace(name) do
    case Repo.one(from(w in Workspace, where: w.name == ^name)) do
      nil -> {:error, :not_found}
      workspace -> Repo.delete(workspace)
    end
  end

  @doc """
  Launch a workspace -- creates all sessions defined in the workspace.
  Each session map should have keys like "project_name", "title", "cwd", "auto_command".
  """
  def launch_workspace(name) do
    case load_workspace(name) do
      nil ->
        {:error, :not_found}

      workspace ->
        results =
          workspace.sessions
          |> Enum.map(fn session_def ->
            project = resolve_project(session_def)

            opts =
              %{
                title: session_def["title"] || (project && project.name) || "terminal",
                cwd: (project && project.path) || session_def["cwd"] || System.user_home!(),
                project: project,
                auto_command: session_def["auto_command"]
              }
              |> Enum.reject(fn {_k, v} -> is_nil(v) end)
              |> Map.new()

            Terminals.create_session(opts)
          end)

        {:ok, results}
    end
  end

  @doc """
  Capture current running sessions into a workspace.
  Saves the current state so it can be restored later.
  """
  def save_current(name, description \\ nil) do
    sessions =
      Terminals.list_sessions()
      |> Enum.map(fn session ->
        %{
          "title" => session[:title] || "terminal",
          "project_name" => session[:project] && session[:project].name,
          "cwd" => session[:cwd] || System.user_home!()
        }
      end)

    case Repo.one(from(w in Workspace, where: w.name == ^name)) do
      nil ->
        %Workspace{}
        |> Workspace.changeset(%{name: name, description: description, sessions: sessions})
        |> Repo.insert()

      existing ->
        attrs = %{sessions: sessions}
        attrs = if description, do: Map.put(attrs, :description, description), else: attrs

        existing
        |> Workspace.changeset(attrs)
        |> Repo.update()
    end
  end

  @doc "Seed built-in default workspaces."
  def seed_defaults do
    projects = Projects.list_projects()

    # "morning" -- top priority projects
    morning_names = ["Hemp Route CRM", "FuelOps", "VapeOps"]

    morning_sessions =
      morning_names
      |> Enum.map(fn name -> Enum.find(projects, fn p -> p.name == name end) end)
      |> Enum.reject(&is_nil/1)
      |> Enum.map(fn p -> %{"project_name" => p.name, "title" => p.name} end)

    save_workspace("morning", morning_sessions, 3)

    # "build" -- all ACTIVE status projects
    build_sessions =
      projects
      |> Enum.filter(fn p -> p.status == "ACTIVE" end)
      |> Enum.map(fn p -> %{"project_name" => p.name, "title" => p.name} end)

    save_workspace("build", build_sessions, 3)

    # "hemp-route" -- Hemp Route project only
    hemp =
      projects
      |> Enum.filter(fn p -> p.name == "Hemp Route CRM" end)
      |> Enum.map(fn p -> %{"project_name" => p.name, "title" => p.name} end)

    save_workspace("hemp-route", hemp, 1)

    :ok
  end

  # --- Private ---

  defp resolve_project(%{"project_name" => name}) when is_binary(name) do
    Projects.get_project(name)
  end

  defp resolve_project(_), do: nil
end
