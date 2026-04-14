defmodule Cortex.Agent.Tools.Bash do
  @moduledoc false
  @behaviour Cortex.Agent.Tool

  @impl true
  def name, do: "bash"

  @impl true
  def description,
    do:
      "Execute a bash command and return its output. Commands run in the project working directory."

  @impl true
  def parameters do
    %{
      type: "object",
      required: ["command"],
      properties: %{
        command: %{type: "string", description: "The bash command to execute"},
        timeout: %{
          type: "integer",
          description: "Timeout in milliseconds (default 120000, max 600000)"
        }
      }
    }
  end

  @max_output_bytes 100_000

  @impl true
  def execute(params, context) do
    command = params["command"]
    timeout = min(params["timeout"] || 120_000, 600_000)
    cwd = Map.get(context, :cwd, System.user_home!())

    # Security: block obviously dangerous commands
    if dangerous?(command) do
      {:error, "Command blocked for safety: #{command}"}
    else
      run_command(command, cwd, timeout)
    end
  end

  defp run_command(command, cwd, timeout) do
    task =
      Task.async(fn ->
        System.cmd("bash", ["-c", command],
          cd: cwd,
          stderr_to_stdout: true,
          env: [{"TERM", "dumb"}, {"NO_COLOR", "1"}]
        )
      end)

    case Task.yield(task, timeout) || Task.shutdown(task, :brutal_kill) do
      {:ok, {output, exit_code}} ->
        truncated = truncate(output, @max_output_bytes)

        result =
          if exit_code == 0 do
            truncated
          else
            "Exit code: #{exit_code}\n#{truncated}"
          end

        {:ok, result}

      nil ->
        {:error, "Command timed out after #{timeout}ms"}
    end
  end

  defp truncate(output, max) when byte_size(output) > max do
    binary_part(output, 0, max) <> "\n... (truncated, #{byte_size(output)} bytes total)"
  end

  defp truncate(output, _max), do: output

  defp dangerous?(cmd) do
    dangerous_patterns = [
      ~r/rm\s+-rf\s+[\/~]/,
      ~r/mkfs/,
      ~r/dd\s+if=/,
      ~r/:(){ :|:& };:/
    ]

    Enum.any?(dangerous_patterns, &Regex.match?(&1, cmd))
  end
end
