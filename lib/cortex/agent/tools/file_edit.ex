defmodule Cortex.Agent.Tools.FileEdit do
  @moduledoc false
  @behaviour Cortex.Agent.Tool

  @impl true
  def name, do: "file_edit"

  @impl true
  def description do
    "Replace an exact string in a file with new content. The old_string must appear exactly once in the file."
  end

  @impl true
  def parameters do
    %{
      type: "object",
      required: ["file_path", "old_string", "new_string"],
      properties: %{
        file_path: %{type: "string", description: "Absolute path to the file to edit"},
        old_string: %{type: "string", description: "The exact string to find and replace"},
        new_string: %{type: "string", description: "The replacement string"}
      }
    }
  end

  @impl true
  def execute(params, context) do
    path = resolve_path(params["file_path"], context)
    old_string = params["old_string"]
    new_string = params["new_string"]

    with {:ok, content} <- File.read(path),
         {:unique, 1} <- {:unique, count_occurrences(content, old_string)},
         new_content = String.replace(content, old_string, new_string, global: false),
         :ok <- File.write(path, new_content) do
      {:ok, "Successfully edited #{path}"}
    else
      {:error, :enoent} ->
        {:error, "File not found: #{path}"}

      {:unique, 0} ->
        {:error, "old_string not found in #{path}"}

      {:unique, n} ->
        {:error, "old_string found #{n} times in #{path} — must be unique. Add more context."}

      {:error, reason} ->
        {:error, "Failed to edit #{path}: #{inspect(reason)}"}
    end
  end

  defp count_occurrences(string, pattern) do
    string
    |> String.split(pattern)
    |> length()
    |> Kernel.-(1)
  end

  defp resolve_path("/" <> _ = absolute, _context), do: absolute
  defp resolve_path(relative, %{cwd: cwd}), do: Path.join(cwd, relative)
  defp resolve_path(relative, _), do: Path.expand(relative)
end
