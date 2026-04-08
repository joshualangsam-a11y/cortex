defmodule Cortex.Intelligence.CompactionAdvisorTest do
  use Cortex.DataCase, async: false

  alias Cortex.Intelligence.CompactionAdvisor

  # Dependencies are started by the application supervision tree

  describe "advise/0" do
    test "returns advice structure" do
      advice = CompactionAdvisor.advise()

      assert is_boolean(advice.should_compact)
      assert advice.urgency in [:low, :medium, :high, :critical]
      assert is_binary(advice.reason)
      assert is_integer(advice.estimated_context_pct)
      assert is_binary(advice.optimal_timing)
      assert is_list(advice.signals)
    end
  end

  describe "compact_now?/0" do
    test "returns {boolean, reason}" do
      {should, reason} = CompactionAdvisor.compact_now?()
      assert is_boolean(should)
      assert is_binary(reason)
    end
  end

  describe "brief_line/0" do
    test "returns nil or string" do
      result = CompactionAdvisor.brief_line()
      assert is_nil(result) or is_binary(result)
    end
  end
end
