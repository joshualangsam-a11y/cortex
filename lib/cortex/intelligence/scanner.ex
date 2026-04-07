defmodule Cortex.Intelligence.Scanner do
  @moduledoc """
  Scans a project directory for actionable signals:
  git status, last commit time, uncommitted changes, port liveness.
  """

  alias Cortex.Projects.Registry.Project

  defstruct [
    :project_name,
    :path,
    :status,
    :port,
    :last_commit_at,
    :last_commit_msg,
    :days_since_commit,
    :uncommitted_count,
    :has_uncommitted,
    :untracked_count,
    :is_git_repo,
    :port_alive,
    :score,
    :top_action
  ]

  @revenue_tiers %{
    "Hemp Route CRM" => 100,
    "FuelOps" => 80,
    "VapeOps" => 70,
    "Litigation Juris" => 90,
    "SiteScout" => 40,
    "AlphaSwarm" => 30,
    "Cortex" => 20,
    "Tab Commander" => 20
  }

  @doc """
  Scans a single project and returns a scored result.
  Runs git commands and port checks -- call from a Task, not inline.
  """
  def scan(%Project{} = project) do
    path = project.path

    result = %__MODULE__{
      project_name: project.name,
      path: path,
      status: project.status,
      port: project.port,
      is_git_repo: git_repo?(path)
    }

    result =
      if result.is_git_repo do
        result
        |> scan_git(path)
        |> scan_port()
        |> compute_score()
        |> compute_action()
      else
        %{result | score: 0, top_action: nil}
      end

    result
  end

  @doc """
  Scans all projects concurrently. Returns sorted by score descending.
  """
  def scan_all(projects) do
    projects
    |> Task.async_stream(&scan/1, timeout: 10_000, max_concurrency: 8)
    |> Enum.map(fn {:ok, result} -> result end)
    |> Enum.sort_by(& &1.score, :desc)
  end

  defp git_repo?(path) do
    File.dir?(Path.join(path, ".git"))
  end

  defp scan_git(result, path) do
    {uncommitted, untracked} = git_status(path)
    {last_commit_at, last_commit_msg} = git_last_commit(path)

    days_since =
      case last_commit_at do
        nil -> nil
        dt -> Date.diff(Date.utc_today(), DateTime.to_date(dt))
      end

    %{
      result
      | uncommitted_count: uncommitted,
        has_uncommitted: uncommitted > 0,
        untracked_count: untracked,
        last_commit_at: last_commit_at,
        last_commit_msg: last_commit_msg,
        days_since_commit: days_since
    }
  end

  defp scan_port(%{port: nil} = result), do: %{result | port_alive: nil}

  defp scan_port(%{port: port} = result) do
    alive =
      case :gen_tcp.connect(~c"127.0.0.1", port, [], 500) do
        {:ok, socket} ->
          :gen_tcp.close(socket)
          true

        {:error, _} ->
          false
      end

    %{result | port_alive: alive}
  end

  defp compute_score(result) do
    base = Map.get(@revenue_tiers, result.project_name, 10)

    # Boost for uncommitted work (you started something -- finish it)
    uncommitted_boost = if result.has_uncommitted, do: 40, else: 0

    # Boost for staleness on active/building projects
    staleness_boost =
      cond do
        result.status not in ["ACTIVE", "BUILDING"] -> 0
        result.days_since_commit == nil -> 0
        result.days_since_commit > 7 -> 30
        result.days_since_commit > 3 -> 15
        true -> 0
      end

    # Penalty for maintenance projects
    maintenance_penalty = if result.status == "MAINTENANCE", do: -50, else: 0

    # Boost if port should be up but isn't
    deploy_boost =
      cond do
        result.port_alive == false and result.status in ["ACTIVE", "BUILDING"] -> 25
        true -> 0
      end

    score =
      max(base + uncommitted_boost + staleness_boost + maintenance_penalty + deploy_boost, 0)

    %{result | score: score}
  end

  defp compute_action(result) do
    action =
      cond do
        result.has_uncommitted ->
          "#{result.uncommitted_count} uncommitted changes -- finish and commit"

        result.port_alive == false and result.port != nil and
            result.status in ["ACTIVE", "BUILDING"] ->
          "Port #{result.port} is down -- needs deploy/restart"

        result.days_since_commit != nil and result.days_since_commit > 7 and
            result.status == "ACTIVE" ->
          "Stale #{result.days_since_commit}d -- needs attention or move to MAINTENANCE"

        result.days_since_commit != nil and result.days_since_commit > 3 and
            result.status == "ACTIVE" ->
          "#{result.days_since_commit}d since last commit"

        true ->
          nil
      end

    %{result | top_action: action}
  end

  defp git_status(path) do
    case System.cmd("git", ["status", "--porcelain"], cd: path, stderr_to_stdout: true) do
      {output, 0} ->
        lines = output |> String.trim() |> String.split("\n", trim: true)

        uncommitted =
          Enum.count(lines, fn line ->
            prefix = String.slice(line, 0, 2)
            prefix != "??"
          end)

        untracked = Enum.count(lines, fn line -> String.starts_with?(line, "??") end)
        {uncommitted, untracked}

      _ ->
        {0, 0}
    end
  end

  defp git_last_commit(path) do
    case System.cmd("git", ["log", "-1", "--format=%aI|%s"], cd: path, stderr_to_stdout: true) do
      {output, 0} ->
        output = String.trim(output)

        case String.split(output, "|", parts: 2) do
          [iso, msg] ->
            case DateTime.from_iso8601(iso) do
              {:ok, dt, _offset} -> {dt, msg}
              _ -> {nil, nil}
            end

          _ ->
            {nil, nil}
        end

      _ ->
        {nil, nil}
    end
  end
end
