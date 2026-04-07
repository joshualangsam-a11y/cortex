defmodule Cortex.Projects.GitStatusTest do
  use ExUnit.Case, async: true

  alias Cortex.Projects.GitStatus

  describe "check/1" do
    test "on a valid git repo returns branch and changes count" do
      # Use the cortex project itself as a known git repo
      path = Path.expand("../../..", __DIR__)

      if File.dir?(Path.join(path, ".git")) do
        result = GitStatus.check(path)
        assert is_binary(result.branch)
        assert is_integer(result.changes)
        assert is_boolean(result.dirty)
      end
    end

    test "on a non-git directory returns defaults" do
      # /tmp is not a git repo
      result = GitStatus.check(System.tmp_dir!())
      assert result.branch == nil
      assert result.changes == 0
      assert result.dirty == false
    end

    test "on non-existent path returns defaults" do
      result = GitStatus.check("/nonexistent/path/that/does/not/exist")
      assert result.branch == nil
      assert result.changes == 0
      assert result.dirty == false
    end
  end
end
