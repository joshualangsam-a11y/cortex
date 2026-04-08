defmodule Cortex.Intelligence.CompactionAdvisor do
  @moduledoc """
  Compaction Advisor: optimal context management timing.

  From Shannon's Channel Capacity theorem: C = B × log₂(1 + S/N)
  You can't increase B (context window is fixed). So maximize S/N ratio.
  Compaction is the Maxwell's Demon — selectively removes entropy tokens
  while preserving signal tokens.

  Key insight from economics: marginal utility of compaction follows a
  curve. Too early = wasted effort. Too late = entropy has compounded
  and compaction quality drops. The optimal point depends on:

  1. Current estimated context usage (from session activity)
  2. Energy phase (compact during peak = extend flow window)
  3. Flow state (DON'T interrupt flow to compact)
  4. Entropy level (high entropy = compact sooner)
  5. Task complexity remaining (big task ahead = compact now)

  Returns actionable advice, not just data.
  """

  alias Cortex.Intelligence.{EnergyCycle, EntropyDetector, MomentumEngine, TokenEconomics}

  @doc """
  Generate compaction advice for current state.

  Returns %{
    should_compact: boolean,
    urgency: :low | :medium | :high | :critical,
    reason: String.t(),
    estimated_context_pct: integer,
    optimal_timing: String.t()
  }
  """
  def advise do
    context_pct = estimate_context_usage()
    energy = EnergyCycle.state()
    flow = safe_flow_state()
    entropy = safe_entropy_level()
    economics = safe_economics()

    signals = build_signals(context_pct, energy, flow, entropy, economics)
    urgency = calculate_urgency(signals)
    should_compact = should_compact?(urgency, flow)

    %{
      should_compact: should_compact,
      urgency: urgency,
      reason: build_reason(signals, urgency),
      estimated_context_pct: context_pct,
      optimal_timing: optimal_timing(energy, flow),
      signals: signals
    }
  end

  @doc """
  Quick check: should I compact now?
  Returns {true/false, reason_string}
  """
  def compact_now? do
    advice = advise()
    {advice.should_compact, advice.reason}
  end

  @doc """
  Get a one-liner for the daily brief.
  """
  def brief_line do
    advice = advise()

    case advice.urgency do
      :critical ->
        "Context critical (#{advice.estimated_context_pct}%) — compact immediately."

      :high ->
        "Context at #{advice.estimated_context_pct}% — compact soon to extend session."

      :medium ->
        "Context healthy (#{advice.estimated_context_pct}%). #{advice.optimal_timing}"

      :low ->
        nil
    end
  end

  # Signal building

  defp build_signals(context_pct, energy, flow, entropy, economics) do
    signals = []

    # Context level signals
    signals =
      cond do
        context_pct >= 80 -> [{:context_critical, 4} | signals]
        context_pct >= 60 -> [{:context_high, 2} | signals]
        context_pct >= 40 -> [{:context_moderate, 1} | signals]
        true -> signals
      end

    # Energy signals — compacting during peak extends the valuable window
    signals =
      case energy.phase do
        :peak -> [{:peak_hours, 1} | signals]
        :mud -> [{:mud_hours, -1} | signals]
        _ -> signals
      end

    # Entropy signals — high entropy means context is full of noise
    signals =
      case entropy do
        :high -> [{:high_entropy, 3} | signals]
        :medium -> [{:medium_entropy, 1} | signals]
        _ -> signals
      end

    # Economics signals — low efficiency means tokens being wasted
    signals =
      if economics.avg_efficiency > 0 and economics.avg_efficiency < 40 do
        [{:low_efficiency, 2} | signals]
      else
        signals
      end

    # Flow signals — NEVER interrupt flow
    signals =
      if flow == :flowing do
        [{:in_flow, -10} | signals]
      else
        signals
      end

    signals
  end

  defp calculate_urgency(signals) do
    score = Enum.sum(Enum.map(signals, &elem(&1, 1)))

    cond do
      score >= 6 -> :critical
      score >= 3 -> :high
      score >= 1 -> :medium
      true -> :low
    end
  end

  defp should_compact?(urgency, flow) do
    # Never interrupt flow unless critical
    case {urgency, flow} do
      {:critical, _} -> true
      {_, :flowing} -> false
      {:high, _} -> true
      {:medium, _} -> false
      {:low, _} -> false
    end
  end

  defp build_reason(signals, urgency) do
    signal_names = Enum.map(signals, &elem(&1, 0))

    parts = []

    parts =
      if :context_critical in signal_names do
        ["context near limit" | parts]
      else
        if :context_high in signal_names do
          ["context above 60%" | parts]
        else
          parts
        end
      end

    parts =
      if :high_entropy in signal_names do
        ["high session entropy" | parts]
      else
        parts
      end

    parts =
      if :peak_hours in signal_names do
        ["peak hours — compacting extends flow window" | parts]
      else
        parts
      end

    parts =
      if :low_efficiency in signal_names do
        ["token efficiency below 40%" | parts]
      else
        parts
      end

    parts =
      if :in_flow in signal_names and urgency != :critical do
        ["(holding — you're in flow)" | parts]
      else
        parts
      end

    case parts do
      [] -> "Context healthy. No action needed."
      _ -> Enum.join(parts, ". ") <> "."
    end
  end

  defp optimal_timing(energy, flow) do
    cond do
      flow == :flowing ->
        "Wait for flow break, then compact."

      energy.phase == :peak ->
        "Good time — compacting during peak extends your build window."

      energy.phase == :mud ->
        "Mud hours — low-stakes time to compact and reorganize."

      energy.phase == :winding_down ->
        "Winding down — compact and leave clean state for tomorrow."

      true ->
        "Compact when you hit a natural pause."
    end
  end

  # Safe loaders (GenServers may not be running in tests)

  defp estimate_context_usage do
    # Estimate based on session activity volume
    # Real implementation would track actual token counts from Claude API
    # For now: heuristic from event volume and session duration
    case safe_economics() do
      %{total_input_chars: input, total_output_chars: output} ->
        total = input + output
        # Rough: 4 chars per token, 200K context
        estimated_tokens = div(total, 4)
        min(round(estimated_tokens / 2000), 100)

      _ ->
        0
    end
  end

  defp safe_flow_state do
    MomentumEngine.state().flow_state
  rescue
    _ -> :idle
  end

  defp safe_entropy_level do
    case EntropyDetector.state() do
      %{highest: %{entropy_level: level}} -> level
      _ -> :none
    end
  rescue
    _ -> :none
  end

  defp safe_economics do
    TokenEconomics.aggregate()
  rescue
    _ -> %{avg_efficiency: 0.0, total_input_chars: 0, total_output_chars: 0}
  end
end
