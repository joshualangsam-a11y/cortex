defmodule Cortex.Intelligence.FlowHistoryTest do
  use Cortex.DataCase, async: true

  alias Cortex.Intelligence.FlowHistory

  describe "start_flow/2 and end_flow/1" do
    test "creates and completes a flow session" do
      {:ok, flow} = FlowHistory.start_flow(25, 3)

      assert flow.started_at
      assert flow.peak_velocity == 25
      assert flow.active_sessions == 3
      assert is_nil(flow.ended_at)

      {:ok, ended} = FlowHistory.end_flow(30)

      assert ended.ended_at
      assert ended.duration_seconds >= 0
      assert ended.peak_velocity == 30
    end
  end

  describe "today_stats/0" do
    test "returns stats structure with zero defaults" do
      stats = FlowHistory.today_stats()

      assert is_integer(stats.sessions)
      assert is_integer(stats.total_minutes)
      assert is_integer(stats.longest_minutes)
      assert is_integer(stats.peak_velocity)
    end

    test "counts today's flow sessions" do
      FlowHistory.start_flow(20, 2)
      FlowHistory.end_flow(25)

      stats = FlowHistory.today_stats()
      assert stats.sessions >= 1
    end
  end

  describe "count_streak/0" do
    test "returns integer streak count" do
      streak = FlowHistory.count_streak()
      assert is_integer(streak)
      assert streak >= 0
    end
  end
end
