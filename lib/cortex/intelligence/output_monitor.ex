defmodule Cortex.Intelligence.OutputMonitor do
  @moduledoc """
  GenServer that watches all terminal session output streams,
  runs pattern detection, and broadcasts notifications + status changes.

  Subscribes to PubSub for session lifecycle events and per-session output.
  Buffers the last 4KB of output per session for pattern matching.
  Tracks idle time and broadcasts idle/active status transitions.
  """

  use GenServer
  require Logger

  alias Cortex.Intelligence.{Notification, OutputPatterns}

  @max_buffer_size 4096
  @idle_check_interval :timer.seconds(10)
  @idle_threshold :timer.seconds(60)

  @sessions_topic "terminal:sessions"
  @status_topic "terminal:status"
  @notifications_topic "terminal:notifications"

  # -- Public API --

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, [], name: __MODULE__)
  end

  @doc "Get the current status of a session."
  def session_status(session_id) do
    GenServer.call(__MODULE__, {:session_status, session_id})
  end

  @doc "List all tracked sessions and their statuses."
  def all_statuses do
    GenServer.call(__MODULE__, :all_statuses)
  end

  @doc "Get recent notifications across all sessions."
  def recent_notifications(limit \\ 20) do
    GenServer.call(__MODULE__, {:recent_notifications, limit})
  end

  # -- GenServer callbacks --

  @impl true
  def init(_opts) do
    Phoenix.PubSub.subscribe(Cortex.PubSub, @sessions_topic)
    schedule_idle_check()

    {:ok,
     %{
       sessions: %{},
       notifications: []
     }}
  end

  @impl true
  def handle_info({:session_started, session_id}, state) do
    state = track_session(state, session_id)
    {:noreply, state}
  end

  def handle_info({:session_exited, session_id, _reason}, state) do
    state = untrack_session(state, session_id)
    {:noreply, state}
  end

  def handle_info({:terminal_output, session_id, data}, state) do
    state =
      state
      |> buffer_output(session_id, data)
      |> detect_patterns(session_id, data)
      |> mark_active(session_id)

    {:noreply, state}
  end

  def handle_info(:check_idle, state) do
    now = System.monotonic_time(:millisecond)

    state =
      Enum.reduce(state.sessions, state, fn {session_id, session}, acc ->
        idle_duration = now - session.last_output_at

        case {session.status, idle_duration > @idle_threshold} do
          {:active, true} ->
            broadcast_status(session_id, :idle)
            put_in(acc, [:sessions, session_id, :status], :idle)

          _ ->
            acc
        end
      end)

    schedule_idle_check()
    {:noreply, state}
  end

  def handle_info(_msg, state), do: {:noreply, state}

  @impl true
  def handle_call({:session_status, session_id}, _from, state) do
    status =
      case Map.get(state.sessions, session_id) do
        nil -> :unknown
        session -> session.status
      end

    {:reply, status, state}
  end

  def handle_call(:all_statuses, _from, state) do
    statuses =
      state.sessions
      |> Enum.map(fn {id, session} -> {id, session.status} end)
      |> Map.new()

    {:reply, statuses, state}
  end

  def handle_call({:recent_notifications, limit}, _from, state) do
    {:reply, Enum.take(state.notifications, limit), state}
  end

  # -- Internal --

  defp track_session(state, session_id) do
    Phoenix.PubSub.subscribe(Cortex.PubSub, "terminal:#{session_id}:output")

    session_data = %{
      buffer: <<>>,
      status: :active,
      last_output_at: System.monotonic_time(:millisecond)
    }

    broadcast_status(session_id, :active)
    put_in(state, [:sessions, session_id], session_data)
  end

  defp untrack_session(state, session_id) do
    Phoenix.PubSub.unsubscribe(Cortex.PubSub, "terminal:#{session_id}:output")
    broadcast_status(session_id, :exited)

    %{state | sessions: Map.delete(state.sessions, session_id)}
  end

  defp buffer_output(state, session_id, data) do
    case Map.get(state.sessions, session_id) do
      nil ->
        state

      session ->
        new_buffer =
          (session.buffer <> data)
          |> truncate_buffer()

        put_in(state, [:sessions, session_id, :buffer], new_buffer)
    end
  end

  defp truncate_buffer(buffer) when byte_size(buffer) > @max_buffer_size do
    excess = byte_size(buffer) - @max_buffer_size
    <<_discard::binary-size(excess), kept::binary>> = buffer
    kept
  end

  defp truncate_buffer(buffer), do: buffer

  defp detect_patterns(state, session_id, data) do
    case OutputPatterns.detect(data) do
      [] ->
        state

      matches ->
        Enum.reduce(matches, state, fn match, acc ->
          notification = Notification.from_match(session_id, match)
          broadcast_notification(session_id, notification)
          update_status_from_match(acc, session_id, match)
          |> prepend_notification(notification)
        end)
    end
  end

  defp mark_active(state, session_id) do
    case Map.get(state.sessions, session_id) do
      nil ->
        state

      session ->
        now = System.monotonic_time(:millisecond)

        case session.status do
          :idle ->
            broadcast_status(session_id, :active)

            state
            |> put_in([:sessions, session_id, :status], :active)
            |> put_in([:sessions, session_id, :last_output_at], now)

          _ ->
            put_in(state, [:sessions, session_id, :last_output_at], now)
        end
    end
  end

  defp update_status_from_match(state, session_id, %{type: type}) do
    new_status =
      case type do
        :build_error -> :errored
        :test_failure -> :errored
        :deploy_failure -> :errored
        :test_success -> :completed
        :deploy_success -> :completed
        :server_started -> :active
        _ -> nil
      end

    case new_status do
      nil ->
        state

      status ->
        broadcast_status(session_id, status)
        put_in(state, [:sessions, session_id, :status], status)
    end
  end

  defp prepend_notification(state, notification) do
    # Keep last 100 notifications
    notifications =
      [notification | state.notifications]
      |> Enum.take(100)

    %{state | notifications: notifications}
  end

  defp broadcast_status(session_id, status) do
    Phoenix.PubSub.broadcast(
      Cortex.PubSub,
      @status_topic,
      {:session_status_changed, session_id, status}
    )
  end

  defp broadcast_notification(session_id, notification) do
    Phoenix.PubSub.broadcast(
      Cortex.PubSub,
      @notifications_topic,
      {:terminal_notification, session_id, notification}
    )
  end

  defp schedule_idle_check do
    Process.send_after(self(), :check_idle, @idle_check_interval)
  end
end
