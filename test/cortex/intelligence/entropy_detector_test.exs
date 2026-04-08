defmodule Cortex.Intelligence.EntropyDetectorTest do
  use Cortex.DataCase, async: false

  alias Cortex.Intelligence.EntropyDetector

  # EntropyDetector is started by the application supervision tree
  # Use unique session IDs to isolate test state

  describe "record_event/3" do
    test "records events for a session" do
      id = Ecto.UUID.generate()
      EntropyDetector.record_event(id, :error, 12345)
      EntropyDetector.record_event(id, :error, 12345)

      result = EntropyDetector.session_entropy(id)
      assert result.event_count >= 2
    end
  end

  describe "session_entropy/1" do
    test "returns low entropy for unknown session" do
      result = EntropyDetector.session_entropy("unknown-#{System.unique_integer()}")
      assert result.entropy_level == :low
      assert result.score == 0
    end

    test "detects repeated patterns" do
      id = Ecto.UUID.generate()

      for _ <- 1..4 do
        EntropyDetector.record_event(id, :error, 99999)
      end

      result = EntropyDetector.session_entropy(id)
      assert result.score > 0
      assert Enum.any?(result.signals, &String.contains?(&1, "repeated"))
    end

    test "detects error clustering" do
      id = Ecto.UUID.generate()

      for _ <- 1..6 do
        EntropyDetector.record_event(id, :build_error)
      end

      result = EntropyDetector.session_entropy(id)
      assert result.score > 0
    end

    test "detects no-progress sessions" do
      id = Ecto.UUID.generate()

      for _ <- 1..10 do
        EntropyDetector.record_event(id, :other)
      end

      result = EntropyDetector.session_entropy(id)
      assert Enum.any?(result.signals, &String.contains?(&1, "spinning"))
    end
  end

  describe "state/0" do
    test "returns aggregate state" do
      result = EntropyDetector.state()
      assert is_map(result.sessions)
      assert is_map(result.highest)
    end
  end
end
