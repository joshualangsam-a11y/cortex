defmodule CortexWeb.PageController do
  use CortexWeb, :controller

  def home(conn, _params) do
    target = if conn.assigns[:current_user], do: "/dashboard", else: "/landing"
    redirect(conn, to: target)
  end
end
