defmodule Cortex.Agent do
  @moduledoc false

  alias Cortex.Agent.{Session, Conversations, ModelRouter}

  def start_session(opts \\ []) do
    id = Keyword.get_lazy(opts, :id, fn -> Ecto.UUID.generate() end)

    opts =
      opts
      |> Keyword.put(:id, id)
      |> Keyword.put_new(:cwd, System.user_home!())

    case DynamicSupervisor.start_child(Cortex.Agent.SessionSupervisor, {Session, opts}) do
      {:ok, _pid} -> {:ok, id}
      {:error, reason} -> {:error, reason}
    end
  end

  def send_message(session_id, content), do: Session.send_message(session_id, content)
  def approve_tool(session_id, tool_call_id), do: Session.approve_tool(session_id, tool_call_id)
  def deny_tool(session_id, tool_call_id), do: Session.deny_tool(session_id, tool_call_id)
  def set_model(session_id, model), do: Session.set_model(session_id, model)

  def get_session(session_id) do
    Session.get_state(session_id)
  rescue
    _ -> nil
  end

  def stop_session(session_id) do
    Session.stop(session_id)
  rescue
    _ -> :ok
  end

  # Conversation persistence
  defdelegate list_conversations(limit \\ 20), to: Conversations, as: :list_recent
  defdelegate get_conversation(id), to: Conversations, as: :get
  defdelegate delete_conversation(id), to: Conversations, as: :delete

  def resume_conversation(conversation_id, opts \\ []) do
    case Conversations.get(conversation_id) do
      nil ->
        {:error, :not_found}

      conv ->
        start_session(
          opts
          |> Keyword.put(:conversation_id, conversation_id)
          |> Keyword.put(:messages, conv.messages)
          |> Keyword.put_new(:cwd, conv.cwd)
        )
    end
  end

  # Model routing
  defdelegate model_label(model), to: ModelRouter, as: :label
  defdelegate model_color(model), to: ModelRouter, as: :color
  defdelegate estimate_cost(model, input, output), to: ModelRouter
  defdelegate format_cost(cost), to: ModelRouter
  defdelegate format_tokens(n), to: ModelRouter

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
