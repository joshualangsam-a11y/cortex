defmodule Cortex.Intelligence.CrashPredictorTest do
  use Cortex.DataCase, async: false

  alias Cortex.Intelligence.CrashPredictor

  describe "predict/0" do
    test "returns prediction structure" do
      pred = CrashPredictor.predict()

      assert is_boolean(pred.crash_likely)
      assert pred.severity in [:none, :low, :medium, :high]
      assert is_list(pred.signals)
      assert is_binary(pred.suggestion)
      assert is_float(pred.confidence) or is_integer(pred.confidence)
    end

    test "minutes_until is nil or positive integer" do
      pred = CrashPredictor.predict()

      assert is_nil(pred.minutes_until) or
               (is_integer(pred.minutes_until) and pred.minutes_until >= 0)
    end
  end

  describe "status/0" do
    test "returns a status atom" do
      status = CrashPredictor.status()
      assert status in [:safe, :watch, :warning, :imminent]
    end
  end

  describe "brief_line/0" do
    test "returns nil or string" do
      result = CrashPredictor.brief_line()
      assert is_nil(result) or is_binary(result)
    end
  end
end
