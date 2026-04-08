defmodule Cortex.Intelligence.ProjectMatcherTest do
  use Cortex.DataCase, async: false

  alias Cortex.Intelligence.ProjectMatcher

  describe "match/0" do
    test "returns list of scored projects" do
      matches = ProjectMatcher.match()
      assert is_list(matches)

      for m <- matches do
        assert is_binary(m.project_name)
        assert is_float(m.score) or is_integer(m.score)
        assert is_list(m.reasons)
        assert m.energy_match in [:perfect, :good, :poor]
        assert is_boolean(m.has_resume_point)
      end
    end
  end

  describe "best_match/0" do
    test "returns nil or match map" do
      result = ProjectMatcher.best_match()
      assert is_nil(result) or is_map(result)
    end
  end

  describe "suggestion/0" do
    test "returns nil or string" do
      result = ProjectMatcher.suggestion()
      assert is_nil(result) or is_binary(result)
    end
  end
end
