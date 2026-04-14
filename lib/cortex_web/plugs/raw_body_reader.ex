defmodule CortexWeb.RawBodyReader do
  @moduledoc """
  Custom body reader that caches the raw body in conn.assigns[:raw_body].
  Required for Stripe webhook signature verification.
  """

  def read_body(conn, opts) do
    case Plug.Conn.read_body(conn, opts) do
      {:ok, body, conn} ->
        {:ok, body, Plug.Conn.assign(conn, :raw_body, body)}

      {:more, body, conn} ->
        {:more, body, Plug.Conn.assign(conn, :raw_body, body)}

      {:error, reason} ->
        {:error, reason}
    end
  end
end
