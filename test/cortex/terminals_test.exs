defmodule Cortex.TerminalsTest do
  use Cortex.DataCase, async: true

  alias Cortex.Terminals
  alias Cortex.Terminals.Session
  alias Cortex.Terminals.Layout

  describe "save_layout/2" do
    test "persists layout" do
      order = ["id-1", "id-2", "id-3"]
      assert {:ok, layout} = Terminals.save_layout(order, 2)
      assert layout.name == "last_workspace"
      assert layout.session_order == order
      assert layout.grid_cols == 2
    end

    test "upserts layout on repeated saves" do
      {:ok, _} = Terminals.save_layout(["a", "b"], 3)
      {:ok, layout} = Terminals.save_layout(["c", "d", "e"], 2)

      assert layout.session_order == ["c", "d", "e"]
      assert layout.grid_cols == 2

      # Only one layout record should exist
      count = Repo.aggregate(from(l in Layout, where: l.name == "last_workspace"), :count)
      assert count == 1
    end
  end

  describe "get_last_layout/0" do
    test "retrieves the saved layout" do
      {:ok, _} = Terminals.save_layout(["x", "y"], 2)
      layout = Terminals.get_last_layout()

      assert layout.name == "last_workspace"
      assert layout.session_order == ["x", "y"]
    end

    test "returns nil when no layout saved" do
      assert Terminals.get_last_layout() == nil
    end
  end

  describe "mark_exited/2" do
    test "updates session status to exited" do
      # Insert a session record directly
      id = Ecto.UUID.generate()

      {:ok, session} =
        %Session{id: id}
        |> Session.changeset(%{
          title: "test",
          status: "running",
          cwd: "/tmp",
          started_at: DateTime.utc_now()
        })
        |> Repo.insert()

      Terminals.mark_exited(session.id, 0)

      updated = Repo.get(Session, session.id)
      assert updated.status == "exited"
      assert updated.exit_code == 0
      assert updated.exited_at != nil
    end

    test "returns :ok for non-existent session" do
      assert :ok = Terminals.mark_exited(Ecto.UUID.generate(), 1)
    end
  end
end
