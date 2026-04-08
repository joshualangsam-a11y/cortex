defmodule Cortex.Intelligence.EnergyCycle do
  @moduledoc """
  Energy cycle awareness for neurodivergent brains.

  Knows that cognitive performance varies by time of day. Josh's brain:
  - Morning (6-11 AM): Mud brain. Low processing power.
  - Afternoon/Evening (11 AM - 9 PM): Rising to peak. Build window.
  - Night (9 PM - 2 AM): Peak. Deep work, flow states, the 145-systems energy.
  - Late night (2-6 AM): Diminishing. Wrap up, leave Zeigarnik hooks.

  Uses this to:
  1. Adjust daily brief tone and task suggestions
  2. Sort tasks by energy requirement vs current capacity
  3. Warn when attempting high-energy tasks during mud hours
  4. Correlate with MomentumEngine data over time
  """

  alias Cortex.NDProfile

  @type phase :: :mud | :rising | :peak | :winding_down | :rest
  @type energy_level :: 1..10

  @doc "Get the current energy phase based on local time + ND profile."
  @spec current_phase() :: phase()
  def current_phase do
    profile = NDProfile.current()
    hour = local_hour()
    phase_for_hour(hour, profile)
  end

  @doc "Get the current energy level (1-10) based on local time."
  @spec current_level() :: energy_level()
  def current_level do
    profile = NDProfile.current()
    hour = local_hour()
    level_for_hour(hour, profile)
  end

  @doc "Get a full energy state map."
  def state do
    profile = NDProfile.current()
    hour = local_hour()
    phase = phase_for_hour(hour, profile)

    %{
      phase: phase,
      level: level_for_hour(hour, profile),
      hour: hour,
      suggestion: suggestion_for_phase(phase),
      peak_starts_in: hours_until_peak(hour, profile),
      deep_work_ok: deep_work_ok?(hour, profile)
    }
  end

  @doc "Should this task be deferred to peak hours?"
  def defer?(task_type) when task_type in [:architecture, :complex_debug, :new_feature] do
    current_phase() == :mud
  end

  def defer?(_task_type), do: false

  @doc "Sort tasks by energy-appropriateness for current phase."
  def sort_by_energy(tasks) do
    phase = current_phase()

    Enum.sort_by(tasks, fn task ->
      energy_cost = Map.get(task, :energy_cost, :medium)
      task_priority(phase, energy_cost)
    end)
  end

  # Phase detection — uses NDProfile hour boundaries

  defp phase_for_hour(hour, profile) do
    mud_s = profile.mud_start
    mud_e = profile.mud_end
    peak_s = profile.peak_start
    peak_e = profile.peak_end

    cond do
      in_range?(hour, mud_s, mud_e) -> :mud
      in_range?(hour, mud_e, peak_s) -> :rising
      in_range?(hour, peak_s, peak_e) -> :peak
      in_range?(hour, peak_e, peak_e + 2) -> :winding_down
      true -> :rest
    end
  end

  defp in_range?(hour, start_h, end_h) when start_h <= end_h do
    hour >= start_h and hour < end_h
  end

  defp in_range?(hour, start_h, end_h) do
    # Wraps midnight (e.g. peak 22-2)
    hour >= start_h or hour < end_h
  end

  defp level_for_hour(hour, profile) do
    phase = phase_for_hour(hour, profile)

    case phase do
      :mud ->
        if hour < profile.mud_start + 2, do: 2, else: 4

      :rising ->
        6

      :peak ->
        mid = div(profile.peak_start + profile.peak_end, 2)
        if hour >= mid, do: 10, else: 8

      :winding_down ->
        6

      :rest ->
        2
    end
  end

  defp deep_work_ok?(hour, profile) do
    phase = phase_for_hour(hour, profile)
    phase in [:rising, :peak]
  end

  defp hours_until_peak(hour, profile) do
    if hour >= profile.peak_start and hour < profile.peak_end do
      0
    else
      rem(profile.peak_start - hour + 24, 24)
    end
  end

  defp suggestion_for_phase(:mud) do
    "Mud hours. Pipeline review, email drafts, planning, light admin."
  end

  defp suggestion_for_phase(:rising) do
    "Rising. Good for continuing yesterday's work — check resume points."
  end

  defp suggestion_for_phase(:peak) do
    "Peak hours. Ship features, solve hard bugs, deep architecture."
  end

  defp suggestion_for_phase(:winding_down) do
    "Winding down. Finish what's open, leave tasks 90% done for tomorrow."
  end

  defp suggestion_for_phase(:rest) do
    "Rest window. Sleep compounds gains. Seriously."
  end

  # Task sorting by energy match

  defp task_priority(:mud, :low), do: 0
  defp task_priority(:mud, :medium), do: 1
  defp task_priority(:mud, :high), do: 2
  defp task_priority(:peak, :high), do: 0
  defp task_priority(:peak, :medium), do: 1
  defp task_priority(:peak, :low), do: 2
  defp task_priority(:rising, :medium), do: 0
  defp task_priority(:rising, :high), do: 1
  defp task_priority(:rising, :low), do: 1
  defp task_priority(_, _), do: 1

  defp local_hour do
    DateTime.utc_now()
    |> DateTime.add(-4 * 3600)
    |> Map.get(:hour)
  end
end
