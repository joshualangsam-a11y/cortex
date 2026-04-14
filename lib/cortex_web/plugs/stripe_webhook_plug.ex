defmodule CortexWeb.StripeWebhookPlug do
  @moduledoc """
  Plug that verifies Stripe webhook signatures and assigns the parsed event.
  Must be used before the StripeWebhookController.

  Reads the raw body (cached by Plug.Parsers :pass_raw_body option)
  and verifies it against the Stripe signing secret.
  """

  import Plug.Conn

  def init(opts), do: opts

  def call(conn, _opts) do
    signing_secret = Application.get_env(:stripity_stripe, :signing_secret)

    with [signature] <- get_req_header(conn, "stripe-signature"),
         {:ok, raw_body} <- read_cached_body(conn),
         {:ok, event} <-
           Stripe.Webhook.construct_event(raw_body, signature, signing_secret) do
      assign(conn, :stripe_event, event)
    else
      _ ->
        conn
        |> put_status(400)
        |> Phoenix.Controller.json(%{error: "Invalid webhook signature"})
        |> halt()
    end
  end

  defp read_cached_body(conn) do
    case conn.assigns[:raw_body] do
      body when is_binary(body) -> {:ok, body}
      _ -> {:error, :no_raw_body}
    end
  end
end
