defmodule Cortex.Intelligence.TokenEconomics do
  @moduledoc """
  Token Economics Engine: tracks cognitive spend and ROI per session.

  From thermodynamics: every token in a context window is either signal
  (useful state) or entropy (noise). This module measures which.

  From economics: marginal utility of each token decays. The first line
  of output is high-value. Line 2000 is usually zero. This module tracks
  the compression ratio — how much useful output per unit of input.

  Tracks per Claude agent session:
  - Input characters (user prompts)
  - Output characters (Claude responses)
  - Code lines produced (signal)
  - Error/retry events (entropy)
  - Compression ratio: output_code_lines / input_chars
  - Efficiency score: signal / (signal + entropy)

  This is the BEM Compressed Intent mechanism made measurable.
  """

  use GenServer
  require Logger

  @topic "intelligence:economics"
  @flush_interval_ms 30_000

  # Public API

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, [], name: __MODULE__)
  end

  def topic, do: @topic

  @doc "Record user input (prompt) for a session."
  def record_input(session_id, char_count) do
    GenServer.cast(__MODULE__, {:input, session_id, char_count})
  end

  @doc "Record Claude output for a session."
  def record_output(session_id, char_count, code_lines \\ 0) do
    GenServer.cast(__MODULE__, {:output, session_id, char_count, code_lines})
  end

  @doc "Record an entropy event (error, retry, repeated grep, etc)."
  def record_entropy(session_id, type) do
    GenServer.cast(__MODULE__, {:entropy, session_id, type})
  end

  @doc "Get economics for a specific session."
  def session_stats(session_id) do
    GenServer.call(__MODULE__, {:session, session_id})
  end

  @doc "Get aggregate economics across all active sessions."
  def aggregate do
    GenServer.call(__MODULE__, :aggregate)
  end

  @doc "Get the compression ratio for a session (code_lines / input_chars * 1000)."
  def compression_ratio(session_id) do
    case session_stats(session_id) do
      nil -> 0.0
      stats -> calculate_compression(stats)
    end
  end

  # GenServer

  @impl true
  def init(_opts) do
    Phoenix.PubSub.subscribe(Cortex.PubSub, "terminal:notifications")
    Phoenix.PubSub.subscribe(Cortex.PubSub, "terminal:sessions")
    schedule_flush()

    {:ok, %{sessions: %{}, completed: []}}
  end

  @impl true
  def handle_cast({:input, session_id, char_count}, state) do
    state = ensure_session(state, session_id)

    sessions =
      Map.update!(state.sessions, session_id, fn s ->
        %{s | input_chars: s.input_chars + char_count, input_count: s.input_count + 1}
      end)

    {:noreply, %{state | sessions: sessions}}
  end

  def handle_cast({:output, session_id, char_count, code_lines}, state) do
    state = ensure_session(state, session_id)

    sessions =
      Map.update!(state.sessions, session_id, fn s ->
        %{s | output_chars: s.output_chars + char_count, code_lines: s.code_lines + code_lines}
      end)

    {:noreply, %{state | sessions: sessions}}
  end

  def handle_cast({:entropy, session_id, type}, state) do
    state = ensure_session(state, session_id)

    sessions =
      Map.update!(state.sessions, session_id, fn s ->
        %{
          s
          | entropy_events: s.entropy_events + 1,
            entropy_types: Map.update(s.entropy_types, type, 1, &(&1 + 1))
        }
      end)

    {:noreply, %{state | sessions: sessions}}
  end

  @impl true
  def handle_call({:session, session_id}, _from, state) do
    stats = Map.get(state.sessions, session_id)
    {:reply, stats, state}
  end

  def handle_call(:aggregate, _from, state) do
    all = Map.values(state.sessions) ++ state.completed

    agg = %{
      total_sessions: length(all),
      total_input_chars: Enum.sum(Enum.map(all, & &1.input_chars)),
      total_output_chars: Enum.sum(Enum.map(all, & &1.output_chars)),
      total_code_lines: Enum.sum(Enum.map(all, & &1.code_lines)),
      total_entropy: Enum.sum(Enum.map(all, & &1.entropy_events)),
      avg_compression: avg_compression(all),
      avg_efficiency: avg_efficiency(all),
      best_session: best_session(all),
      active_sessions: map_size(state.sessions)
    }

    {:reply, agg, state}
  end

  # PubSub — auto-detect Claude sessions and track output patterns

  @impl true
  def handle_info({:terminal_notification, session_id, %{severity: :error}}, state) do
    state = ensure_session(state, session_id)

    sessions =
      Map.update!(state.sessions, session_id, fn s ->
        %{
          s
          | entropy_events: s.entropy_events + 1,
            entropy_types: Map.update(s.entropy_types, :error, 1, &(&1 + 1))
        }
      end)

    {:noreply, %{state | sessions: sessions}}
  end

  def handle_info({:session_exited, id, _reason}, state) do
    case Map.get(state.sessions, id) do
      nil ->
        {:noreply, state}

      session ->
        completed = [Map.put(session, :ended_at, DateTime.utc_now()) | state.completed]
        sessions = Map.delete(state.sessions, id)

        # Broadcast session economics on exit
        stats = Map.put(session, :ended_at, DateTime.utc_now())
        compression = calculate_compression(stats)
        efficiency = calculate_efficiency(stats)

        if stats.input_chars > 0 do
          Phoenix.PubSub.broadcast(
            Cortex.PubSub,
            @topic,
            {:session_economics, id,
             %{
               compression: compression,
               efficiency: efficiency,
               code_lines: stats.code_lines,
               input_chars: stats.input_chars,
               entropy_events: stats.entropy_events
             }}
          )
        end

        {:noreply, %{state | sessions: sessions, completed: completed}}
    end
  end

  def handle_info(:flush, state) do
    # Prune old completed sessions (keep last 24h)
    cutoff = DateTime.add(DateTime.utc_now(), -86400, :second)

    completed =
      Enum.filter(state.completed, fn s ->
        case s[:ended_at] do
          nil -> false
          dt -> DateTime.compare(dt, cutoff) == :gt
        end
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
        session_id: session_id,
        input_chars: 0,
        input_count: 0,
        output_chars: 0,
        code_lines: 0,
        entropy_events: 0,
        entropy_types: %{},
        started_at: DateTime.utc_now()
      }

      %{state | sessions: Map.put(state.sessions, session_id, session)}
    end
  end

  defp calculate_compression(%{input_chars: 0}), do: 0.0

  defp calculate_compression(%{code_lines: lines, input_chars: input}) do
    Float.round(lines / input * 1000, 1)
  end

  defp calculate_efficiency(%{code_lines: 0, entropy_events: 0}), do: 0.0

  defp calculate_efficiency(%{code_lines: signal, entropy_events: entropy}) do
    total = signal + entropy
    if total > 0, do: Float.round(signal / total * 100, 1), else: 0.0
  end

  defp avg_compression([]), do: 0.0

  defp avg_compression(sessions) do
    ratios =
      sessions
      |> Enum.map(&calculate_compression/1)
      |> Enum.filter(&(&1 > 0))

    if ratios != [], do: Float.round(Enum.sum(ratios) / length(ratios), 1), else: 0.0
  end

  defp avg_efficiency([]), do: 0.0

  defp avg_efficiency(sessions) do
    effs =
      sessions
      |> Enum.map(&calculate_efficiency/1)
      |> Enum.filter(&(&1 > 0))

    if effs != [], do: Float.round(Enum.sum(effs) / length(effs), 1), else: 0.0
  end

  defp best_session([]), do: nil

  defp best_session(sessions) do
    sessions
    |> Enum.max_by(&calculate_compression/1, fn -> nil end)
    |> case do
      nil -> nil
      s -> %{session_id: s.session_id, compression: calculate_compression(s)}
    end
  end

  defp schedule_flush do
    Process.send_after(self(), :flush, @flush_interval_ms)
  end
end
