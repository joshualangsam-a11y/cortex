defmodule Cortex.Intelligence.FlowCalibrator do
  @moduledoc """
  Adaptive flow threshold learning.

  The MomentumEngine starts with a default velocity threshold (15) from the
  NDProfile. Over time, FlowCalibrator observes ACTUAL flow patterns and
  learns the user's personal flow entry velocity.

  After 10+ completed flow sessions, it calculates:
  - Personal flow velocity (the velocity at which flow typically starts)
  - Optimal sustain time (how long to wait before confirming flow)
  - Average flow duration (for the thermal throttle marathon detection)

  This data can optionally write back to the NDProfile, creating a
  self-calibrating system. The more you use Cortex, the better it
  understands your brain.

  "The system that learns from itself — the compound loop."
  """

  alias Cortex.Intelligence.FlowHistory
  alias Cortex.NDProfile
  alias Cortex.Repo

  @min_sessions_for_calibration 10

  @doc """
  Analyze flow history and return calibrated thresholds.

  Returns nil if not enough data (< 10 sessions).
  """
  def calibrate do
    sessions = completed_sessions()

    if length(sessions) < @min_sessions_for_calibration do
      nil
    else
      analyze(sessions)
    end
  end

  @doc """
  Calibrate and write results back to the user's NDProfile.

  Only updates if calibration produces valid results and the values
  differ meaningfully from current profile.
  """
  def calibrate_and_apply do
    case calibrate() do
      nil ->
        {:ok, :insufficient_data}

      calibration ->
        profile = NDProfile.current()
        apply_calibration(profile, calibration)
    end
  end

  @doc "Get calibration status — how close to having enough data."
  def status do
    count = completed_session_count()

    %{
      sessions_recorded: count,
      sessions_needed: @min_sessions_for_calibration,
      ready: count >= @min_sessions_for_calibration,
      progress: min(100, round(count / @min_sessions_for_calibration * 100))
    }
  end

  # Analysis

  defp analyze(sessions) do
    velocities = Enum.map(sessions, & &1.peak_velocity) |> Enum.filter(&(&1 > 0))
    durations = Enum.map(sessions, & &1.duration_seconds) |> Enum.filter(&(&1 > 0))

    if velocities == [] or durations == [] do
      nil
    else
      # Use the 25th percentile of peak velocities as the flow threshold
      # This captures the "entry point" — the minimum velocity that correlates with flow
      sorted_v = Enum.sort(velocities)
      p25_idx = max(0, div(length(sorted_v), 4))
      optimal_threshold = Enum.at(sorted_v, p25_idx)

      # Average duration helps calibrate marathon detection
      avg_duration_min = Enum.sum(durations) / length(durations) / 60

      # Median duration for sustain time calibration
      sorted_d = Enum.sort(durations)
      median_duration = Enum.at(sorted_d, div(length(sorted_d), 2))

      # Sustain time: 20% of median flow duration, clamped to 15-120 seconds
      optimal_sustain = (median_duration * 0.2) |> round() |> max(15) |> min(120)

      %{
        recommended_velocity_threshold: optimal_threshold,
        recommended_sustain_seconds: optimal_sustain,
        avg_flow_duration_minutes: Float.round(avg_duration_min, 1),
        median_flow_duration_seconds: median_duration,
        sessions_analyzed: length(sessions),
        peak_velocity_range: {Enum.min(velocities), Enum.max(velocities)},
        confidence: confidence_score(length(sessions))
      }
    end
  end

  defp apply_calibration(profile, calibration) do
    # Only apply if confidence is high enough and values differ meaningfully
    if calibration.confidence < 0.6 do
      {:ok, :low_confidence}
    else
      changes = %{}

      changes =
        if abs(calibration.recommended_velocity_threshold - profile.flow_velocity_threshold) >= 3 do
          Map.put(changes, :flow_velocity_threshold, calibration.recommended_velocity_threshold)
        else
          changes
        end

      changes =
        if abs(calibration.recommended_sustain_seconds - profile.flow_sustain_seconds) >= 5 do
          Map.put(changes, :flow_sustain_seconds, calibration.recommended_sustain_seconds)
        else
          changes
        end

      if map_size(changes) > 0 do
        case Repo.get(NDProfile, profile.id) do
          nil ->
            {:ok, :no_profile}

          db_profile ->
            db_profile
            |> NDProfile.changeset(changes)
            |> Repo.update()
            |> case do
              {:ok, updated} ->
                NDProfile.reload()
                {:ok, :calibrated, updated, changes}

              error ->
                error
            end
        end
      else
        {:ok, :no_changes_needed}
      end
    end
  end

  defp confidence_score(n) when n >= 50, do: 1.0
  defp confidence_score(n) when n >= 30, do: 0.9
  defp confidence_score(n) when n >= 20, do: 0.8
  defp confidence_score(n) when n >= 10, do: 0.6
  defp confidence_score(_), do: 0.3

  defp completed_sessions do
    import Ecto.Query

    FlowHistory
    |> where([f], not is_nil(f.duration_seconds) and f.duration_seconds > 0)
    |> order_by(desc: :started_at)
    |> limit(100)
    |> Repo.all()
  end

  defp completed_session_count do
    import Ecto.Query

    FlowHistory
    |> where([f], not is_nil(f.duration_seconds) and f.duration_seconds > 0)
    |> Repo.aggregate(:count)
  rescue
    _ -> 0
  end
end
