defmodule Cortex.Intelligence.EnergyCycleTest do
  use ExUnit.Case, async: true

  alias Cortex.Intelligence.EnergyCycle

  describe "current_phase/0" do
    test "returns an atom phase" do
      phase = EnergyCycle.current_phase()
      assert phase in [:mud, :rising, :peak, :winding_down, :rest]
    end
  end

  describe "state/0" do
    test "returns a map with all energy fields" do
      state = EnergyCycle.state()

      assert is_atom(state.phase)
      assert is_integer(state.level)
      assert state.level >= 1 and state.level <= 10
      assert is_integer(state.hour)
      assert is_binary(state.suggestion)
      assert is_integer(state.peak_starts_in)
      assert is_boolean(state.deep_work_ok)
    end
  end

  describe "defer?/1" do
    test "returns boolean for architecture tasks" do
      assert is_boolean(EnergyCycle.defer?(:architecture))
    end

    test "never defers non-heavy tasks" do
      refute EnergyCycle.defer?(:email)
      refute EnergyCycle.defer?(:pipeline_review)
    end
  end

  describe "sort_by_energy/1" do
    test "returns sorted list" do
      tasks = [
        %{name: "heavy", energy_cost: :high},
        %{name: "light", energy_cost: :low},
        %{name: "medium", energy_cost: :medium}
      ]

      sorted = EnergyCycle.sort_by_energy(tasks)
      assert length(sorted) == 3
    end
  end
end
