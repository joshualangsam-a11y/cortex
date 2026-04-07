defmodule CortexWeb.UserSessionController do
  use CortexWeb, :controller

  alias Cortex.Accounts
  alias CortexWeb.UserAuth

  @doc """
  Magic link callback -- verifies token and logs user in.
  We handle this in a controller (not LiveView) because we need to set session cookies.
  """
  def create(conn, %{"token" => token}) do
    case Accounts.verify_magic_link_token(token) do
      {:ok, user} ->
        UserAuth.log_in_user(conn, user)

      :error ->
        conn
        |> put_flash(:error, "Magic link is invalid or expired.")
        |> redirect(to: "/login")
    end
  end

  @doc """
  Logs out the user.
  """
  def delete(conn, _params) do
    UserAuth.log_out_user(conn)
  end
end
