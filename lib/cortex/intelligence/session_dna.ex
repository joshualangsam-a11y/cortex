defmodule Cortex.Intelligence.SessionDNA do
  @moduledoc """
  Session DNA: activity fingerprint for every terminal session.

  Tracks what happened in each session — builds, tests, deploys, errors,
  flow states, idle time — and accumulates it into a fingerprint. This lets
  Cortex show you HOW you work, not just WHAT you did.

  Used for:
  - "Today you spent 3h building, 45m debugging, 20m deploying"
  - Identifying patterns (always debug after deploy? always test before commit?)
  - Optimizing burst mode configs based on actual usage
  - The weekly review: evidence of what you shipped

  Listens to OutputMonitor notifications and MomentumEngine state changes
  to build the DNA in real-time.
  """

  use GenServer
  require Logger

  @flush_interval_ms 30_000

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, [], name: __MODULE__)
  end

  @doc "Get the DNA for a specific session."
  def get(session_id) do
    GenServer.call(__MODULE__, {:get, session_id})
  end

  @doc "Get DNA for all active sessions."
  def all do
    GenServer.call(__MODULE__, :all)
  end

  @doc "Get a summary of today's activity across all sessions."
  def today_summary do
    GenServer.call(__MODULE__, :today_summary)
  end

  @doc "Record an activity event for a session."
  def record(session_id, activity_type) do
    GenServer.cast(__MODULE__, {:record, session_id, activity_type})
  end

  @doc "Mark a session as ended and finalize its DNA."
  def finalize(session_id) do
    GenServer.cast(__MODULE__, {:finalize, session_id})
  end

  # GenServer

  @impl true
  def init(_opts) do
    Phoenix.PubSub.subscribe(Cortex.PubSub, "terminal:sessions")
    Phoenix.PubSub.subscribe(Cortex.PubSub, "terminal:notifications")
    Phoenix.PubSub.subscribe(Cortex.PubSub, Cortex.Intelligence.MomentumEngine.topic())

    schedule_flush()

    {:ok,
     %{
       # %{session_id => %{activities: MapSet, timeline: [], started_at: DateTime}}
       sessions: %{},
       # Finalized session summaries for today
       completed: []
     }}
  end

  @impl true
  def handle_cast({:record, session_id, activity_type}, state) do
    state = ensure_session(state, session_id)

    sessions =
      Map.update!(state.sessions, session_id, fn session ->
        %{
          session
          | activities: MapSet.put(session.activities, activity_type),
            timeline: [{activity_type, DateTime.utc_now()} | session.timeline],
            counts: Map.update(session.counts, activity_type, 1, &(&1 + 1))
        }
      end)

    {:noreply, %{state | sessions: sessions}}
  end

  def handle_cast({:finalize, session_id}, state) do
    case Map.get(state.sessions, session_id) do
      nil ->
        {:noreply, state}

      session ->
        summary = build_summary(session_id, session)
        completed = [summary | state.completed]
        sessions = Map.delete(state.sessions, session_id)
        {:noreply, %{state | sessions: sessions, completed: completed}}
    end
  end

  @impl true
  def handle_call({:get, session_id}, _from, state) do
    dna = Map.get(state.sessions, session_id)
    {:reply, dna, state}
  end

  def handle_call(:all, _from, state) do
    {:reply, state.sessions, state}
  end

  def handle_call(:today_summary, _from, state) do
    # Merge active + completed
    active_summaries =
      Enum.map(state.sessions, fn {id, session} -> build_summary(id, session) end)

    all_summaries = active_summaries ++ state.completed

    summary = %{
      total_sessions: length(all_summaries),
      activity_breakdown: merge_counts(all_summaries),
      primary_activity: primary_activity(all_summaries),
      total_events: all_summaries |> Enum.map(& &1.total_events) |> Enum.sum()
    }

    {:reply, summary, state}
  end

  # PubSub handlers — auto-record from existing systems

  @impl true
  def handle_info({:session_started, id, _info}, state) do
    {:noreply, ensure_session(state, id)}
  end

  def handle_info({:session_exited, id, _reason}, state) do
    case Map.get(state.sessions, id) do
      nil ->
        {:noreply, state}

      session ->
        summary = build_summary(id, session)
        completed = [summary | state.completed]
        sessions = Map.delete(state.sessions, id)
        {:noreply, %{state | sessions: sessions, completed: completed}}
    end
  end

  def handle_info({:terminal_notification, session_id, notification}, state) do
    activity_type = notification_to_activity(notification.type)
    state = ensure_session(state, session_id)

    sessions =
      Map.update!(state.sessions, session_id, fn session ->
        %{
          session
          | activities: MapSet.put(session.activities, activity_type),
            timeline: [{activity_type, DateTime.utc_now()} | session.timeline],
            counts: Map.update(session.counts, activity_type, 1, &(&1 + 1))
        }
      end)

    {:noreply, %{state | sessions: sessions}}
  end

  def handle_info({:momentum_changed, :flowing, _velocity}, state) do
    # Mark all active sessions as having experienced flow
    sessions =
      Enum.reduce(state.sessions, state.sessions, fn {id, session}, acc ->
        Map.put(acc, id, %{
          session
          | activities: MapSet.put(session.activities, :flow),
            counts: Map.update(session.counts, :flow, 1, &(&1 + 1))
        })
      end)

    {:noreply, %{state | sessions: sessions}}
  end

  def handle_info(:flush, state) do
    # Prune completed sessions older than today
    today = Date.utc_today()

    completed =
      Enum.filter(state.completed, fn summary ->
        Date.compare(DateTime.to_date(summary.ended_at || summary.started_at), today) != :lt
      end)

    schedule_flush()
    {:noreply, %{state | completed: completed}}
  end

  def handle_info(_msg, state), do: {:noreply, state}

  # Internal

  defp ensure_session(state, session_id) do
    if Map.has_key?(state.sessions, session_id) do
      state
    else
      session = %{
        activities: MapSet.new(),
        timeline: [],
        counts: %{},
        started_at: DateTime.utc_now()
      }

      %{state | sessions: Map.put(state.sessions, session_id, session)}
    end
  end

  defp build_summary(session_id, session) do
    duration =
      DateTime.diff(DateTime.utc_now(), session.started_at, :second)

    %{
      session_id: session_id,
      activities: MapSet.to_list(session.activities),
      counts: session.counts,
      total_events: session.timeline |> length(),
      duration_seconds: duration,
      started_at: session.started_at,
      ended_at: DateTime.utc_now(),
      primary: primary_single(session.counts)
    }
  end

  defp notification_to_activity(:build_error), do: :debug
  defp notification_to_activity(:test_failure), do: :test
  defp notification_to_activity(:test_success), do: :test
  defp notification_to_activity(:deploy_success), do: :deploy
  defp notification_to_activity(:deploy_failure), do: :deploy
  defp notification_to_activity(:server_started), do: :build
  defp notification_to_activity(:claude_output), do: :agent
  defp notification_to_activity(:git_conflict), do: :git
  defp notification_to_activity(:git_update), do: :git
  defp notification_to_activity(:git_status), do: :git
  defp notification_to_activity(_), do: :other

  defp primary_single(counts) when map_size(counts) == 0, do: :idle

  defp primary_single(counts) do
    counts
    |> Enum.max_by(fn {_type, count} -> count end)
    |> elem(0)
  end

  defp primary_activity([]), do: :idle

  defp primary_activity(summaries) do
    summaries
    |> Enum.flat_map(fn s -> Map.to_list(s.counts) end)
    |> Enum.reduce(%{}, fn {type, count}, acc ->
      Map.update(acc, type, count, &(&1 + count))
    end)
    |> Enum.max_by(fn {_type, count} -> count end, fn -> {:idle, 0} end)
    |> elem(0)
  end

  defp merge_counts(summaries) do
    summaries
    |> Enum.flat_map(fn s -> Map.to_list(s.counts) end)
    |> Enum.reduce(%{}, fn {type, count}, acc ->
      Map.update(acc, type, count, &(&1 + count))
    end)
  end

  defp schedule_flush do
    Process.send_after(self(), :flush, @flush_interval_ms)
  end
end
