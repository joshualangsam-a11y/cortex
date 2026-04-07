defmodule Cortex.Terminals do
  @moduledoc """
  Context for managing terminal sessions.
  """

  alias Cortex.Terminal.SessionServer

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

    server_opts = [
      id: id,
      cwd: Map.get(opts, :cwd, System.user_home!()),
      cols: Map.get(opts, :cols, 120),
      rows: Map.get(opts, :rows, 30),
      command: Map.get(opts, :command),
      project: Map.get(opts, :project),
      title: Map.get(opts, :title)
    ]

    server_opts = Enum.reject(server_opts, fn {_k, v} -> is_nil(v) end)

    case DynamicSupervisor.start_child(
           Cortex.Terminal.SessionSupervisor,
           {SessionServer, server_opts}
         ) do
      {:ok, _pid} -> {:ok, id}
      error -> error
    end
  end

  def kill_session(id) do
    try do
      SessionServer.kill_session(id)
    catch
      :exit, _ -> {:error, :not_found}
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
end
