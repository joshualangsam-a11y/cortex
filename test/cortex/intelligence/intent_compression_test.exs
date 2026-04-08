defmodule Cortex.Intelligence.IntentCompressionTest do
  use Cortex.DataCase, async: false

  alias Cortex.Intelligence.{IntentCompression, TokenEconomics}

  # TokenEconomics is started by the application supervision tree

  describe "metrics/0" do
    test "returns metrics structure" do
      m = IntentCompression.metrics()
      assert is_float(m.overall_ratio)
      assert is_float(m.efficiency_pct)
      assert is_integer(m.total_code_lines)
      assert is_integer(m.total_input_chars)
      assert is_integer(m.total_entropy)
      assert is_integer(m.session_count)
    end

    test "compression increases with high code output" do
      id = Ecto.UUID.generate()
      TokenEconomics.record_input(id, 100)
      TokenEconomics.record_output(id, 10000, 200)

      m = IntentCompression.metrics()
      assert m.overall_ratio > 0
      assert m.total_code_lines > 0
    end
  end

  describe "ratio_label/0" do
    test "returns human-readable label" do
      label = IntentCompression.ratio_label()
      assert is_binary(label)
    end
  end

  describe "pattern_insight/0" do
    test "returns nil or insight map" do
      result = IntentCompression.pattern_insight()

      if result do
        assert is_binary(result.insight)
        assert is_binary(result.evidence)
        assert is_binary(result.suggestion)
        assert result.confidence > 0
      end
    end
  end

  describe "compare/2" do
    test "returns nil for unknown sessions" do
      a = "unknown-#{System.unique_integer()}"
      b = "unknown-#{System.unique_integer()}"
      assert IntentCompression.compare(a, b) == nil
    end

    test "compares two sessions" do
      id_a = Ecto.UUID.generate()
      id_b = Ecto.UUID.generate()

      TokenEconomics.record_input(id_a, 100)
      TokenEconomics.record_output(id_a, 3000, 30)
      TokenEconomics.record_input(id_b, 500)
      TokenEconomics.record_output(id_b, 3000, 15)

      result = IntentCompression.compare(id_a, id_b)
      assert result != nil
      assert result.session_a.ratio > result.session_b.ratio
      assert result.winner == id_a
      assert result.difference_pct > 0
    end
  end
end
