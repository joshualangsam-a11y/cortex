defmodule Cortex.Intelligence.IntentCompression do
  @moduledoc """
  Intent Compression: measures the BEM Compressed Intent ratio.

  From the Bandwidth Expanders paper:
  "Compressed Intent: spatial/kinesthetic thoughts → code at 100:1 ratio"

  This module measures that ratio in real-time. For every Claude session,
  it tracks:
  - User input volume (characters typed)
  - Useful output volume (code lines, file changes)
  - The compression ratio: how much output per unit of input

  Key insight: neurodivergent brains often think in spatial/kinesthetic
  modes that compress poorly into natural language but decompress perfectly
  through AI. A 5-word prompt that produces 500 lines of correct code
  is a 100:1 compression ratio.

  This module proves that ratio exists, measures it, and helps you
  optimize for it. "Your terse sessions produce 3x more code" is not
  a motivational quote — it's measured data.

  The compression ratio IS the moat metric. No NT-designed tool measures this.
  """

  alias Cortex.Intelligence.TokenEconomics

  @doc """
  Calculate compression metrics for the current aggregate state.

  Returns %{
    overall_ratio: float,        # code_lines per 1000 input chars
    efficiency_pct: float,       # signal / (signal + entropy) * 100
    total_code_lines: integer,
    total_input_chars: integer,
    total_entropy: integer,
    session_count: integer,
    insight: String.t() | nil
  }
  """
  def metrics do
    agg = safe_aggregate()

    ratio =
      if agg.total_input_chars > 0 do
        Float.round(agg.total_code_lines / agg.total_input_chars * 1000, 1)
      else
        0.0
      end

    %{
      overall_ratio: ratio,
      efficiency_pct: agg.avg_efficiency,
      total_code_lines: agg.total_code_lines,
      total_input_chars: agg.total_input_chars,
      total_entropy: agg.total_entropy,
      session_count: agg.total_sessions,
      insight: generate_insight(ratio, agg)
    }
  end

  @doc """
  Get the compression ratio as a human-readable string.
  """
  def ratio_label do
    m = metrics()

    cond do
      m.overall_ratio >= 50 ->
        "#{m.overall_ratio} — exceptional compression. Pure intent → code."

      m.overall_ratio >= 20 ->
        "#{m.overall_ratio} — strong compression. Terse prompts, high output."

      m.overall_ratio >= 5 ->
        "#{m.overall_ratio} — moderate. Could tighten prompts."

      m.overall_ratio > 0 ->
        "#{m.overall_ratio} — low. Try shorter, more direct prompts."

      true ->
        "No data yet."
    end
  end

  @doc """
  Compare two sessions' compression ratios.
  Used for A/B insights between terse and verbose sessions.
  """
  def compare(session_a_id, session_b_id) do
    a = TokenEconomics.session_stats(session_a_id)
    b = TokenEconomics.session_stats(session_b_id)

    case {a, b} do
      {nil, _} ->
        nil

      {_, nil} ->
        nil

      _ ->
        ratio_a = compression_for(a)
        ratio_b = compression_for(b)

        diff = if ratio_b > 0, do: round((ratio_a / ratio_b - 1) * 100), else: 0

        %{
          session_a: %{ratio: ratio_a, input: a.input_chars, output: a.code_lines},
          session_b: %{ratio: ratio_b, input: b.input_chars, output: b.code_lines},
          difference_pct: diff,
          winner: if(ratio_a > ratio_b, do: session_a_id, else: session_b_id)
        }
    end
  end

  @doc """
  Generate a work pattern insight about compression.
  Used by WorkPatterns module.
  """
  def pattern_insight do
    m = metrics()

    cond do
      m.session_count < 2 ->
        nil

      m.overall_ratio >= 30 ->
        %{
          insight: "Compression ratio #{m.overall_ratio}x — your prompts are highly efficient",
          evidence: "#{m.total_code_lines} code lines from #{m.total_input_chars} input chars",
          suggestion: "This is the BEM effect. Keep prompts terse, let the AI expand.",
          confidence: 0.8
        }

      m.efficiency_pct < 40 and m.total_entropy > 5 ->
        %{
          insight: "Token efficiency at #{m.efficiency_pct}% — #{m.total_entropy} entropy events",
          evidence: "#{m.total_code_lines} code lines but #{m.total_entropy} errors/retries",
          suggestion: "High entropy. Try: single focused task, compact earlier, shorter prompts.",
          confidence: 0.7
        }

      m.overall_ratio < 10 and m.total_input_chars > 500 ->
        %{
          insight: "Compression ratio #{m.overall_ratio}x — prompts may be too verbose",
          evidence:
            "#{m.total_input_chars} input chars producing #{m.total_code_lines} code lines",
          suggestion:
            "Try compressed intent: 5 words that trigger 500 lines. 'fix the test' > 'can you please look at the failing test and fix it'.",
          confidence: 0.6
        }

      true ->
        nil
    end
  end

  # Internal

  defp generate_insight(ratio, agg) do
    cond do
      agg.total_sessions == 0 ->
        nil

      ratio >= 50 ->
        "Pure compressed intent. Your brain → AI bridge is operating at peak bandwidth."

      ratio >= 20 and agg.avg_efficiency >= 70 ->
        "Strong signal-to-noise. High compression + low entropy = optimal token economics."

      ratio < 10 and agg.total_entropy > agg.total_code_lines ->
        "Entropy exceeding signal. The context window is accumulating noise faster than value."

      agg.avg_efficiency < 40 ->
        "Efficiency below 40%. Most token spend is going to retries and errors."

      true ->
        nil
    end
  end

  defp compression_for(%{input_chars: 0}), do: 0.0

  defp compression_for(%{code_lines: lines, input_chars: input}) do
    Float.round(lines / input * 1000, 1)
  end

  defp safe_aggregate do
    TokenEconomics.aggregate()
  rescue
    _ ->
      %{
        total_sessions: 0,
        total_input_chars: 0,
        total_output_chars: 0,
        total_code_lines: 0,
        total_entropy: 0,
        avg_compression: 0.0,
        avg_efficiency: 0.0,
        best_session: nil,
        active_sessions: 0
      }
  end
end
