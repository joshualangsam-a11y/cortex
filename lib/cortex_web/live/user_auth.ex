defmodule CortexWeb.Live.UserAuth do
  @moduledoc """
  LiveView on_mount hooks for authentication.
  """

  import Phoenix.LiveView
  import Phoenix.Component

  def on_mount(:ensure_authenticated, _params, session, socket) do
    socket = assign_current_user(socket, session)

    # Local-only mode: allow unauthenticated access when no users exist
    if socket.assigns.current_user || local_dev_mode?() do
      {:cont, socket}
    else
      {:halt, redirect(socket, to: "/login")}
    end
  end

  def on_mount(:mount_current_user, _params, session, socket) do
    {:cont, assign_current_user(socket, session)}
  end

  defp assign_current_user(socket, session) do
    case session["user_token"] do
      nil -> assign(socket, :current_user, nil)
      token -> assign(socket, :current_user, Cortex.Accounts.get_user_by_session_token(token))
    end
  end

  defp local_dev_mode? do
    Application.get_env(:cortex, :env) == :dev
  end
end
