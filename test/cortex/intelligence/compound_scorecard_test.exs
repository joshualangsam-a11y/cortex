defmodule Cortex.Intelligence.CompoundScorecardTest do
  use Cortex.DataCase, async: false

  alias Cortex.Intelligence.CompoundScorecard

  describe "record_flow_prediction/3" do
    test "inserts a flow prediction" do
      {:ok, pred} = CompoundScorecard.record_flow_prediction(14, 16, 0.7)
      assert pred.type == "flow_window"
      assert pred.confidence == 0.7
      assert pred.scored == false
    end
  end

  describe "record_crash_prediction/2" do
    test "inserts a crash prediction" do
      {:ok, pred} = CompoundScorecard.record_crash_prediction(15, :medium)
      assert pred.type == "crash_warning"
      assert pred.confidence == 0.6
    end
  end

  describe "record_project_prediction/2" do
    test "inserts a project match prediction" do
      {:ok, pred} = CompoundScorecard.record_project_prediction("cortex", 75.0)
      assert pred.type == "project_match"

      assert pred.prediction_value["project_name"] == "cortex" or
               pred.prediction_value[:project_name] == "cortex"
    end
  end

  describe "accuracy_stats/0" do
    test "returns map of type stats" do
      stats = CompoundScorecard.accuracy_stats()
      assert is_map(stats)
    end
  end

  describe "overall_accuracy/0" do
    test "returns aggregate accuracy" do
      acc = CompoundScorecard.overall_accuracy()
      assert is_integer(acc.total)
      assert is_integer(acc.accurate)
      assert is_float(acc.accuracy_pct)
    end
  end

  describe "brief_line/0" do
    test "returns a string" do
      line = CompoundScorecard.brief_line()
      assert is_binary(line)
    end
  end

  describe "score_pending/0" do
    test "scores predictions past target time" do
      # Insert a prediction with target_time in the past
      {:ok, _pred} = CompoundScorecard.record_flow_prediction(0, 2, 0.5)

      results = CompoundScorecard.score_pending()
      assert is_list(results)
    end
  end
end
