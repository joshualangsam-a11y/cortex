defmodule Cortex.Intelligence.Notification do
  @moduledoc """
  Struct representing a terminal output notification.

  Broadcasted on PubSub when the OutputMonitor detects a
  pattern match in a session's terminal output.
  """

  @enforce_keys [:id, :session_id, :type, :severity, :message, :timestamp]
  defstruct [:id, :session_id, :type, :severity, :message, :timestamp, :action_hint]

  @type severity :: :info | :warning | :error | :success
  @type t :: %__MODULE__{
          id: String.t(),
          session_id: String.t(),
          type: atom(),
          severity: severity(),
          message: String.t(),
          timestamp: DateTime.t(),
          action_hint: String.t() | nil
        }

  @doc "Build a notification from a pattern match result for a given session."
  def from_match(session_id, %{type: type, severity: severity, message: message} = match) do
    %__MODULE__{
      id: Ecto.UUID.generate(),
      session_id: session_id,
      type: type,
      severity: severity,
      message: reframe_message(type, severity, message),
      action_hint: Map.get(match, :action_hint),
      timestamp: DateTime.utc_now()
    }
  end

  # Reframe errors as attack surfaces, not failures
  defp reframe_message(_type, :error, message) do
    cond do
      message =~ ~r/Compile error/ -> "compile error — fix and re-run"
      message =~ ~r/Syntax error/ -> "syntax error — quick fix"
      message =~ ~r/Test failures/ -> String.replace(message, "detected", "— knock them out")
      message =~ ~r/Build failed/ -> "build broke — attack it"
      message =~ ~r/Deploy failed/ -> "deploy failed — check logs, retry"
      true -> message
    end
  end

  defp reframe_message(_type, _severity, message), do: message
end
