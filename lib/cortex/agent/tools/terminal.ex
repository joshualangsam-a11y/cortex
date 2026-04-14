defmodule Cortex.Agent.Tools.Terminal do
  @moduledoc false
  @behaviour Cortex.Agent.Tool

  @impl true
  def name, do: "terminal"

  @impl true
  def description do
    "Open a visible terminal session in the Cortex dashboard grid, optionally running a command. " <>
      "Use this for long-running processes (servers, watchers, test suites) that the user should see. " <>
      "For quick one-off commands, use the bash tool instead."
  end

  @impl true
  def parameters do
    %{
      type: "object",
      required: ["title"],
      properties: %{
        title: %{type: "string", description: "Title for the terminal tab (e.g. 'test suite', 'dev server')"},
        command: %{type: "string", description: "Command to auto-run after the shell starts (e.g. 'mix test', 'npm run dev')"},
        cwd: %{type: "string", description: "Working directory (defaults to project cwd)"}
      }
    }
  end

  @impl true
  def execute(params, context) do
    title = params["title"]
    command = params["command"]
    cwd = params["cwd"] || Map.get(context, :cwd, System.user_home!())

    opts = %{
      cwd: cwd,
      title: title
    }

    opts = if command, do: Map.put(opts, :auto_command, command), else: opts

    case Cortex.Terminals.create_session(opts) do
      {:ok, session_id} ->
        result = "Opened terminal '#{title}' in the dashboard grid (session: #{String.slice(session_id, 0, 8)})"
        result = if command, do: result <> "\nRunning: #{command}", else: result
        {:ok, result}

      {:error, reason} ->
        {:error, "Failed to open terminal: #{inspect(reason)}"}
    end
  end
end
