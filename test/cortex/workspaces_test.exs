defmodule Cortex.WorkspacesTest do
  use Cortex.DataCase, async: true

  alias Cortex.Workspaces

  @sessions [
    %{"title" => "term1", "project_name" => "FuelOps", "cwd" => "/tmp"},
    %{"title" => "term2", "project_name" => "VapeOps", "cwd" => "/tmp"}
  ]

  describe "save_workspace/3" do
    test "creates a workspace" do
      assert {:ok, ws} = Workspaces.save_workspace("test-ws", @sessions, 2)
      assert ws.name == "test-ws"
      assert ws.sessions == @sessions
      assert ws.grid_cols == 2
    end

    test "upserts: same name overwrites sessions" do
      {:ok, _} = Workspaces.save_workspace("upsert-ws", @sessions, 2)
      new_sessions = [%{"title" => "new", "cwd" => "/home"}]
      {:ok, ws} = Workspaces.save_workspace("upsert-ws", new_sessions, 1)

      assert ws.name == "upsert-ws"
      assert ws.sessions == new_sessions
      assert ws.grid_cols == 1
    end
  end

  describe "load_workspace/1" do
    test "retrieves workspace by name" do
      {:ok, _} = Workspaces.save_workspace("load-ws", @sessions)
      ws = Workspaces.load_workspace("load-ws")

      assert ws.name == "load-ws"
      assert ws.sessions == @sessions
    end

    test "returns nil for non-existent workspace" do
      assert Workspaces.load_workspace("nope") == nil
    end
  end

  describe "list_workspaces/0" do
    test "returns all workspaces ordered by name" do
      {:ok, _} = Workspaces.save_workspace("bravo", [])
      {:ok, _} = Workspaces.save_workspace("alpha", [])
      {:ok, _} = Workspaces.save_workspace("charlie", [])

      names = Workspaces.list_workspaces() |> Enum.map(& &1.name)
      assert names == ["alpha", "bravo", "charlie"]
    end

    test "returns empty list when no workspaces exist" do
      assert Workspaces.list_workspaces() == []
    end
  end

  describe "delete_workspace/1" do
    test "removes a workspace" do
      {:ok, _} = Workspaces.save_workspace("delete-me", @sessions)
      assert {:ok, _} = Workspaces.delete_workspace("delete-me")
      assert Workspaces.load_workspace("delete-me") == nil
    end

    test "returns error for non-existent workspace" do
      assert {:error, :not_found} = Workspaces.delete_workspace("ghost")
    end
  end
end
