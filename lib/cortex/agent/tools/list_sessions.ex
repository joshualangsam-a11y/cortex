defmodule Cortex.Agent.Tools.ListSessions do
  @moduledoc false
  @behaviour Cortex.Agent.Tool

  @impl true
  def name, do: "list_terminals"

  @impl true
  def description do
    "List all active terminal sessions in the Cortex dashboard. " <>
      "Shows session IDs, titles, status, and working directories."
  end

  @impl true
  def parameters do
    %{type: "object", properties: %{}}
  end

  @impl true
  def execute(_params, _context) do
    sessions = Cortex.Terminals.list_sessions()

    if sessions == [] do
      {:ok, "No active terminal sessions."}
    else
      lines =
        Enum.map(sessions, fn s ->
          status = Map.get(s, :status, :running)
          "#{String.slice(s.id, 0, 8)}  #{Map.get(s, :title, "terminal")}  [#{status}]  #{Map.get(s, :cwd, "~")}"
        end)

      {:ok, "#{length(sessions)} active sessions:\n#{Enum.join(lines, "\n")}"}
    end
  end
end
