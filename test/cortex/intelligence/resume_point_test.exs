defmodule Cortex.Intelligence.ResumePointTest do
  use Cortex.DataCase, async: true

  alias Cortex.Intelligence.ResumePoint

  describe "from_output/3" do
    test "detects compile errors and generates resume point" do
      output = """
      ** (CompileError) lib/my_app.ex:10: undefined function foo/0
      """

      {:ok, rp} = ResumePoint.from_output(Ecto.UUID.generate(), "test-project", output)

      assert rp.context =~ "compile error"
      assert rp.next_action =~ "Re-run"
      assert rp.urgency == "high"
      assert rp.status == "pending"
    end

    test "detects test failures" do
      output = "5 tests, 2 failures"

      {:ok, rp} = ResumePoint.from_output(Ecto.UUID.generate(), "test-project", output)

      assert rp.context =~ "2/5 tests failing"
      assert rp.next_action =~ "Fix"
    end

    test "detects git merge conflicts" do
      output = "CONFLICT (content): Merge conflict in lib/app.ex"

      {:ok, rp} = ResumePoint.from_output(Ecto.UUID.generate(), "test-project", output)

      assert rp.context =~ "merge conflict"
      assert rp.urgency == "high"
    end

    test "detects uncommitted changes" do
      output = """
      Changes not staged for commit:
        modified: lib/app.ex
      """

      {:ok, rp} = ResumePoint.from_output(Ecto.UUID.generate(), "test-project", output)

      assert rp.context =~ "Uncommitted"
    end

    test "returns nil for empty output" do
      assert nil == ResumePoint.from_output(Ecto.UUID.generate(), "test-project", "")
    end

    test "returns nil for short generic output" do
      assert nil == ResumePoint.from_output(Ecto.UUID.generate(), "test-project", "hi")
    end
  end

  describe "pending/0" do
    test "returns pending resume points" do
      ResumePoint.from_output(
        Ecto.UUID.generate(),
        "proj-a",
        "** (CompileError) lib/foo.ex:1: error"
      )

      ResumePoint.from_output(Ecto.UUID.generate(), "proj-b", "5 tests, 3 failures")

      pending = ResumePoint.pending()
      assert length(pending) >= 2
      assert Enum.all?(pending, &(&1.status == "pending"))
    end
  end

  describe "mark_resumed/1 and mark_dismissed/1" do
    test "marks a resume point as resumed" do
      {:ok, rp} =
        ResumePoint.from_output(Ecto.UUID.generate(), "proj", "** (CompileError) foo.ex:1: err")

      {:ok, updated} = ResumePoint.mark_resumed(rp.id)
      assert updated.status == "resumed"
    end

    test "marks a resume point as dismissed" do
      {:ok, rp} = ResumePoint.from_output(Ecto.UUID.generate(), "proj", "CONFLICT in file.ex")
      {:ok, updated} = ResumePoint.mark_dismissed(rp.id)
      assert updated.status == "dismissed"
    end
  end
end
