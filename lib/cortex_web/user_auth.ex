defmodule CortexWeb.UserAuth do
  @moduledoc """
  Authentication plugs for the browser pipeline.
  """

  use CortexWeb, :controller

  alias Cortex.Accounts

  @session_key "user_token"

  @doc """
  Logs the user in by generating a session token and putting it in the session.
  """
  def log_in_user(conn, user) do
    token = Accounts.generate_session_token(user)

    conn
    |> renew_session()
    |> put_session(@session_key, token)
    |> put_session(:live_socket_id, "users_sessions:#{Base.url_encode64(token)}")
    |> redirect(to: "/dashboard")
  end

  @doc """
  Logs the user out by deleting the session token and clearing the session.
  """
  def log_out_user(conn) do
    if token = get_session(conn, @session_key) do
      Accounts.delete_session_token(token)
    end

    if live_socket_id = get_session(conn, :live_socket_id) do
      CortexWeb.Endpoint.broadcast(live_socket_id, "disconnect", %{})
    end

    conn
    |> renew_session()
    |> redirect(to: "/")
  end

  @doc """
  Plug: reads the session token and loads the current user.
  """
  def fetch_current_user(conn, _opts) do
    {token, conn} = ensure_user_token(conn)
    user = token && Accounts.get_user_by_session_token(token)
    assign(conn, :current_user, user)
  end

  @doc """
  Plug: redirects to /login if user is not authenticated.
  """
  def require_authenticated_user(conn, _opts) do
    if conn.assigns[:current_user] do
      conn
    else
      conn
      |> put_flash(:error, "You must log in to access this page.")
      |> redirect(to: "/login")
      |> halt()
    end
  end

  @doc """
  Plug: redirects to /dashboard if user is already authenticated.
  """
  def redirect_if_user_is_authenticated(conn, _opts) do
    if conn.assigns[:current_user] do
      conn
      |> redirect(to: "/dashboard")
      |> halt()
    else
      conn
    end
  end

  defp ensure_user_token(conn) do
    if token = get_session(conn, @session_key) do
      {token, conn}
    else
      {nil, conn}
    end
  end

  defp renew_session(conn) do
    delete_csrf_token()

    conn
    |> configure_session(renew: true)
    |> clear_session()
  end
end
