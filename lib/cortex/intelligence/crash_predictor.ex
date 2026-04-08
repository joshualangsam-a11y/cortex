defmodule Cortex.Intelligence.CrashPredictor do
  @moduledoc """
  Crash Predictor: anticipates cognitive wall before it hits.

  From signal processing: the derivative of a signal predicts where
  it's going. If error rate is accelerating, velocity is decelerating,
  and session duration is approaching your historical crash point —
  the wall is coming in ~15 minutes.

  This is the difference between:
  - Reactive: "You're overheating" (too late, already in headache)
  - Predictive: "Based on your pattern, you'll hit the wall in 15min.
    Take a 5-min break NOW and extend your session by an hour."

  Uses:
  1. ThermalThrottle signal trends (not just current state)
  2. Historical crash durations from FlowHistory
  3. EntropyDetector trend (rising entropy = approaching crash)
  4. Time-of-day patterns (you crash at 1AM more than 4PM)
  5. NDProfile marathon threshold as baseline

  Hormesis-aware: occasional pushing past predicted crash = growth.
  Repeated crashes without breaks = diminishing returns.
  """

  alias Cortex.Intelligence.{
    EnergyCycle,
    EntropyDetector,
    FlowHistory,
    ThermalThrottle
  }

  alias Cortex.NDProfile
  alias Cortex.Repo
  import Ecto.Query

  @doc """
  Predict if and when a crash is likely.

  Returns %{
    crash_likely: boolean,
    minutes_until: integer | nil,
    confidence: float,
    signals: [String.t()],
    suggestion: String.t(),
    severity: :none | :low | :medium | :high
  }
  """
  def predict do
    thermal = safe_thermal()
    entropy = safe_entropy()
    profile = NDProfile.current()
    energy = EnergyCycle.state()
    session_hours = thermal.session_hours
    historical = historical_crash_duration()

    signals = []
    risk_score = 0

    # Signal 1: Session duration approaching historical crash point
    {signals, risk_score} =
      if historical > 0 do
        remaining_ratio = session_hours / historical

        cond do
          remaining_ratio >= 0.9 ->
            {["Session at #{pct(remaining_ratio)} of your typical crash duration" | signals],
             risk_score + 4}

          remaining_ratio >= 0.7 ->
            {["Session at #{pct(remaining_ratio)} of typical crash point" | signals],
             risk_score + 2}

          remaining_ratio >= 0.5 ->
            {["Halfway to typical crash duration" | signals], risk_score + 1}

          true ->
            {signals, risk_score}
        end
      else
        # No historical data, use profile threshold
        if session_hours >= profile.marathon_hours_threshold * 0.75 do
          {["Approaching marathon threshold (#{profile.marathon_hours_threshold}h)" | signals],
           risk_score + 2}
        else
          {signals, risk_score}
        end
      end

    # Signal 2: Thermal state trend
    {signals, risk_score} =
      case thermal.thermal_state do
        :warming ->
          {["Thermal warming — trajectory points to overheating" | signals], risk_score + 3}

        :elevated ->
          {["Thermal elevated — early warning" | signals], risk_score + 1}

        :overheating ->
          {["Already overheating" | signals], risk_score + 5}

        _ ->
          {signals, risk_score}
      end

    # Signal 3: Entropy rising
    {signals, risk_score} =
      case entropy do
        :high ->
          {["Session entropy high — cognitive noise accumulating" | signals], risk_score + 3}

        :medium ->
          {["Entropy building — approaching noise threshold" | signals], risk_score + 1}

        _ ->
          {signals, risk_score}
      end

    # Signal 4: Error rate + velocity combination
    {signals, risk_score} =
      if thermal.recent_errors >= 3 and thermal.velocity < 5 do
        {["Errors up + velocity down — classic pre-crash pattern" | signals], risk_score + 3}
      else
        {signals, risk_score}
      end

    # Signal 5: Energy phase (crashing during mud hours is worse)
    {signals, risk_score} =
      case energy.phase do
        :mud ->
          {["Mud hours amplify crash risk" | signals], risk_score + 1}

        :winding_down ->
          {["Winding down phase — natural stopping point approaching" | signals], risk_score + 1}

        _ ->
          {signals, risk_score}
      end

    # Calculate prediction
    severity = severity_from_score(risk_score)
    crash_likely = risk_score >= 4
    minutes_until = estimate_minutes_until(risk_score, session_hours, historical, profile)
    confidence = prediction_confidence(signals, historical)

    %{
      crash_likely: crash_likely,
      minutes_until: minutes_until,
      confidence: confidence,
      signals: signals,
      suggestion: build_suggestion(severity, minutes_until, energy),
      severity: severity
    }
  end

  @doc """
  Quick check for dashboard header indicator.
  Returns :safe | :watch | :warning | :imminent
  """
  def status do
    prediction = predict()

    case prediction.severity do
      :high -> :imminent
      :medium -> :warning
      :low -> :watch
      :none -> :safe
    end
  end

  @doc """
  One-liner for the daily brief.
  """
  def brief_line do
    prediction = predict()

    case prediction.severity do
      :none -> nil
      :low -> nil
      :medium -> "Crash risk building. #{prediction.suggestion}"
      :high -> "Crash imminent. #{prediction.suggestion}"
    end
  end

  # Estimation

  defp estimate_minutes_until(risk_score, session_hours, historical, profile) do
    cond do
      risk_score >= 8 ->
        5

      risk_score >= 6 ->
        15

      risk_score >= 4 ->
        if historical > 0 do
          remaining_hours = max(0, historical - session_hours)
          round(remaining_hours * 60)
        else
          remaining = max(0, profile.marathon_hours_threshold - session_hours)
          round(remaining * 60)
        end

      true ->
        nil
    end
  end

  defp severity_from_score(score) do
    cond do
      score >= 7 -> :high
      score >= 4 -> :medium
      score >= 2 -> :low
      true -> :none
    end
  end

  defp prediction_confidence(signals, historical) do
    base = if historical > 0, do: 0.4, else: 0.2
    signal_boost = min(0.5, length(signals) * 0.1)
    min(1.0, Float.round(base + signal_boost, 2))
  end

  defp build_suggestion(severity, minutes_until, energy) do
    case severity do
      :high ->
        if minutes_until && minutes_until <= 10 do
          "Take a 5-minute break NOW. Walk away from the screen. This extends your total session."
        else
          "Wall approaching. Save your state, leave a Zeigarnik hook, take a break."
        end

      :medium ->
        case energy.phase do
          :winding_down ->
            "Natural wind-down approaching. Finish current task, leave hooks for tomorrow."

          :mud ->
            "Mud hours + rising signals. Switch to light admin or take a break."

          _ ->
            minutes_str = if minutes_until, do: " (~#{minutes_until}min)", else: ""

            "Crash risk building#{minutes_str}. Consider a 5-min break to reset — " <>
              "it extends output, not reduces it."
        end

      _ ->
        "All clear."
    end
  end

  # Historical analysis

  defp historical_crash_duration do
    # Find the average session duration before flow breaks
    # (sessions that ended naturally, not ones that kept going)
    four_weeks_ago = DateTime.add(DateTime.utc_now(), -28, :day)

    durations =
      FlowHistory
      |> where([f], f.started_at >= ^four_weeks_ago and not is_nil(f.duration_seconds))
      |> where([f], f.duration_seconds > 300)
      |> select([f], f.duration_seconds)
      |> Repo.all()

    if length(durations) >= 5 do
      # Use 85th percentile as "typical crash duration"
      sorted = Enum.sort(durations)
      p85_idx = round(length(sorted) * 0.85)
      crash_seconds = Enum.at(sorted, min(p85_idx, length(sorted) - 1))
      crash_seconds / 3600
    else
      0
    end
  rescue
    _ -> 0
  end

  # Safe loaders

  defp safe_thermal do
    ThermalThrottle.state()
  rescue
    _ ->
      %{
        thermal_state: :normal,
        recent_errors: 0,
        recent_switches: 0,
        session_hours: 0,
        velocity: 0
      }
  end

  defp safe_entropy do
    case EntropyDetector.state() do
      %{highest: %{entropy_level: level}} -> level
      _ -> :none
    end
  rescue
    _ -> :none
  end

  defp pct(ratio), do: "#{round(ratio * 100)}%"
end
