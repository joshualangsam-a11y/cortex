defmodule Cortex.Intelligence.FlowCalibratorTest do
  use Cortex.DataCase, async: true

  alias Cortex.Intelligence.{FlowCalibrator, FlowHistory}

  describe "status/0" do
    test "returns status with progress tracking" do
      status = FlowCalibrator.status()

      assert is_integer(status.sessions_recorded)
      assert status.sessions_needed == 10
      assert is_boolean(status.ready)
      assert is_integer(status.progress)
      assert status.progress >= 0 and status.progress <= 100
    end
  end

  describe "calibrate/0" do
    test "returns nil with insufficient data" do
      assert nil == FlowCalibrator.calibrate()
    end

    test "returns calibration data with enough flow sessions" do
      # Insert 12 completed flow sessions
      for i <- 1..12 do
        {:ok, flow} = FlowHistory.start_flow(10 + i, 3)

        flow
        |> Ecto.Changeset.change(%{
          ended_at: DateTime.add(flow.started_at, 1800 + i * 60),
          duration_seconds: 1800 + i * 60,
          peak_velocity: 10 + i
        })
        |> Cortex.Repo.update!()
      end

      result = FlowCalibrator.calibrate()

      assert result != nil
      assert is_integer(result.recommended_velocity_threshold)
      assert is_integer(result.recommended_sustain_seconds)
      assert result.recommended_sustain_seconds >= 15
      assert result.recommended_sustain_seconds <= 120
      assert result.sessions_analyzed == 12
      assert is_float(result.confidence)
    end
  end
end
