defmodule Cortex.Terminals do
  @moduledoc """
  Context for managing terminal sessions.
  Persists session metadata to Postgres for crash recovery.
  """

  alias Cortex.Repo
  alias Cortex.Terminal.SessionServer
  alias Cortex.Terminals.Session
  alias Cortex.Terminals.Layout
  import Ecto.Query

  def list_sessions do
    Cortex.Terminal.SessionRegistry
    |> Registry.select([{{:"$1", :"$2", :"$3"}, [], [:"$1"]}])
    |> Enum.map(fn id ->
      try do
        SessionServer.get_state(id)
      catch
        :exit, _ -> nil
      end
    end)
    |> Enum.reject(&is_nil/1)
  end

  def create_session(opts \\ %{}) do
    id = Ecto.UUID.generate()
    project = Map.get(opts, :project)

    server_opts = [
      id: id,
      cwd: Map.get(opts, :cwd, System.user_home!()),
      cols: Map.get(opts, :cols, 120),
      rows: Map.get(opts, :rows, 30),
      command: Map.get(opts, :command),
      project: project,
      title: Map.get(opts, :title)
    ]

    server_opts = Enum.reject(server_opts, fn {_k, v} -> is_nil(v) end)

    case DynamicSupervisor.start_child(
           Cortex.Terminal.SessionSupervisor,
           {SessionServer, server_opts}
         ) do
      {:ok, _pid} ->
        # Persist to DB for crash recovery
        persist_session(id, server_opts, project)

        # Auto-execute command after shell is ready
        case Map.get(opts, :auto_command) do
          nil ->
            :ok

          cmd ->
            Task.start(fn ->
              Process.sleep(800)

              try do
                SessionServer.write(id, cmd <> "\n")
              catch
                :exit, _ -> :ok
              end
            end)
        end

        {:ok, id}

      error ->
        error
    end
  end

  def kill_session(id) do
    # Clean up persisted scrollback
    Cortex.Terminal.Scrollback.delete_from_disk(id)

    try do
      SessionServer.kill_session(id)
    catch
      :exit, _ -> {:error, :not_found}
    end
  end

  def mark_exited(id, exit_code) do
    case Repo.get(Session, id) do
      nil ->
        :ok

      session ->
        session
        |> Session.changeset(%{
          status: "exited",
          exit_code: exit_code,
          exited_at: DateTime.utc_now()
        })
        |> Repo.update()
    end
  end

  def write(id, data) do
    try do
      SessionServer.write(id, data)
    catch
      :exit, _ -> {:error, :not_found}
    end
  end

  def resize(id, cols, rows) do
    try do
      SessionServer.resize(id, cols, rows)
    catch
      :exit, _ -> {:error, :not_found}
    end
  end

  def get_scrollback(id) do
    try do
      SessionServer.get_scrollback(id)
    catch
      :exit, _ -> {:error, :not_found}
    end
  end

  # --- Layout persistence ---

  def save_layout(session_order, grid_cols \\ 3) do
    case Repo.one(from(l in Layout, where: l.name == "last_workspace")) do
      nil ->
        %Layout{}
        |> Layout.changeset(%{
          name: "last_workspace",
          session_order: session_order,
          grid_cols: grid_cols,
          is_default: true
        })
        |> Repo.insert()

      layout ->
        layout
        |> Layout.changeset(%{session_order: session_order, grid_cols: grid_cols})
        |> Repo.update()
    end
  end

  def get_last_layout do
    Repo.one(from(l in Layout, where: l.name == "last_workspace"))
  end

  # --- Crash recovery ---

  @doc """
  Called on boot. Finds sessions that were "running" when the app last died,
  re-spawns PTYs for each, and returns the restored session IDs.
  """
  def restore_sessions do
    stale =
      Repo.all(from(s in Session, where: s.status == "running", order_by: [asc: s.started_at]))

    if stale == [] do
      {:ok, []}
    else
      restored =
        Enum.map(stale, fn record ->
          project = resolve_project(record.project_name)

          # Use the project's path as cwd when the project is resolved,
          # so restored sessions land in the right directory
          cwd = project_cwd(project, record.cwd)

          opts = %{
            cwd: cwd,
            cols: record.cols || 120,
            rows: record.rows || 30,
            command: record.command,
            project: project,
            title: record.title
          }

          # Mark old record as exited (it crashed)
          record
          |> Session.changeset(%{status: "exited", exit_code: -1, exited_at: DateTime.utc_now()})
          |> Repo.update()

          # Create a fresh session
          case create_session(opts) do
            {:ok, new_id} -> {record.id, new_id}
            _error -> nil
          end
        end)
        |> Enum.reject(&is_nil/1)

      {:ok, restored}
    end
  end

  # --- Private ---

  defp persist_session(id, opts, project) do
    attrs = %{
      id: id,
      title: Keyword.get(opts, :title, "terminal"),
      command: Keyword.get(opts, :command, System.get_env("SHELL") || "/bin/zsh"),
      cwd: Keyword.get(opts, :cwd),
      project_name: if(project, do: project.name),
      status: "running",
      cols: Keyword.get(opts, :cols, 120),
      rows: Keyword.get(opts, :rows, 30),
      started_at: DateTime.utc_now()
    }

    %Session{}
    |> Session.changeset(attrs)
    |> Repo.insert(on_conflict: :replace_all, conflict_target: :id)
  rescue
    e ->
      require Logger
      Logger.warning("Failed to persist session #{id}: #{inspect(e)}")
  end

  defp resolve_project(nil), do: nil

  defp resolve_project(name) do
    Cortex.Projects.get_project(name)
  end

  defp project_cwd(%{path: path}, _fallback) when is_binary(path), do: path
  defp project_cwd(_, fallback) when is_binary(fallback), do: fallback
  defp project_cwd(_, _), do: System.user_home!()
end
