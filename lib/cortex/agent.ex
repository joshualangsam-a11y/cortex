defmodule Cortex.Agent do
  @moduledoc false

  alias Cortex.Agent.Session

  @doc "Start a new agent session. Returns {:ok, session_id}."
  def start_session(opts \\ []) do
    id = Keyword.get_lazy(opts, :id, fn -> Ecto.UUID.generate() end)

    opts =
      opts
      |> Keyword.put(:id, id)
      |> Keyword.put_new(:cwd, System.user_home!())

    case DynamicSupervisor.start_child(
           Cortex.Agent.SessionSupervisor,
           {Session, opts}
         ) do
      {:ok, _pid} -> {:ok, id}
      {:error, reason} -> {:error, reason}
    end
  end

  @doc "Send a user message to an agent session."
  def send_message(session_id, content) do
    Session.send_message(session_id, content)
  end

  @doc "Approve a pending tool call."
  def approve_tool(session_id, tool_call_id) do
    Session.approve_tool(session_id, tool_call_id)
  end

  @doc "Deny a pending tool call."
  def deny_tool(session_id, tool_call_id) do
    Session.deny_tool(session_id, tool_call_id)
  end

  @doc "Get session info."
  def get_session(session_id) do
    Session.get_state(session_id)
  rescue
    _ -> nil
  end

  @doc "Stop an agent session."
  def stop_session(session_id) do
    Session.stop(session_id)
  rescue
    _ -> :ok
  end

  @doc "List all active agent sessions."
  def list_sessions do
    Cortex.Agent.SessionSupervisor
    |> DynamicSupervisor.which_children()
    |> Enum.filter(fn {_, pid, _, _} -> is_pid(pid) end)
    |> Enum.map(fn {_, pid, _, _} ->
      try do
        GenServer.call(pid, :get_state, 1000)
      catch
        _, _ -> nil
      end
    end)
    |> Enum.reject(&is_nil/1)
  end
end
