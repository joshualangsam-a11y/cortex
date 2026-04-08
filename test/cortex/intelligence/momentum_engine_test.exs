defmodule Cortex.Intelligence.MomentumEngineTest do
  use ExUnit.Case, async: false

  alias Cortex.Intelligence.MomentumEngine

  describe "state/0" do
    test "returns momentum state with all fields" do
      state = MomentumEngine.state()

      assert state.flow_state in [:idle, :flowing]
      assert is_integer(state.velocity)
      assert is_integer(state.peak_velocity)
      assert is_integer(state.active_sessions)
      assert is_integer(state.total_flow_ms)
    end
  end

  describe "velocity/0" do
    test "returns current velocity as integer" do
      velocity = MomentumEngine.velocity()
      assert is_integer(velocity)
      assert velocity >= 0
    end
  end

  describe "record_input/1" do
    test "accepts a session_id without error" do
      assert :ok == MomentumEngine.record_input("test-session-123")
    end

    test "recording input increases velocity on next tick" do
      # Record many inputs to boost velocity
      for _ <- 1..20 do
        MomentumEngine.record_input("test-burst-#{System.unique_integer()}")
      end

      # Give the tick time to process
      Process.sleep(2500)
      velocity = MomentumEngine.velocity()
      assert velocity > 0
    end
  end

  describe "topic/0" do
    test "returns the PubSub topic string" do
      assert MomentumEngine.topic() == "momentum:state"
    end
  end
end
