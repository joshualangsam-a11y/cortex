defmodule Cortex.Intelligence.FlowPredictor do
  @moduledoc """
  Flow Predictor: anticipates when you'll hit flow state today.

  From Bayesian inference: P(flow | hour, day, energy) is computable
  from historical data. Given 2+ weeks of FlowHistory, this module
  builds a probability distribution of flow onset by hour and day.

  Key predictions:
  - "Your most likely flow window today is 3-5 PM (73% confidence)"
  - "Tuesdays you flow 40% more than Mondays — protect this afternoon"
  - "You haven't flowed during mud hours in 14 days — don't force it"

  The insight: knowing WHEN flow will come lets you PREPARE for it.
  Clear the calendar, queue the right project, set up the workspace.

  This is mechanism 15 (Proof-by-Construction) — the system uses its
  own data to predict its own future states.
  """

  alias Cortex.Intelligence.{EnergyCycle, FlowHistory}
  alias Cortex.Repo
  import Ecto.Query

  @doc """
  Predict today's flow windows.

  Returns %{
    windows: [%{hour_start, hour_end, probability, evidence}],
    best_window: %{hour_start, hour_end, probability},
    day_outlook: :strong | :moderate | :low,
    day_insight: String.t(),
    confidence: float
  }
  """
  def predict_today do
    history = flow_history_by_hour()
    day_history = flow_history_by_day()
    today_dow = Date.day_of_week(Date.utc_today())

    windows = build_windows(history)
    day_factor = day_strength(day_history, today_dow)
    best = best_window(windows)

    %{
      windows: windows,
      best_window: best,
      day_outlook: day_outlook(day_factor, windows),
      day_insight: day_insight(day_factor, today_dow, day_history),
      confidence: calculate_confidence(history)
    }
  end

  @doc """
  Get a single-line prediction for the daily brief.
  """
  def brief_prediction do
    prediction = predict_today()

    case prediction.best_window do
      nil ->
        if prediction.confidence < 0.3 do
          "Not enough flow data yet — keep building, predictions unlock after 10+ sessions."
        else
          "No strong flow window predicted today. Energy-match your tasks instead."
        end

      window ->
        "Flow window: #{format_hour(window.hour_start)}-#{format_hour(window.hour_end)} " <>
          "(#{round(window.probability * 100)}% likely). #{prediction.day_insight}"
    end
  end

  @doc """
  Should I start deep work now?
  Quick check against predicted windows.
  """
  def deep_work_now? do
    prediction = predict_today()
    current_hour = local_hour()

    in_window =
      Enum.any?(prediction.windows, fn w ->
        current_hour >= w.hour_start and current_hour < w.hour_end and w.probability >= 0.4
      end)

    energy = EnergyCycle.state()

    cond do
      in_window and energy.deep_work_ok ->
        {:yes, "You're in a predicted flow window AND energy supports deep work."}

      in_window ->
        {:maybe,
         "Predicted flow window, but energy is #{energy.phase}. Light tasks may be better."}

      energy.phase == :peak ->
        {:maybe, "Not a predicted window, but peak energy. Worth trying."}

      true ->
        next = next_window(prediction.windows, current_hour)

        case next do
          nil -> {:no, "No predicted flow windows remaining today."}
          w -> {:no, "Next flow window at #{format_hour(w.hour_start)}. #{flow_prep_tip()}."}
        end
    end
  end

  # Build hourly probability windows from history

  defp build_windows(history) when map_size(history) < 3, do: []

  defp build_windows(history) do
    total_days = total_days_tracked()
    if total_days < 3, do: [], else: do_build_windows(history, total_days)
  end

  defp do_build_windows(history, total_days) do
    # Group into 2-hour blocks for smoother predictions
    blocks = [
      {6, 8},
      {8, 10},
      {10, 12},
      {12, 14},
      {14, 16},
      {16, 18},
      {18, 20},
      {20, 22},
      {22, 24}
    ]

    blocks
    |> Enum.map(fn {start_h, end_h} ->
      # Count flow sessions in this block
      count =
        Enum.reduce(start_h..(end_h - 1), 0, fn h, acc ->
          acc + Map.get(history, h, 0)
        end)

      probability = min(1.0, count / max(total_days, 1))

      %{
        hour_start: start_h,
        hour_end: end_h,
        probability: Float.round(probability, 2),
        evidence: "#{count} flow sessions in #{total_days} days"
      }
    end)
    |> Enum.filter(&(&1.probability > 0.1))
    |> Enum.sort_by(& &1.probability, :desc)
  end

  defp best_window([]), do: nil
  defp best_window([best | _]), do: best

  defp next_window(windows, current_hour) do
    windows
    |> Enum.filter(&(&1.hour_start > current_hour))
    |> Enum.sort_by(& &1.hour_start)
    |> List.first()
  end

  # Day-of-week analysis

  defp day_strength(day_history, today_dow) do
    today_count = Map.get(day_history, today_dow, 0)
    all_counts = Map.values(day_history)

    if all_counts == [] do
      1.0
    else
      avg = Enum.sum(all_counts) / length(all_counts)
      if avg > 0, do: today_count / avg, else: 1.0
    end
  end

  defp day_outlook(factor, windows) do
    cond do
      factor >= 1.3 and length(windows) >= 2 -> :strong
      factor >= 0.7 or length(windows) >= 1 -> :moderate
      true -> :low
    end
  end

  defp day_insight(factor, today_dow, day_history) do
    day_name = day_name(today_dow)
    today_count = Map.get(day_history, today_dow, 0)

    cond do
      factor >= 1.5 ->
        "#{day_name}s are your strongest flow day (#{today_count} historical sessions)."

      factor >= 1.2 ->
        "#{day_name}s are above average for flow."

      factor <= 0.5 and today_count > 0 ->
        "#{day_name}s tend to be lower flow — don't force it, match energy to tasks."

      factor <= 0.5 ->
        "No historical flow on #{day_name}s yet."

      true ->
        "Average flow day for #{day_name}s."
    end
  end

  # Data loading

  defp flow_history_by_hour do
    four_weeks_ago = DateTime.add(DateTime.utc_now(), -28, :day)

    FlowHistory
    |> where([f], f.started_at >= ^four_weeks_ago and not is_nil(f.duration_seconds))
    |> select([f], f.started_at)
    |> Repo.all()
    |> Enum.reduce(%{}, fn started_at, acc ->
      # Convert to local hour (EST = UTC-4)
      hour = started_at |> DateTime.add(-4 * 3600) |> Map.get(:hour)
      Map.update(acc, hour, 1, &(&1 + 1))
    end)
  rescue
    _ -> %{}
  end

  defp flow_history_by_day do
    four_weeks_ago = DateTime.add(DateTime.utc_now(), -28, :day)

    FlowHistory
    |> where([f], f.started_at >= ^four_weeks_ago and not is_nil(f.duration_seconds))
    |> select([f], f.started_at)
    |> Repo.all()
    |> Enum.reduce(%{}, fn started_at, acc ->
      dow = Date.day_of_week(DateTime.to_date(started_at))
      Map.update(acc, dow, 1, &(&1 + 1))
    end)
  rescue
    _ -> %{}
  end

  defp total_days_tracked do
    four_weeks_ago = DateTime.add(DateTime.utc_now(), -28, :day)

    FlowHistory
    |> where([f], f.started_at >= ^four_weeks_ago and not is_nil(f.duration_seconds))
    |> select([f], fragment("COUNT(DISTINCT DATE(?))", f.started_at))
    |> Repo.one()
  rescue
    _ -> 0
  end

  defp calculate_confidence(history) do
    total = Enum.sum(Map.values(history))

    cond do
      total >= 50 -> 0.9
      total >= 20 -> 0.7
      total >= 10 -> 0.5
      total >= 5 -> 0.3
      true -> 0.1
    end
  end

  # Helpers

  defp format_hour(h) when h >= 12, do: "#{if h > 12, do: h - 12, else: h}PM"
  defp format_hour(h), do: "#{h}AM"

  defp day_name(1), do: "Monday"
  defp day_name(2), do: "Tuesday"
  defp day_name(3), do: "Wednesday"
  defp day_name(4), do: "Thursday"
  defp day_name(5), do: "Friday"
  defp day_name(6), do: "Saturday"
  defp day_name(7), do: "Sunday"

  defp flow_prep_tip do
    Enum.random([
      "Queue your workspace now",
      "Close distractions before then",
      "Set up your hardest task to attack",
      "Pre-load the project in a terminal"
    ])
  end

  defp local_hour do
    DateTime.utc_now()
    |> DateTime.add(-4 * 3600)
    |> Map.get(:hour)
  end
end
