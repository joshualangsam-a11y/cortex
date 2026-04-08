defmodule Cortex.Intelligence.ThermalThrottle do
  @moduledoc """
  Thermal Throttle Detection: knows when you're hitting the wall.

  From Josh's brain map:
  - "Wall = headache. Brain overheating, not quitting."
  - "Flow interrupts accumulate as headaches — context-switching tax under parallel load"

  Detects cognitive overload by correlating:
  1. Error rate spiking (OutputMonitor patterns)
  2. Velocity dropping (MomentumEngine)
  3. Context-switching frequency (rapid session focus changes)
  4. Session duration (diminishing returns after extended periods)

  When the signal crosses threshold, broadcasts a throttle warning:
  not "you should stop" but "your brain is overheating — 5 min break
  or switch to a lighter task will let it cool down."

  This is hormesis-aware: occasional thermal events are growth.
  Sustained ones are diminishing returns.
  """

  use GenServer
  require Logger

  alias Cortex.NDProfile

  @check_interval_ms 30_000
  @error_window_ms 120_000
  @throttle_cooldown_ms 600_000
  @topic "intelligence:throttle"

  # Context switch threshold is fixed — profile controls error + marathon thresholds
  @context_switch_threshold 8

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, [], name: __MODULE__)
  end

  def topic, do: @topic

  @doc "Get current thermal state."
  def state do
    GenServer.call(__MODULE__, :state)
  end

  @doc "Record an error event."
  def record_error(session_id) do
    GenServer.cast(__MODULE__, {:error, session_id, System.monotonic_time(:millisecond)})
  end

  @doc "Record a context switch (session focus change)."
  def record_context_switch do
    GenServer.cast(__MODULE__, {:context_switch, System.monotonic_time(:millisecond)})
  end

  # GenServer

  @impl true
  def init(_opts) do
    Phoenix.PubSub.subscribe(Cortex.PubSub, "terminal:notifications")
    Phoenix.PubSub.subscribe(Cortex.PubSub, Cortex.Intelligence.MomentumEngine.topic())

    schedule_check()

    {:ok,
     %{
       errors: [],
       context_switches: [],
       thermal_state: :normal,
       last_throttle_at: nil,
       session_start: System.monotonic_time(:millisecond),
       velocity_trend: [],
       current_velocity: 0
     }}
  end

  @impl true
  def handle_cast({:error, _session_id, timestamp}, state) do
    errors = [timestamp | state.errors]
    {:noreply, %{state | errors: errors}}
  end

  def handle_cast({:context_switch, timestamp}, state) do
    switches = [timestamp | state.context_switches]
    {:noreply, %{state | context_switches: switches}}
  end

  @impl true
  def handle_call(:state, _from, state) do
    {:reply,
     %{
       thermal_state: state.thermal_state,
       recent_errors: count_recent(state.errors),
       recent_switches: count_recent(state.context_switches),
       session_hours: session_hours(state),
       velocity: state.current_velocity
     }, state}
  end

  @impl true
  def handle_info({:terminal_notification, _id, %{severity: :error}}, state) do
    now = System.monotonic_time(:millisecond)
    {:noreply, %{state | errors: [now | state.errors]}}
  end

  def handle_info({:momentum_changed, _flow_state, velocity}, state) do
    trend =
      [{velocity, System.monotonic_time(:millisecond)} | state.velocity_trend] |> Enum.take(30)

    {:noreply, %{state | current_velocity: velocity, velocity_trend: trend}}
  end

  def handle_info(:check_thermal, state) do
    now = System.monotonic_time(:millisecond)
    state = prune_old_events(state, now)

    signals = calculate_signals(state, now)
    new_thermal = evaluate_thermal(signals, state)

    state =
      if new_thermal != state.thermal_state do
        handle_thermal_change(state, new_thermal, signals)
      else
        state
      end

    schedule_check()
    {:noreply, state}
  end

  def handle_info(_msg, state), do: {:noreply, state}

  # Signal calculation

  defp calculate_signals(state, now) do
    profile = NDProfile.current()
    error_threshold = profile.error_spike_threshold
    marathon_threshold = profile.marathon_hours_threshold

    error_count = count_recent(state.errors)
    switch_count = count_recent(state.context_switches)
    hours = session_hours(state)
    velocity_dropping = velocity_declining?(state.velocity_trend)

    %{
      error_spike: error_count >= error_threshold,
      context_thrashing: switch_count >= @context_switch_threshold,
      marathon_session: hours >= marathon_threshold,
      velocity_dropping: velocity_dropping,
      error_count: error_count,
      switch_count: switch_count,
      hours: hours,
      # Combined score: how many warning signals are active
      heat_score:
        Enum.count(
          [
            error_count >= error_threshold,
            switch_count >= @context_switch_threshold,
            hours >= marathon_threshold,
            velocity_dropping
          ],
          & &1
        ),
      can_throttle: can_throttle?(state, now)
    }
  end

  defp evaluate_thermal(signals, _state) do
    cond do
      # 3+ signals = definite throttle
      signals.heat_score >= 3 and signals.can_throttle -> :overheating
      # Error spike + velocity drop = hitting the wall
      signals.error_spike and signals.velocity_dropping and signals.can_throttle -> :overheating
      # 2 signals = warming
      signals.heat_score >= 2 -> :warming
      # 1 signal = normal but noted
      signals.heat_score >= 1 -> :elevated
      true -> :normal
    end
  end

  defp handle_thermal_change(state, :overheating, signals) do
    now = System.monotonic_time(:millisecond)

    Logger.info(
      "ThermalThrottle: OVERHEATING detected " <>
        "(errors: #{signals.error_count}, switches: #{signals.switch_count}, " <>
        "hours: #{Float.round(signals.hours, 1)}, velocity_dropping: #{signals.velocity_dropping})"
    )

    suggestion = throttle_suggestion(signals)

    Phoenix.PubSub.broadcast(
      Cortex.PubSub,
      @topic,
      {:thermal_throttle, :overheating, suggestion}
    )

    %{state | thermal_state: :overheating, last_throttle_at: now}
  end

  defp handle_thermal_change(state, :warming, _signals) do
    Phoenix.PubSub.broadcast(
      Cortex.PubSub,
      @topic,
      {:thermal_throttle, :warming, nil}
    )

    %{state | thermal_state: :warming}
  end

  defp handle_thermal_change(state, new_state, _signals) do
    if state.thermal_state in [:overheating, :warming] do
      Phoenix.PubSub.broadcast(
        Cortex.PubSub,
        @topic,
        {:thermal_throttle, :normal, nil}
      )
    end

    %{state | thermal_state: new_state}
  end

  defp throttle_suggestion(signals) do
    cond do
      signals.error_spike and signals.velocity_dropping ->
        "You're hitting a wall — errors up, speed down. 5-min break or switch to a lighter task."

      signals.context_thrashing ->
        "Context-switching tax building up. Pick ONE session and go deep."

      signals.marathon_session ->
        "#{Float.round(signals.hours, 1)} hours straight. A 10-min break will compound, not cost."

      true ->
        "Brain overheating — not quitting, just thermal throttling. Brief pause then attack."
    end
  end

  # Helpers

  defp count_recent(events) do
    cutoff = System.monotonic_time(:millisecond) - @error_window_ms
    Enum.count(events, &(&1 > cutoff))
  end

  defp prune_old_events(state, now) do
    cutoff = now - @error_window_ms

    %{
      state
      | errors: Enum.filter(state.errors, &(&1 > cutoff)),
        context_switches: Enum.filter(state.context_switches, &(&1 > cutoff))
    }
  end

  defp session_hours(state) do
    (System.monotonic_time(:millisecond) - state.session_start) / 3_600_000
  end

  defp can_throttle?(state, now) do
    case state.last_throttle_at do
      nil -> true
      last -> now - last > @throttle_cooldown_ms
    end
  end

  defp velocity_declining?(trend) when length(trend) < 5, do: false

  defp velocity_declining?(trend) do
    recent = trend |> Enum.take(5) |> Enum.map(&elem(&1, 0))
    older = trend |> Enum.drop(5) |> Enum.take(5) |> Enum.map(&elem(&1, 0))

    case {recent, older} do
      {r, o} when r != [] and o != [] ->
        avg_recent = Enum.sum(r) / length(r)
        avg_older = Enum.sum(o) / length(o)
        # Velocity dropped by more than 50%
        avg_older > 0 and avg_recent / avg_older < 0.5

      _ ->
        false
    end
  end

  defp schedule_check do
    Process.send_after(self(), :check_thermal, @check_interval_ms)
  end
end
