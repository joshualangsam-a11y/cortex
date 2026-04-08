defmodule Cortex.Intelligence.WorkPatterns do
  @moduledoc """
  Work Pattern Insights: learns HOW you work from correlated data.

  Correlates SessionDNA activities with energy phases, flow sessions,
  and time-of-day to generate actionable insights:

  - "Your flow sessions are 40% longer during peak hours"
  - "You debug 3x more during mud hours — consider deferring"
  - "Test-first sessions have 2x the flow rate"
  - "Your most productive day this week was Tuesday (4.2h flow)"
  - "You context-switch 60% less when using burst mode"

  These insights are the ultimate compound: the system understands
  your work patterns better than you do and surfaces the non-obvious.

  Based on brain map: "Cross-domain pattern matching — sees the system
  connecting everything" — but applied to YOUR OWN work data.
  """

  alias Cortex.Intelligence.{FlowHistory, SessionDNA}
  alias Cortex.Repo
  import Ecto.Query

  @doc """
  Generate insights from the last 7 days of data.

  Returns a list of %{insight, evidence, suggestion, confidence}
  """
  def generate do
    flow_sessions = recent_flow_sessions()
    dna_summary = SessionDNA.today_summary()

    insights = []
    insights = insights ++ flow_timing_insights(flow_sessions)
    insights = insights ++ activity_insights(dna_summary)
    insights = insights ++ streak_insights()
    insights = insights ++ volume_insights(flow_sessions)

    insights
    |> Enum.filter(& &1)
    |> Enum.sort_by(& &1.confidence, :desc)
  end

  # Flow timing: when do you flow best?

  defp flow_timing_insights(sessions) when length(sessions) < 3, do: []

  defp flow_timing_insights(sessions) do
    # Group flow sessions by time-of-day bucket
    by_phase =
      sessions
      |> Enum.group_by(fn s ->
        hour = s.started_at |> DateTime.add(-4 * 3600) |> Map.get(:hour)

        cond do
          hour >= 6 and hour < 11 -> :mud
          hour >= 11 and hour < 14 -> :rising
          hour >= 14 and hour < 22 -> :peak
          true -> :night
        end
      end)

    insights = []

    # Compare average flow duration by phase
    phase_avgs =
      Enum.map(by_phase, fn {phase, flows} ->
        durations = Enum.map(flows, & &1.duration_seconds) |> Enum.filter(&(&1 && &1 > 0))

        avg =
          if durations != [] do
            Enum.sum(durations) / length(durations)
          else
            0
          end

        {phase, avg, length(flows)}
      end)
      |> Enum.filter(fn {_, avg, _} -> avg > 0 end)

    case Enum.max_by(phase_avgs, fn {_, avg, _} -> avg end, fn -> nil end) do
      nil ->
        insights

      {best_phase, best_avg, _count} ->
        others = Enum.reject(phase_avgs, fn {p, _, _} -> p == best_phase end)

        comparison =
          if others != [] do
            other_avg =
              others
              |> Enum.map(fn {_, avg, count} -> avg * count end)
              |> Enum.sum()
              |> Kernel./(Enum.sum(Enum.map(others, fn {_, _, c} -> c end)))

            if other_avg > 0 do
              round((best_avg / other_avg - 1) * 100)
            else
              0
            end
          else
            0
          end

        if comparison > 20 do
          [
            %{
              insight: "Your flow sessions are #{comparison}% longer during #{best_phase} hours",
              evidence:
                "Based on #{length(phase_avgs)} time periods, #{Enum.sum(Enum.map(phase_avgs, fn {_, _, c} -> c end))} flow sessions",
              suggestion:
                "Schedule your hardest work during #{best_phase} hours for maximum flow",
              confidence: min(1.0, length(phase_avgs) / 3)
            }
            | insights
          ]
        else
          insights
        end
    end
  end

  # Activity insights: what patterns correlate with flow?

  defp activity_insights(dna) when map_size(dna.activity_breakdown) < 2, do: []

  defp activity_insights(dna) do
    debug_count = Map.get(dna.activity_breakdown, :debug, 0)
    test_count = Map.get(dna.activity_breakdown, :test, 0)
    build_count = Map.get(dna.activity_breakdown, :build, 0)
    flow_count = Map.get(dna.activity_breakdown, :flow, 0)

    insights = []

    # High debug ratio
    total = Enum.sum(Map.values(dna.activity_breakdown))

    insights =
      if total > 10 and debug_count / total > 0.4 do
        [
          %{
            insight: "#{round(debug_count / total * 100)}% of your events today are debugging",
            evidence: "#{debug_count} debug events out of #{total} total",
            suggestion: "Consider switching to a fresh task — debugging fatigue compounds errors",
            confidence: 0.7
          }
          | insights
        ]
      else
        insights
      end

    # Flow + test correlation
    insights =
      if flow_count > 0 and test_count > 0 do
        [
          %{
            insight: "You're hitting flow while testing — this is a strong pattern",
            evidence: "#{flow_count} flow events, #{test_count} test events in same sessions",
            suggestion:
              "Start with tests to prime the flow state — your brain responds to the feedback loop",
            confidence: 0.6
          }
          | insights
        ]
      else
        insights
      end

    # Build dominance
    insights =
      if total > 5 and build_count / max(total, 1) > 0.5 do
        [
          %{
            insight: "Build-heavy day — #{build_count} build events",
            evidence: "#{round(build_count / total * 100)}% of activity is building",
            suggestion: "You're in build mode. Protect this momentum.",
            confidence: 0.5
          }
          | insights
        ]
      else
        insights
      end

    insights
  end

  # Streak insights

  defp streak_insights do
    streak = FlowHistory.count_streak()

    cond do
      streak >= 7 ->
        [
          %{
            insight: "#{streak}-day flow streak — you're on fire",
            evidence: "Flow state achieved every day for #{streak} consecutive days",
            suggestion: "This is compounding. Don't break the chain.",
            confidence: 1.0
          }
        ]

      streak >= 3 ->
        [
          %{
            insight: "#{streak}-day flow streak building",
            evidence: "#{streak} consecutive days with flow",
            suggestion: "Momentum is building. One more day extends the streak.",
            confidence: 0.8
          }
        ]

      true ->
        []
    end
  rescue
    _ -> []
  end

  # Volume insights

  defp volume_insights(sessions) when length(sessions) < 2, do: []

  defp volume_insights(sessions) do
    today = Date.utc_today()

    today_sessions =
      Enum.filter(sessions, fn s ->
        Date.compare(DateTime.to_date(s.started_at), today) == :eq
      end)

    yesterday = Date.add(today, -1)

    yesterday_sessions =
      Enum.filter(sessions, fn s ->
        Date.compare(DateTime.to_date(s.started_at), yesterday) == :eq
      end)

    if length(today_sessions) > 0 and length(yesterday_sessions) > 0 do
      today_minutes =
        today_sessions
        |> Enum.map(& &1.duration_seconds)
        |> Enum.filter(& &1)
        |> Enum.sum()
        |> div(60)

      yesterday_minutes =
        yesterday_sessions
        |> Enum.map(& &1.duration_seconds)
        |> Enum.filter(& &1)
        |> Enum.sum()
        |> div(60)

      if yesterday_minutes > 0 do
        change = round((today_minutes / yesterday_minutes - 1) * 100)

        if abs(change) > 25 do
          [
            %{
              insight:
                if(change > 0,
                  do: "#{change}% more flow time today vs yesterday",
                  else: "#{abs(change)}% less flow time today vs yesterday"
                ),
              evidence: "Today: #{today_minutes}m, Yesterday: #{yesterday_minutes}m",
              suggestion:
                if(change > 0,
                  do: "You're accelerating. Ride it.",
                  else: "Lower output today — check if energy or environment changed"
                ),
              confidence: 0.6
            }
          ]
        else
          []
        end
      else
        []
      end
    else
      []
    end
  end

  defp recent_flow_sessions do
    week_ago = DateTime.add(DateTime.utc_now(), -7, :day)

    FlowHistory
    |> where([f], f.started_at >= ^week_ago and not is_nil(f.duration_seconds))
    |> order_by(desc: :started_at)
    |> Repo.all()
  rescue
    _ -> []
  end
end
