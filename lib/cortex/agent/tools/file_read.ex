defmodule Cortex.Agent.Tools.FileRead do
  @moduledoc false
  @behaviour Cortex.Agent.Tool

  @impl true
  def name, do: "file_read"

  @impl true
  def description, do: "Read the contents of a file. Returns the file content with line numbers."

  @impl true
  def parameters do
    %{
      type: "object",
      required: ["file_path"],
      properties: %{
        file_path: %{type: "string", description: "Absolute path to the file to read"},
        offset: %{type: "integer", description: "Line number to start reading from (0-based)"},
        limit: %{type: "integer", description: "Maximum number of lines to read"}
      }
    }
  end

  @impl true
  def execute(params, context) do
    path = resolve_path(params["file_path"], context)
    offset = params["offset"] || 0
    limit = params["limit"] || 2000

    case File.read(path) do
      {:ok, content} ->
        lines =
          content
          |> String.split("\n")
          |> Enum.drop(offset)
          |> Enum.take(limit)
          |> Enum.with_index(offset + 1)
          |> Enum.map(fn {line, num} -> "#{num}\t#{line}" end)
          |> Enum.join("\n")

        {:ok, lines}

      {:error, :enoent} ->
        {:error, "File not found: #{path}"}

      {:error, reason} ->
        {:error, "Failed to read #{path}: #{reason}"}
    end
  end

  defp resolve_path("/" <> _ = absolute, _context), do: absolute
  defp resolve_path(relative, %{cwd: cwd}), do: Path.join(cwd, relative)
  defp resolve_path(relative, _), do: Path.expand(relative)
end
