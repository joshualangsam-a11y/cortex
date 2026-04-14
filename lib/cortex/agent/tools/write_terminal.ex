defmodule Cortex.Agent.Tools.WriteTerminal do
  @moduledoc false
  @behaviour Cortex.Agent.Tool

  @impl true
  def name, do: "write_terminal"

  @impl true
  def description do
    "Send input to an existing terminal session in the Cortex dashboard. " <>
      "Use this to type commands into a running terminal, like sending Ctrl+C or running follow-up commands."
  end

  @impl true
  def parameters do
    %{
      type: "object",
      required: ["session_id", "input"],
      properties: %{
        session_id: %{type: "string", description: "Terminal session ID (from list_terminals)"},
        input: %{type: "string", description: "Text to send to the terminal (\\n for Enter)"}
      }
    }
  end

  @impl true
  def execute(params, _context) do
    session_id = params["session_id"]
    input = params["input"]

    # Allow partial session IDs (first 8 chars)
    full_id = resolve_session_id(session_id)

    case full_id do
      nil ->
        {:error, "Terminal session not found: #{session_id}"}

      id ->
        case Cortex.Terminal.SessionServer.write(id, input) do
          :ok -> {:ok, "Sent #{byte_size(input)} bytes to terminal #{String.slice(id, 0, 8)}"}
          {:error, reason} -> {:error, "Failed to write to terminal: #{inspect(reason)}"}
        end
    end
  end

  defp resolve_session_id(partial) do
    Cortex.Terminals.list_sessions()
    |> Enum.find_value(fn s ->
      if s.id == partial or String.starts_with?(s.id, partial), do: s.id
    end)
  end
end
