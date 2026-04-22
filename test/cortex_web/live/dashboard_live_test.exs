defmodule CortexWeb.DashboardLiveTest do
  use CortexWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  describe "Landing page GET /landing" do
    test "returns 200 with CORTEX in the response", %{conn: conn} do
      {:ok, _view, html} = live(conn, "/landing")
      assert html =~ "CORTEX"
    end

    test "page contains waitlist form", %{conn: conn} do
      {:ok, _view, html} = live(conn, "/landing")
      assert html =~ "Join Waitlist"
    end

    test "page contains feature descriptions", %{conn: conn} do
      {:ok, _view, html} = live(conn, "/landing")
      assert html =~ "Output Intelligence"
    end

    test "page contains pricing section", %{conn: conn} do
      {:ok, _view, html} = live(conn, "/landing")
      assert html =~ "$19"
    end
  end
end
