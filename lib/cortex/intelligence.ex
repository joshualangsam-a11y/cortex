defmodule Cortex.Intelligence do
  @moduledoc """
  Context for the priority engine.
  Delegates to the Prioritizer GenServer.
  """

  alias Cortex.Intelligence.Prioritizer

  defdelegate ranked, to: Prioritizer
  defdelegate top_actions(n \\ 3), to: Prioritizer
  defdelegate refresh, to: Prioritizer
end
