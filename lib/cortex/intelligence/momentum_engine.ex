defmodule Cortex.Intelligence.MomentumEngine do
  @moduledoc """
  Tracks input velocity across terminal sessions and detects flow state.

  Neurodivergent-native: parallel-processing brains enter flow when sustained
  input happens across multiple sessions. This engine detects that state and
  broadcasts it so the UI can protect momentum (suppress non-critical toasts,
  show velocity indicator, guard against interruptions).

  Flow detection algorithm:
  - Tracks keystrokes per session with timestamps
  - Calculates rolling velocity (keystrokes per 10-second window)
  - Flow state triggers when velocity stays above threshold for sustained period
  - Flow breaks when velocity drops below threshold for cooldown period
  """

  use GenServer
  require Logger

  alias Cortex.Intelligence.{FlowCalibrator, FlowHistory}
  alias Cortex.NDProfile

  @velocity_window_ms 10_000
  @tick_interval_ms 2_000

  @topic "momentum:state"

  # Public API

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, [], name: __MODULE__)
  end

  def topic, do: @topic

  @doc "Record a keystroke event from a session."
  def record_input(session_id) do
    GenServer.cast(__MODULE__, {:input, session_id, System.monotonic_time(:millisecond)})
  end

  @doc "Get current momentum state."
  def state do
    GenServer.call(__MODULE__, :state)
  end

  @doc "Get current velocity (keystrokes per window)."
  def velocity do
    GenServer.call(__MODULE__, :velocity)
  end

  # GenServer callbacks

  @impl true
  def init(_opts) do
    schedule_tick()

    {:ok,
     %{
       # %{session_id => [timestamp, ...]}
       inputs: %{},
       flow_state: :idle,
       # When velocity first exceeded threshold
       flow_entered_at: nil,
       # When velocity last dropped below threshold
       flow_dropped_at: nil,
       current_velocity: 0,
       peak_velocity: 0,
       # Total flow time this session (ms)
       total_flow_ms: 0,
       flow_start: nil
     }}
  end

  @impl true
  def handle_cast({:input, session_id, timestamp}, state) do
    inputs =
      Map.update(state.inputs, session_id, [timestamp], fn timestamps ->
        [timestamp | timestamps]
      end)

    {:noreply, %{state | inputs: inputs}}
  end

  @impl true
  def handle_call(:state, _from, state) do
    {:reply,
     %{
       flow_state: state.flow_state,
       velocity: state.current_velocity,
       peak_velocity: state.peak_velocity,
       active_sessions: count_active_sessions(state),
       total_flow_ms: state.total_flow_ms
     }, state}
  end

  def handle_call(:velocity, _from, state) do
    {:reply, state.current_velocity, state}
  end

  @impl true
  def handle_info(:tick, state) do
    now = System.monotonic_time(:millisecond)
    cutoff = now - @velocity_window_ms

    # Prune old timestamps and calculate velocity
    {inputs, velocity} = calculate_velocity(state.inputs, cutoff)

    peak = max(state.peak_velocity, velocity)
    state = %{state | inputs: inputs, current_velocity: velocity, peak_velocity: peak}

    # State machine for flow detection
    state = update_flow_state(state, velocity, now)

    schedule_tick()
    {:noreply, state}
  end

  def handle_info(_msg, state), do: {:noreply, state}

  # Internal

  defp calculate_velocity(inputs, cutoff) do
    Enum.reduce(inputs, {%{}, 0}, fn {session_id, timestamps}, {acc_inputs, acc_count} ->
      recent = Enum.filter(timestamps, &(&1 > cutoff))

      case recent do
        [] -> {acc_inputs, acc_count}
        ts -> {Map.put(acc_inputs, session_id, ts), acc_count + length(ts)}
      end
    end)
  end

  defp count_active_sessions(state) do
    now = System.monotonic_time(:millisecond)
    cutoff = now - @velocity_window_ms

    state.inputs
    |> Enum.count(fn {_id, timestamps} ->
      Enum.any?(timestamps, &(&1 > cutoff))
    end)
  end

  defp update_flow_state(state, velocity, now) do
    profile = NDProfile.current()
    threshold = profile.flow_velocity_threshold

    case {state.flow_state, velocity >= threshold} do
      # Idle, velocity rising -> start tracking
      {:idle, true} ->
        entered = state.flow_entered_at || now

        %{state | flow_entered_at: entered, flow_dropped_at: nil}
        |> maybe_enter_flow(now, profile)

      # Idle, still low -> stay idle
      {:idle, false} ->
        %{state | flow_entered_at: nil, flow_dropped_at: nil}

      # In flow, velocity still high -> maintain
      {:flowing, true} ->
        %{state | flow_dropped_at: nil}

      # In flow, velocity dropped -> start cooldown
      {:flowing, false} ->
        dropped = state.flow_dropped_at || now

        %{state | flow_dropped_at: dropped}
        |> maybe_exit_flow(now, profile)
    end
  end

  defp maybe_enter_flow(%{flow_state: :idle, flow_entered_at: entered} = state, now, profile) do
    sustain_ms = profile.flow_sustain_seconds * 1000

    if is_integer(entered) and now - entered >= sustain_ms do
      Logger.info("MomentumEngine: flow state ENTERED (velocity: #{state.current_velocity})")
      broadcast_flow_change(:flowing, state.current_velocity)

      # Record in FlowHistory for streak tracking
      spawn(fn ->
        FlowHistory.start_flow(state.peak_velocity, count_active_sessions(state))
      end)

      %{state | flow_state: :flowing, flow_start: now}
    else
      state
    end
  end

  defp maybe_exit_flow(%{flow_state: :flowing, flow_dropped_at: dropped} = state, now, profile) do
    cooldown_ms = profile.flow_cooldown_seconds * 1000

    if is_integer(dropped) and now - dropped >= cooldown_ms do
      flow_duration = if state.flow_start, do: now - state.flow_start, else: 0

      Logger.info(
        "MomentumEngine: flow state EXITED (duration: #{div(flow_duration, 1000)}s, peak: #{state.peak_velocity})"
      )

      broadcast_flow_change(:idle, state.current_velocity)

      # Record end in FlowHistory
      spawn(fn ->
        FlowHistory.end_flow(state.peak_velocity)

        # Auto-calibrate after accumulating enough flow data
        status = FlowCalibrator.status()

        if status.ready and rem(status.sessions_recorded, 5) == 0 do
          FlowCalibrator.calibrate_and_apply()
        end
      end)

      %{
        state
        | flow_state: :idle,
          flow_entered_at: nil,
          flow_dropped_at: nil,
          flow_start: nil,
          total_flow_ms: state.total_flow_ms + flow_duration
      }
    else
      state
    end
  end

  defp broadcast_flow_change(new_state, velocity) do
    Phoenix.PubSub.broadcast(
      Cortex.PubSub,
      @topic,
      {:momentum_changed, new_state, velocity}
    )
  end

  defp schedule_tick do
    Process.send_after(self(), :tick, @tick_interval_ms)
  end
end
