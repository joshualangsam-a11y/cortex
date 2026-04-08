defmodule Cortex.Intelligence.EntropyDetector do
  @moduledoc """
  Entropy Detector: identifies when Claude sessions are spinning.

  From thermodynamics: entropy increases in closed systems over time.
  A Claude Code context window IS a closed system. When entropy exceeds
  signal, the session is wasting tokens — producing heat, not work.

  Detects entropy signals:
  1. Repeated error patterns (same error 3+ times in window)
  2. Grep cycling (searching for the same thing repeatedly)
  3. Retry loops (same command re-executed without change)
  4. Explanation bloat (long output with no file writes)
  5. Read-without-progress (reading files but not editing)

  When entropy crosses threshold, broadcasts a suggestion:
  not "stop" but "try a different approach" or "compact and refocus."

  Hormesis-aware: some entropy is exploration. Sustained entropy is waste.
  """

  use GenServer
  require Logger

  alias Cortex.Intelligence.{EnergyCycle, TokenEconomics}

  @topic "intelligence:entropy"
  @check_interval_ms 15_000
  @pattern_window_ms 120_000
  @entropy_threshold 3
  @cooldown_ms 300_000

  # Public API

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, [], name: __MODULE__)
  end

  def topic, do: @topic

  @doc "Record an output event from a Claude session for pattern analysis."
  def record_event(session_id, event_type, content_hash \\ nil) do
    GenServer.cast(__MODULE__, {:event, session_id, event_type, content_hash, now_ms()})
  end

  @doc "Get current entropy state for a session."
  def session_entropy(session_id) do
    GenServer.call(__MODULE__, {:session, session_id})
  end

  @doc "Get entropy state across all sessions."
  def state do
    GenServer.call(__MODULE__, :state)
  end

  # GenServer

  @impl true
  def init(_opts) do
    Phoenix.PubSub.subscribe(Cortex.PubSub, "terminal:notifications")
    schedule_check()

    {:ok, %{sessions: %{}, last_alert_at: nil}}
  end

  @impl true
  def handle_cast({:event, session_id, event_type, content_hash, timestamp}, state) do
    state = ensure_session(state, session_id)

    sessions =
      Map.update!(state.sessions, session_id, fn s ->
        event = %{type: event_type, hash: content_hash, at: timestamp}
        %{s | events: [event | s.events]}
      end)

    {:noreply, %{state | sessions: sessions}}
  end

  @impl true
  def handle_call({:session, session_id}, _from, state) do
    case Map.get(state.sessions, session_id) do
      nil -> {:reply, %{entropy_level: :low, signals: [], score: 0}, state}
      session -> {:reply, analyze_session(session), state}
    end
  end

  def handle_call(:state, _from, state) do
    analyses =
      Enum.map(state.sessions, fn {id, session} ->
        {id, analyze_session(session)}
      end)
      |> Map.new()

    highest =
      analyses
      |> Enum.max_by(fn {_id, a} -> a.score end, fn -> {nil, %{score: 0}} end)
      |> elem(1)

    {:reply, %{sessions: analyses, highest: highest}, state}
  end

  # Auto-detect from OutputMonitor notifications

  @impl true
  def handle_info({:terminal_notification, session_id, notification}, state) do
    state = ensure_session(state, session_id)

    # Hash the message for duplicate detection
    hash = :erlang.phash2(notification.message)

    sessions =
      Map.update!(state.sessions, session_id, fn s ->
        event = %{type: notification.type, hash: hash, at: now_ms()}
        %{s | events: [event | s.events]}
      end)

    {:noreply, %{state | sessions: sessions}}
  end

  def handle_info(:check_entropy, state) do
    now = now_ms()
    state = prune_old_events(state, now)

    # Check each session for entropy
    Enum.each(state.sessions, fn {session_id, session} ->
      analysis = analyze_session(session)

      if analysis.entropy_level == :high and can_alert?(state, now) do
        suggestion = entropy_suggestion(analysis, session_id)

        Phoenix.PubSub.broadcast(
          Cortex.PubSub,
          @topic,
          {:entropy_detected, session_id, analysis.entropy_level, suggestion}
        )

        # Also record in TokenEconomics
        TokenEconomics.record_entropy(session_id, :spinning)
      end
    end)

    state =
      if Enum.any?(state.sessions, fn {_id, s} ->
           analyze_session(s).entropy_level == :high
         end) do
        %{state | last_alert_at: now}
      else
        state
      end

    schedule_check()
    {:noreply, state}
  end

  def handle_info(_msg, state), do: {:noreply, state}

  # Analysis

  defp analyze_session(session) do
    events = session.events
    signals = []
    score = 0

    # 1. Repeated errors (same hash 3+ times)
    {signals, score} = check_repeated_patterns(events, signals, score)

    # 2. Error clustering (many errors in short window)
    {signals, score} = check_error_clustering(events, signals, score)

    # 3. No-progress detection (events but no code output signals)
    {signals, score} = check_no_progress(events, signals, score)

    entropy_level =
      cond do
        score >= 6 -> :high
        score >= 3 -> :medium
        score >= 1 -> :low
        true -> :none
      end

    %{
      entropy_level: entropy_level,
      signals: signals,
      score: score,
      event_count: length(events)
    }
  end

  defp check_repeated_patterns(events, signals, score) do
    # Group by hash, find repeats
    repeats =
      events
      |> Enum.filter(& &1.hash)
      |> Enum.group_by(& &1.hash)
      |> Enum.filter(fn {_hash, evts} -> length(evts) >= @entropy_threshold end)

    if repeats != [] do
      count = length(repeats)
      {["#{count} repeated pattern(s) — same output cycling" | signals], score + count * 2}
    else
      {signals, score}
    end
  end

  defp check_error_clustering(events, signals, score) do
    error_events =
      events
      |> Enum.filter(fn e -> e.type in [:build_error, :test_failure, :error] end)

    if length(error_events) >= 5 do
      {["#{length(error_events)} errors in window — hitting a wall" | signals], score + 3}
    else
      {signals, score}
    end
  end

  defp check_no_progress(events, signals, score) do
    # Many events but no success/deploy signals = churning
    total = length(events)

    success_count =
      Enum.count(events, fn e ->
        e.type in [:test_success, :deploy_success, :server_started]
      end)

    if total >= 8 and success_count == 0 do
      {["#{total} events with 0 successes — session may be spinning" | signals], score + 2}
    else
      {signals, score}
    end
  end

  defp entropy_suggestion(analysis, _session_id) do
    energy = EnergyCycle.state()

    base =
      cond do
        Enum.any?(analysis.signals, &String.contains?(&1, "repeated")) ->
          "Same patterns cycling — try a completely different approach."

        Enum.any?(analysis.signals, &String.contains?(&1, "errors")) ->
          "Error rate spiking. Step back, re-read the error, try one focused fix."

        Enum.any?(analysis.signals, &String.contains?(&1, "spinning")) ->
          "Lots of activity, no progress. Compact context and refocus on one thing."

        true ->
          "Session entropy rising. Consider: different approach, compact, or fresh session."
      end

    # Energy-aware addendum
    case energy.phase do
      :mud -> base <> " (Mud hours — this might be an energy problem, not a code problem.)"
      :winding_down -> base <> " (Winding down — leave a Zeigarnik hook and pick up tomorrow.)"
      _ -> base
    end
  end

  # Helpers

  defp ensure_session(state, session_id) do
    if Map.has_key?(state.sessions, session_id) do
      state
    else
      %{state | sessions: Map.put(state.sessions, session_id, %{events: []})}
    end
  end

  defp prune_old_events(state, now) do
    cutoff = now - @pattern_window_ms

    sessions =
      Enum.map(state.sessions, fn {id, session} ->
        events = Enum.filter(session.events, &(&1.at > cutoff))
        {id, %{session | events: events}}
      end)
      |> Map.new()

    %{state | sessions: sessions}
  end

  defp can_alert?(state, now) do
    case state.last_alert_at do
      nil -> true
      last -> now - last > @cooldown_ms
    end
  end

  defp now_ms, do: System.monotonic_time(:millisecond)

  defp schedule_check do
    Process.send_after(self(), :check_entropy, @check_interval_ms)
  end
end
