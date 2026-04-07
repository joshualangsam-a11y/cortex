defmodule Cortex.Projects.Scanner do
  @moduledoc """
  Scans filesystem for git repositories to suggest as projects.
  """

  @doc """
  Walk directories up to max_depth from base_path.
  Returns list of %{name: dir_name, path: full_path, type: detected_type}
  Only includes dirs that have .git/
  """
  def scan(base_path \\ System.user_home!(), max_depth \\ 2) do
    base_path
    |> walk(0, max_depth)
    |> Enum.sort_by(& &1.name)
  end

  @doc """
  Detect project type from filesystem markers.
  """
  def detect_type(path) do
    cond do
      File.exists?(Path.join(path, "mix.exs")) -> "elixir"
      File.exists?(Path.join(path, "package.json")) -> "node"
      File.exists?(Path.join(path, "Cargo.toml")) -> "rust"
      File.exists?(Path.join(path, "pyproject.toml")) -> "python"
      File.exists?(Path.join(path, "go.mod")) -> "go"
      true -> "other"
    end
  end

  @doc """
  Suggest a dev command based on project type.
  """
  def suggest_dev_command("elixir"), do: "mix phx.server"
  def suggest_dev_command("node"), do: "npm run dev"
  def suggest_dev_command("python"), do: "python -m uvicorn main:app --reload"
  def suggest_dev_command("rust"), do: "cargo run"
  def suggest_dev_command("go"), do: "go run ."
  def suggest_dev_command(_), do: nil

  # -- Private

  defp walk(_path, depth, max_depth) when depth > max_depth, do: []

  defp walk(path, depth, max_depth) do
    git_path = Path.join(path, ".git")

    if File.dir?(git_path) do
      [%{name: Path.basename(path), path: path, type: detect_type(path)}]
    else
      path
      |> list_dirs()
      |> Enum.flat_map(fn child -> walk(child, depth + 1, max_depth) end)
    end
  end

  defp list_dirs(path) do
    case File.ls(path) do
      {:ok, entries} ->
        entries
        |> Enum.reject(&String.starts_with?(&1, "."))
        |> Enum.map(&Path.join(path, &1))
        |> Enum.filter(&File.dir?/1)

      {:error, _} ->
        []
    end
  end
end
