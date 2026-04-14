defmodule Cortex.Agent.Tools.FileWrite do
  @moduledoc false
  @behaviour Cortex.Agent.Tool

  @impl true
  def name, do: "file_write"

  @impl true
  def description,
    do: "Write content to a file. Creates the file if it doesn't exist, overwrites if it does."

  @impl true
  def parameters do
    %{
      type: "object",
      required: ["file_path", "content"],
      properties: %{
        file_path: %{type: "string", description: "Absolute path to the file to write"},
        content: %{type: "string", description: "The content to write to the file"}
      }
    }
  end

  @impl true
  def execute(params, context) do
    path = resolve_path(params["file_path"], context)
    content = params["content"]

    # Ensure parent directory exists
    path |> Path.dirname() |> File.mkdir_p!()

    case File.write(path, content) do
      :ok ->
        line_count = content |> String.split("\n") |> length()
        {:ok, "Wrote #{line_count} lines to #{path}"}

      {:error, reason} ->
        {:error, "Failed to write #{path}: #{reason}"}
    end
  end

  defp resolve_path("/" <> _ = absolute, _context), do: absolute
  defp resolve_path(relative, %{cwd: cwd}), do: Path.join(cwd, relative)
  defp resolve_path(relative, _), do: Path.expand(relative)
end
