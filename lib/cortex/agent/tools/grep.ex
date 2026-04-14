defmodule Cortex.Agent.Tools.Grep do
  @moduledoc false
  @behaviour Cortex.Agent.Tool

  @impl true
  def name, do: "grep"

  @impl true
  def description do
    "Search file contents using ripgrep. Returns matching lines with file paths and line numbers."
  end

  @impl true
  def parameters do
    %{
      type: "object",
      required: ["pattern"],
      properties: %{
        pattern: %{type: "string", description: "Regex pattern to search for"},
        path: %{type: "string", description: "Directory or file to search in (defaults to cwd)"},
        glob: %{type: "string", description: "File glob filter (e.g. '*.ex', '*.ts')"},
        case_insensitive: %{type: "boolean", description: "Case insensitive search"},
        max_results: %{type: "integer", description: "Maximum number of results (default 50)"}
      }
    }
  end

  @impl true
  def execute(params, context) do
    pattern = params["pattern"]
    cwd = Map.get(context, :cwd, System.user_home!())
    path = params["path"] || cwd
    max_results = params["max_results"] || 50

    args = build_args(pattern, path, params)

    case System.cmd("rg", args, cd: cwd, stderr_to_stdout: true) do
      {output, 0} ->
        lines = String.split(output, "\n", trim: true)
        truncated = Enum.take(lines, max_results)
        result = Enum.join(truncated, "\n")

        suffix =
          if length(lines) > max_results,
            do: "\n... (#{length(lines) - max_results} more matches)",
            else: ""

        {:ok, result <> suffix}

      {_, 1} ->
        {:ok, "No matches found."}

      {output, _} ->
        {:error, "ripgrep error: #{String.trim(output)}"}
    end
  end

  defp build_args(pattern, path, params) do
    args = ["--no-heading", "--line-number", "--color", "never"]
    args = if params["case_insensitive"], do: args ++ ["-i"], else: args
    args = if params["glob"], do: args ++ ["--glob", params["glob"]], else: args
    args ++ [pattern, path]
  end
end
