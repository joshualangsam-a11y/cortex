defmodule CortexWeb.DevLoginController do
  use CortexWeb, :controller

  alias Cortex.Accounts
  alias CortexWeb.UserAuth

  def login(conn, %{"email" => email}) do
    if Application.get_env(:cortex, :env) == :dev do
      user =
        case Accounts.get_user_by_email(email) do
          nil ->
            {:ok, u} = Accounts.register_user(%{email: email})
            u

          u ->
            u
        end

      UserAuth.log_in_user(conn, user)
    else
      conn
      |> put_status(:not_found)
      |> text("Not found")
    end
  end
end
