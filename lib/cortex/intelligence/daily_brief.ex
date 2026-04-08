defmodule Cortex.Intelligence.DailyBrief do
  @moduledoc """
  Generates a daily action brief by reading Josh's memory files,
  scanning git repos, and checking pipeline state.
  Returns structured recommendations for what to build/ship/sell today.
  """

  alias Cortex.Repo

  alias Cortex.Intelligence.{
    BriefCompletion,
    CompactionAdvisor,
    CrashPredictor,
    EnergyCycle,
    FlowCalibrator,
    FlowHistory,
    FlowPredictor,
    ProjectMatcher,
    SessionDNA
  }

  import Ecto.Query

  @home System.user_home!()
  @pipeline_path Path.join([@home, ".claude", "memory", "sales-pipeline.md"])
  @recent_memory_path Path.join([@home, ".claude", "memory", "recent-memory.md"])
  @priorities_path Path.join([@home, "CLAUDE.md"])

  defstruct [
    :generated_at,
    :greeting,
    :money_moves,
    :build_tasks,
    :pipeline_actions,
    :warnings,
    :quick_wins,
    :energy_phase,
    :energy_level,
    :energy_suggestion,
    :today_recap,
    :flow_calibration_status,
    :flow_prediction,
    :crash_prediction,
    :project_suggestion,
    :compaction_advice
  ]

  @doc """
  Generate today's brief. Call once on dashboard load.
  """
  def generate do
    # Cleanup old resume points on brief generation
    spawn(fn -> Cortex.Intelligence.ResumePoint.cleanup() end)

    priorities = parse_priorities()
    pipeline = parse_pipeline()
    recent = parse_recent_memory()
    repo_signals = scan_repos()
    energy = EnergyCycle.state()

    greeting = energy_greeting(energy.phase)

    %__MODULE__{
      generated_at: DateTime.utc_now(),
      greeting: greeting,
      money_moves: build_money_moves(pipeline, recent),
      build_tasks: build_tasks(repo_signals, priorities),
      pipeline_actions: build_pipeline_actions(pipeline),
      warnings: build_warnings(repo_signals, pipeline),
      quick_wins: build_quick_wins(recent, repo_signals),
      energy_phase: energy.phase,
      energy_level: energy.level,
      energy_suggestion: energy.suggestion,
      today_recap: build_today_recap(),
      flow_calibration_status: safe_calibration_status(),
      flow_prediction: safe_flow_prediction(),
      crash_prediction: safe_crash_prediction(),
      project_suggestion: safe_project_suggestion(),
      compaction_advice: safe_compaction_advice()
    }
  end

  defp energy_greeting(:mud) do
    "Mud hours. Light work only — pipeline, planning, email drafts."
  end

  defp energy_greeting(:rising) do
    "Brain warming up. Pick up where you left off — check resume points."
  end

  defp energy_greeting(:peak) do
    "Peak hours. Ship the hardest thing on this list."
  end

  defp energy_greeting(:winding_down) do
    "Winding down. Finish what's open, leave hooks for tomorrow."
  end

  defp energy_greeting(:rest) do
    "Late. Sleep compounds gains — or one more focused sprint."
  end

  # --- Today Recap: evidence of what you shipped ---

  defp build_today_recap do
    flow_stats = FlowHistory.today_stats()
    dna_summary = SessionDNA.today_summary()

    %{
      flow_sessions: flow_stats.sessions,
      flow_minutes: flow_stats.total_minutes,
      longest_flow_minutes: flow_stats.longest_minutes,
      peak_velocity: flow_stats.peak_velocity,
      total_sessions: dna_summary.total_sessions,
      activity_breakdown: dna_summary.activity_breakdown,
      primary_activity: dna_summary.primary_activity
    }
  rescue
    _ ->
      %{
        flow_sessions: 0,
        flow_minutes: 0,
        longest_flow_minutes: 0,
        peak_velocity: 0,
        total_sessions: 0,
        activity_breakdown: %{},
        primary_activity: :idle
      }
  end

  defp safe_calibration_status do
    FlowCalibrator.status()
  rescue
    _ -> %{sessions_recorded: 0, sessions_needed: 10, ready: false, progress: 0}
  end

  # --- Money Moves: things that directly generate revenue ---

  defp build_money_moves(pipeline, recent) do
    moves = []

    # Unsent drafts
    draft_count = count_drafts(pipeline)

    moves =
      if draft_count > 0 do
        moves ++ [%{action: "Send #{draft_count} pipeline emails", type: :send, priority: :high}]
      else
        moves
      end

    # Warm leads needing follow-up
    warm = find_warm_leads(pipeline)

    moves =
      Enum.reduce(warm, moves, fn lead, acc ->
        acc ++ [%{action: "Follow up: #{lead}", type: :follow_up, priority: :high}]
      end)

    # Upwork
    moves =
      if has_recent_task?(recent, "upwork") do
        moves
      else
        moves ++
          [%{action: "Run /upwork-sniper — fresh jobs waiting", type: :hunt, priority: :medium}]
      end

    moves
  end

  # --- Build Tasks: SaaS products that need work ---

  defp build_tasks(repo_signals, _priorities) do
    repo_signals
    |> Enum.filter(fn {_name, signal} -> signal.action != nil end)
    |> Enum.sort_by(fn {_name, signal} -> -signal.score end)
    |> Enum.take(5)
    |> Enum.map(fn {name, signal} ->
      %{
        project: name,
        action: signal.action,
        score: signal.score,
        dirty: signal.dirty
      }
    end)
  end

  # --- Pipeline Actions ---

  defp build_pipeline_actions(pipeline) do
    actions = []

    # Demo Done leads
    demo_done = find_stage_leads(pipeline, "Demo Done")

    actions =
      Enum.reduce(demo_done, actions, fn lead, acc ->
        acc ++ [%{action: "Close #{lead} — demo already done", urgency: :critical}]
      end)

    # Stale contacts (>7 days)
    stale = find_stale_leads(pipeline)

    actions =
      Enum.reduce(stale, actions, fn lead, acc ->
        acc ++ [%{action: "#{lead} going cold — re-engage now", urgency: :high}]
      end)

    actions
  end

  # --- Warnings ---

  defp build_warnings(repo_signals, _pipeline) do
    warnings = []

    # Dirty repos
    dirty_repos =
      repo_signals
      |> Enum.filter(fn {_name, s} -> s.dirty > 0 end)
      |> Enum.map(fn {name, s} -> "#{name}: #{s.dirty} uncommitted files" end)

    warnings = if dirty_repos != [], do: warnings ++ dirty_repos, else: warnings

    warnings
  end

  # --- Quick Wins: <5 min tasks ---

  defp build_quick_wins(recent, _repo_signals) do
    wins = []

    # Check for Gmail auth pending
    token_path = Path.join([@home, ".claude", "mcp-servers", "gmail-send", "token.json"])

    wins =
      if not File.exists?(token_path) do
        wins ++ ["Auth Gmail Send MCP — run: node auth.js"]
      else
        wins
      end

    # Check for todos in recent memory
    todos = extract_todos(recent)
    wins = wins ++ Enum.take(todos, 3)

    wins
  end

  # --- Parsers ---

  defp parse_pipeline do
    case File.read(@pipeline_path) do
      {:ok, content} -> content
      _ -> ""
    end
  end

  defp parse_recent_memory do
    case File.read(@recent_memory_path) do
      {:ok, content} -> content
      _ -> ""
    end
  end

  defp parse_priorities do
    case File.read(@priorities_path) do
      {:ok, content} -> content
      _ -> ""
    end
  end

  defp count_drafts(pipeline) do
    pipeline
    |> String.split("\n")
    |> Enum.count(fn line ->
      String.contains?(line, "Drafted") and String.contains?(line, "draft")
    end)
  end

  defp find_warm_leads(pipeline) do
    pipeline
    |> String.split("\n")
    |> Enum.filter(fn line ->
      String.contains?(line, "Demo Done") or String.contains?(line, "Call Back")
    end)
    |> Enum.map(fn line ->
      line
      |> String.split("|")
      |> Enum.at(1, "")
      |> String.trim()
    end)
    |> Enum.reject(&(&1 == ""))
  end

  defp find_stage_leads(pipeline, stage) do
    pipeline
    |> String.split("\n")
    |> Enum.filter(&String.contains?(&1, stage))
    |> Enum.map(fn line ->
      line |> String.split("|") |> Enum.at(1, "") |> String.trim()
    end)
    |> Enum.reject(&(&1 == "" or &1 == "Firm"))
  end

  defp find_stale_leads(pipeline) do
    pipeline
    |> String.split("\n")
    |> Enum.filter(fn line ->
      String.contains?(line, "Contacted") and String.contains?(line, "2026-03")
    end)
    |> Enum.map(fn line ->
      line |> String.split("|") |> Enum.at(1, "") |> String.trim()
    end)
    |> Enum.reject(&(&1 == "" or &1 == "Firm"))
  end

  defp has_recent_task?(recent, keyword) do
    String.contains?(String.downcase(recent), keyword)
  end

  defp extract_todos(recent) do
    recent
    |> String.split("\n")
    |> Enum.filter(&String.starts_with?(String.trim(&1), "- [ ]"))
    |> Enum.map(fn line ->
      line |> String.trim() |> String.replace_prefix("- [ ] ", "")
    end)
    |> Enum.take(5)
  end

  defp scan_repos do
    # Names must match ~/CLAUDE.md project table exactly
    project_dirs = [
      {"Hemp Route CRM", Path.join(@home, "hemp-route")},
      {"FuelOps", Path.join(@home, "fuel-ops")},
      {"VapeOps", Path.join(@home, "vape-ops")},
      {"Litigation Juris", Path.join(@home, "roan-pi-platform")},
      {"SiteScout", Path.join(@home, "site_scout")},
      {"AlphaSwarm", Path.join(@home, "alphaswarm")},
      {"Cortex", Path.join(@home, "cortex")},
      {"GreekLedger", Path.join(@home, "greekledger")},
      {"VerdictAds", Path.join(@home, "verdict-ads")},
      {"Servicewright", Path.join(@home, "servicewright")}
    ]

    project_dirs
    |> Task.async_stream(
      fn {name, path} ->
        {name, scan_repo(path)}
      end,
      timeout: 5_000,
      max_concurrency: 10
    )
    |> Enum.map(fn {:ok, result} -> result end)
  end

  defp scan_repo(path) do
    dirty = repo_dirty_count(path)
    {days, last_msg} = repo_last_commit(path)

    action =
      cond do
        dirty > 5 -> "#{dirty} uncommitted files — commit or stash"
        dirty > 0 -> "#{dirty} uncommitted changes"
        days != nil and days > 7 -> "Stale #{days}d — needs work or archive"
        days != nil and days > 3 -> "#{days}d since last touch"
        true -> nil
      end

    score =
      cond do
        dirty > 5 -> 80
        dirty > 0 -> 50
        days != nil and days > 7 -> 30
        true -> 10
      end

    %{dirty: dirty, days_since: days, last_msg: last_msg, action: action, score: score}
  end

  defp repo_dirty_count(path) do
    case System.cmd("git", ["status", "--porcelain"], cd: path, stderr_to_stdout: true) do
      {output, 0} ->
        output |> String.trim() |> String.split("\n", trim: true) |> length()

      _ ->
        0
    end
  end

  defp repo_last_commit(path) do
    case System.cmd("git", ["log", "-1", "--format=%aI|%s"], cd: path, stderr_to_stdout: true) do
      {output, 0} ->
        case output |> String.trim() |> String.split("|", parts: 2) do
          [iso, msg] ->
            case DateTime.from_iso8601(iso) do
              {:ok, dt, _} -> {Date.diff(Date.utc_today(), DateTime.to_date(dt)), msg}
              _ -> {nil, nil}
            end

          _ ->
            {nil, nil}
        end

      _ ->
        {nil, nil}
    end
  end

  # --- Completion tracking ---

  @doc "Hash an action string for dedup."
  def action_hash(action) when is_binary(action) do
    :crypto.hash(:md5, action) |> Base.encode16(case: :lower) |> binary_part(0, 12)
  end

  @doc "Mark an action as completed for today."
  def mark_completed(action, section) do
    today = Date.utc_today()
    hash = action_hash(action)

    %BriefCompletion{}
    |> BriefCompletion.changeset(%{date: today, action_hash: hash, section: section})
    |> Repo.insert(on_conflict: :nothing)
  end

  defp safe_flow_prediction do
    FlowPredictor.brief_prediction()
  rescue
    _ -> nil
  end

  defp safe_crash_prediction do
    CrashPredictor.brief_line()
  rescue
    _ -> nil
  end

  defp safe_project_suggestion do
    ProjectMatcher.suggestion()
  rescue
    _ -> nil
  end

  defp safe_compaction_advice do
    CompactionAdvisor.brief_line()
  rescue
    _ -> nil
  end

  @doc "Get all completed action hashes for today."
  def completed_today do
    today = Date.utc_today()

    from(c in BriefCompletion, where: c.date == ^today, select: c.action_hash)
    |> Repo.all()
    |> MapSet.new()
  end
end
