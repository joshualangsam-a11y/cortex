defmodule Cortex.Intelligence.FlowPredictorTest do
  use Cortex.DataCase, async: false

  alias Cortex.Intelligence.FlowPredictor

  describe "predict_today/0" do
    test "returns prediction structure" do
      pred = FlowPredictor.predict_today()

      assert is_list(pred.windows)
      assert pred.day_outlook in [:strong, :moderate, :low]
      assert is_binary(pred.day_insight)
      assert is_float(pred.confidence) or is_integer(pred.confidence)
    end

    test "best_window is nil or has required fields" do
      pred = FlowPredictor.predict_today()

      case pred.best_window do
        nil ->
          assert true

        w ->
          assert is_integer(w.hour_start)
          assert is_integer(w.hour_end)
          assert is_float(w.probability)
      end
    end
  end

  describe "brief_prediction/0" do
    test "returns a string" do
      result = FlowPredictor.brief_prediction()
      assert is_binary(result)
    end
  end

  describe "deep_work_now?/0" do
    test "returns tagged tuple with reason" do
      {tag, reason} = FlowPredictor.deep_work_now?()
      assert tag in [:yes, :no, :maybe]
      assert is_binary(reason)
    end
  end
end
