defmodule Cortex.NDProfileTest do
  use Cortex.DataCase, async: true

  alias Cortex.NDProfile

  describe "default/0" do
    test "returns a profile struct with ADHD-optimized defaults" do
      profile = NDProfile.default()

      assert profile.thinking_style == "parallel"
      assert profile.parallel_capacity == 10
      assert profile.mud_start == 6
      assert profile.mud_end == 11
      assert profile.peak_start == 14
      assert profile.peak_end == 22
      assert profile.flow_velocity_threshold == 15
      assert profile.context_switch_cost == "high"
      assert profile.interruption_tolerance == "low"
    end
  end

  describe "current/0" do
    test "returns default profile when no DB record exists" do
      profile = NDProfile.current()

      assert profile.thinking_style == "parallel"
      assert profile.flow_velocity_threshold == 15
    end
  end

  describe "changeset/2" do
    test "validates thinking_style inclusion" do
      cs = NDProfile.changeset(%NDProfile{}, %{thinking_style: "invalid"})
      assert {:thinking_style, _} = hd(cs.errors)
    end

    test "validates parallel_capacity range" do
      cs = NDProfile.changeset(%NDProfile{}, %{parallel_capacity: 0})
      assert {:parallel_capacity, _} = hd(cs.errors)

      cs = NDProfile.changeset(%NDProfile{}, %{parallel_capacity: 25})
      assert {:parallel_capacity, _} = hd(cs.errors)
    end

    test "accepts valid changes" do
      cs =
        NDProfile.changeset(%NDProfile{}, %{
          thinking_style: "linear",
          parallel_capacity: 4,
          flow_velocity_threshold: 10
        })

      assert cs.valid?
    end
  end

  describe "presets/0" do
    test "returns preset map with expected keys" do
      presets = NDProfile.presets()

      assert Map.has_key?(presets, "adhd_parallel")
      assert Map.has_key?(presets, "adhd_hyperfocus")
      assert Map.has_key?(presets, "autism_systematic")
      assert Map.has_key?(presets, "dyslexia_visual")
      assert Map.has_key?(presets, "neurotypical")
    end

    test "each preset has name, description, and profile" do
      for {_key, preset} <- NDProfile.presets() do
        assert is_binary(preset.name)
        assert is_binary(preset.description)
        assert is_map(preset.profile)
      end
    end
  end
end
