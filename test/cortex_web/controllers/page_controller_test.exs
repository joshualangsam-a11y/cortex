defmodule CortexWeb.PageControllerTest do
  use CortexWeb.ConnCase

  test "GET / redirects unauthenticated user to /landing", %{conn: conn} do
    conn = get(conn, ~p"/")
    assert redirected_to(conn) == "/landing"
  end
end
