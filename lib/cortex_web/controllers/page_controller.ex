defmodule CortexWeb.PageController do
  use CortexWeb, :controller

  def home(conn, _params) do
    redirect(conn, to: "/dashboard")
  end
end
