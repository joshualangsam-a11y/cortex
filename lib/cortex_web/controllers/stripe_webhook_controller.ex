defmodule CortexWeb.StripeWebhookController do
  use CortexWeb, :controller

  require Logger

  alias Cortex.Billing

  @doc """
  Handles incoming Stripe webhook events.
  Signature verification is done by the StripeWebhookPlug in the endpoint.
  """
  def handle(conn, _params) do
    event = conn.assigns[:stripe_event]

    case event.type do
      "checkout.session.completed" ->
        Billing.handle_checkout_completed(event.data.object)

      "customer.subscription.updated" ->
        Billing.handle_subscription_event(event.data.object)

      "customer.subscription.deleted" ->
        Billing.handle_subscription_event(event.data.object)

      "invoice.payment_failed" ->
        Logger.warning("Stripe: payment failed for customer #{event.data.object.customer}")

      _ ->
        Logger.debug("Stripe: unhandled event type #{event.type}")
    end

    json(conn, %{received: true})
  end
end
