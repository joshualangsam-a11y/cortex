defmodule Cortex.Projects do
  @moduledoc """
  Context for project registry, user-configured projects, and presets.

  Two sources:
  - Registry (GenServer): parses ~/CLAUDE.md at boot for dashboard use
  - DB (user_projects): user-configurable, editable via settings UI
  """

  import Ecto.Query
  alias Cortex.Repo
  alias Cortex.Projects.{Registry, UserProject, Scanner}

  # -- Registry delegation (dashboard use) --

  defdelegate list_projects, to: Registry
  defdelegate get_project(name), to: Registry

  def active_projects do
    list_projects()
    |> Enum.filter(fn p -> p.status in ["ACTIVE", "BUILDING"] end)
  end

  # -- DB-backed user projects --

  def list_user_projects(user_id) do
    UserProject
    |> where(user_id: ^user_id)
    |> order_by([p], desc: p.priority_weight, asc: p.name)
    |> Repo.all()
  end

  def get_user_project(user_id, name) do
    UserProject
    |> where(user_id: ^user_id, name: ^name)
    |> Repo.one()
  end

  def get_user_project!(id) do
    Repo.get!(UserProject, id)
  end

  def create_user_project(user_id, attrs) do
    %UserProject{}
    |> UserProject.changeset(Map.put(attrs, "user_id", user_id))
    |> Repo.insert()
  end

  def update_user_project(%UserProject{} = project, attrs) do
    project
    |> UserProject.changeset(attrs)
    |> Repo.update()
  end

  def delete_user_project(%UserProject{} = project) do
    Repo.delete(project)
  end

  def change_user_project(%UserProject{} = project, attrs \\ %{}) do
    UserProject.changeset(project, attrs)
  end

  # -- Detection helpers --

  def detect_project_type(path) do
    Scanner.detect_type(path)
  end

  def suggest_dev_command(project_type) do
    Scanner.suggest_dev_command(project_type)
  end

  # -- Import from CLAUDE.md --

  @doc """
  Reads ~/CLAUDE.md project table and creates user_projects for each entry.
  Skips projects that already exist for the user.
  """
  def import_from_claude_md(user_id) do
    existing = list_user_projects(user_id) |> Enum.map(& &1.name) |> MapSet.new()

    Registry.list_projects()
    |> Enum.reject(fn p -> MapSet.member?(existing, p.name) end)
    |> Enum.map(fn p ->
      status = normalize_status(p.status)
      project_type = if File.dir?(p.path), do: detect_project_type(p.path), else: nil
      dev_cmd = if project_type, do: suggest_dev_command(project_type), else: nil

      create_user_project(user_id, %{
        "name" => p.name,
        "path" => p.path,
        "status" => status,
        "port" => p.port,
        "project_type" => project_type,
        "dev_command" => dev_cmd,
        "priority_weight" => 50
      })
    end)
  end

  # -- Filesystem scanning --

  def scan_filesystem(base_path \\ System.user_home!()) do
    Scanner.scan(base_path)
  end

  # -- Private --

  defp normalize_status(status) do
    case String.downcase(status || "active") do
      "active" -> "active"
      "building" -> "building"
      "maintenance" -> "maintenance"
      "archived" -> "archived"
      "development" -> "building"
      "personal" -> "active"
      _ -> "active"
    end
  end
end
