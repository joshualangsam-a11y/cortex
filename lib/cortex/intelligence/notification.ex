defmodule Cortex.Intelligence.Notification do
  @moduledoc """
  Struct representing a terminal output notification.

  Broadcasted on PubSub when the OutputMonitor detects a
  pattern match in a session's terminal output.
  """

  @enforce_keys [:id, :session_id, :type, :severity, :message, :timestamp]
  defstruct [:id, :session_id, :type, :severity, :message, :timestamp]

  @type severity :: :info | :warning | :error | :success
  @type t :: %__MODULE__{
          id: String.t(),
          session_id: String.t(),
          type: atom(),
          severity: severity(),
          message: String.t(),
          timestamp: DateTime.t()
        }

  @doc "Build a notification from a pattern match result for a given session."
  def from_match(session_id, %{type: type, severity: severity, message: message}) do
    %__MODULE__{
      id: Ecto.UUID.generate(),
      session_id: session_id,
      type: type,
      severity: severity,
      message: message,
      timestamp: DateTime.utc_now()
    }
  end
end
