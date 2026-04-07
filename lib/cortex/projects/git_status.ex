defmodule Cortex.Projects.GitStatus do
  @moduledoc """
  Quick git status checks for projects.
  """

  def check(path) do
    with true <- File.dir?(Path.join(path, ".git")),
         {status, 0} <-
           System.cmd("git", ["status", "--porcelain", "-b"],
             cd: path,
             stderr_to_stdout: true
           ) do
      lines = String.split(status, "\n", trim: true)
      branch = parse_branch(hd(lines))
      changes = length(lines) - 1
      %{branch: branch, changes: changes, dirty: changes > 0}
    else
      _ -> %{branch: nil, changes: 0, dirty: false}
    end
  end

  defp parse_branch("## " <> rest) do
    rest |> String.split("...") |> hd() |> String.trim()
  end

  defp parse_branch(_), do: "unknown"
end
