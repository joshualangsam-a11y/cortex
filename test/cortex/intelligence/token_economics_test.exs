defmodule Cortex.Intelligence.TokenEconomicsTest do
  use Cortex.DataCase, async: false

  alias Cortex.Intelligence.TokenEconomics

  # TokenEconomics is started by the application supervision tree
  # State accumulates across tests, so use unique session IDs and relative assertions

  describe "record_input/2" do
    test "tracks input characters for a session" do
      id = Ecto.UUID.generate()
      TokenEconomics.record_input(id, 100)
      TokenEconomics.record_input(id, 50)

      stats = TokenEconomics.session_stats(id)
      assert stats.input_chars == 150
      assert stats.input_count == 2
    end
  end

  describe "record_output/3" do
    test "tracks output characters and code lines" do
      id = Ecto.UUID.generate()
      TokenEconomics.record_output(id, 5000, 50)
      TokenEconomics.record_output(id, 3000, 30)

      stats = TokenEconomics.session_stats(id)
      assert stats.output_chars == 8000
      assert stats.code_lines == 80
    end
  end

  describe "record_entropy/2" do
    test "tracks entropy events by type" do
      id = Ecto.UUID.generate()
      TokenEconomics.record_entropy(id, :error)
      TokenEconomics.record_entropy(id, :error)
      TokenEconomics.record_entropy(id, :retry)

      stats = TokenEconomics.session_stats(id)
      assert stats.entropy_events == 3
      assert stats.entropy_types == %{error: 2, retry: 1}
    end
  end

  describe "compression_ratio/1" do
    test "calculates code lines per 1000 input chars" do
      id = Ecto.UUID.generate()
      TokenEconomics.record_input(id, 1000)
      TokenEconomics.record_output(id, 5000, 50)

      ratio = TokenEconomics.compression_ratio(id)
      assert ratio == 50.0
    end

    test "returns 0 for unknown session" do
      assert TokenEconomics.compression_ratio("nope-#{System.unique_integer()}") == 0.0
    end
  end

  describe "aggregate/0" do
    test "includes all active sessions" do
      agg = TokenEconomics.aggregate()
      assert agg.active_sessions >= 0
      assert is_integer(agg.total_input_chars)
      assert is_integer(agg.total_code_lines)
    end
  end

  describe "session_stats/1" do
    test "returns nil for unknown session" do
      assert TokenEconomics.session_stats("unknown-#{System.unique_integer()}") == nil
    end

    test "returns stats with all fields" do
      id = Ecto.UUID.generate()
      TokenEconomics.record_input(id, 100)
      stats = TokenEconomics.session_stats(id)

      assert stats.session_id == id
      assert stats.input_chars == 100
      assert stats.output_chars == 0
      assert stats.code_lines == 0
      assert stats.entropy_events == 0
      assert %DateTime{} = stats.started_at
    end
  end
end
