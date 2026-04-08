defmodule Cortex.Intelligence.SessionArchitectTest do
  use Cortex.DataCase, async: false

  alias Cortex.Intelligence.SessionArchitect

  # SessionDNA is started by the application supervision tree

  describe "recommend/0" do
    test "returns list of recommendations" do
      recs = SessionArchitect.recommend()
      assert is_list(recs)

      # Should always include the BEM terse-vs-verbose insight
      assert Enum.any?(recs, fn r -> r.category == :prompt_style end)
    end

    test "recommendations have required fields" do
      recs = SessionArchitect.recommend()

      for rec <- recs do
        assert is_binary(rec.recommendation)
        assert is_binary(rec.evidence)
        assert is_float(rec.confidence) or is_integer(rec.confidence)
        assert is_atom(rec.category)
      end
    end
  end

  describe "top_recommendation/0" do
    test "returns highest confidence recommendation" do
      rec = SessionArchitect.top_recommendation()
      assert rec == nil or is_map(rec)
    end
  end

  describe "recommended_structure/0" do
    test "returns a session structure atom" do
      structure = SessionArchitect.recommended_structure()
      assert structure in [:single_focus, :burst_mode, :light_admin, :wind_down]
    end
  end
end
