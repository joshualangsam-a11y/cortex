defmodule Cortex.Agent.Tools.Glob do
  @moduledoc false
  @behaviour Cortex.Agent.Tool

  @impl true
  def name, do: "glob"

  @impl true
  def description, do: "Find files matching a glob pattern. Returns matching file paths."

  @impl true
  def parameters do
    %{
      type: "object",
      required: ["pattern"],
      properties: %{
        pattern: %{type: "string", description: "Glob pattern (e.g. '**/*.ex', 'lib/**/*.ts')"},
        path: %{type: "string", description: "Base directory to search from (defaults to cwd)"}
      }
    }
  end

  @max_results 200

  @impl true
  def execute(params, context) do
    pattern = params["pattern"]
    cwd = Map.get(context, :cwd, System.user_home!())
    base = params["path"] || cwd

    full_pattern = Path.join(base, pattern)
    matches = Path.wildcard(full_pattern)

    if matches == [] do
      {:ok, "No files found matching #{pattern}"}
    else
      truncated = Enum.take(matches, @max_results)
      result = Enum.join(truncated, "\n")

      suffix =
        if length(matches) > @max_results,
          do: "\n... (#{length(matches) - @max_results} more files)",
          else: ""

      {:ok, "#{length(matches)} files found:\n#{result}#{suffix}"}
    end
  end
end
