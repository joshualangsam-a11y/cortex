defmodule Cortex.Billing do
  @moduledoc """
  The Billing context — Stripe customers, subscriptions, checkout, portal, feature gating.
  """

  import Ecto.Query
  alias Cortex.Repo
  alias Cortex.Accounts.User

  @pro_price_id "price_cortex_pro_monthly"
  @trial_days 14
  @free_limits %{projects: 3, sessions: 3}

  ## Stripe Customer

  def get_or_create_stripe_customer(%User{stripe_customer_id: cid}) when is_binary(cid) do
    {:ok, cid}
  end

  def get_or_create_stripe_customer(%User{} = user) do
    with {:ok, customer} <-
           Stripe.Customer.create(%{
             email: user.email,
             name: user.name,
             metadata: %{"cortex_user_id" => user.id}
           }) do
      user
      |> Ecto.Changeset.change(%{stripe_customer_id: customer.id})
      |> Repo.update!()

      {:ok, customer.id}
    end
  end

  ## Checkout

  def create_checkout_session(%User{} = user, success_url, cancel_url) do
    with {:ok, customer_id} <- get_or_create_stripe_customer(user) do
      params = %{
        customer: customer_id,
        mode: "subscription",
        line_items: [%{price: pro_price_id(), quantity: 1}],
        success_url: success_url,
        cancel_url: cancel_url,
        subscription_data: %{trial_period_days: @trial_days}
      }

      Stripe.Checkout.Session.create(params)
    end
  end

  ## Portal

  def create_portal_session(%User{stripe_customer_id: cid}, return_url) when is_binary(cid) do
    Stripe.BillingPortal.Session.create(%{customer: cid, return_url: return_url})
  end

  def create_portal_session(_user, _return_url), do: {:error, :no_stripe_customer}

  ## Subscription sync (called from webhooks)

  def sync_subscription(stripe_subscription_id) do
    with {:ok, sub} <- Stripe.Subscription.retrieve(stripe_subscription_id) do
      update_user_subscription(sub)
    end
  end

  def handle_subscription_event(subscription) do
    update_user_subscription(subscription)
  end

  def handle_checkout_completed(session) do
    customer_id = session.customer
    subscription_id = session.subscription

    case Repo.one(from u in User, where: u.stripe_customer_id == ^customer_id) do
      nil ->
        {:error, :user_not_found}

      user ->
        user
        |> Ecto.Changeset.change(%{stripe_subscription_id: subscription_id})
        |> Repo.update()

        sync_subscription(subscription_id)
    end
  end

  defp update_user_subscription(subscription) do
    customer_id = subscription.customer

    case Repo.one(from u in User, where: u.stripe_customer_id == ^customer_id) do
      nil ->
        {:error, :user_not_found}

      user ->
        tier = subscription_to_tier(subscription.status)

        trial_ends_at =
          if subscription.trial_end do
            DateTime.from_unix!(subscription.trial_end)
          end

        user
        |> Ecto.Changeset.change(%{
          stripe_subscription_id: subscription.id,
          subscription_status: subscription.status,
          tier: tier,
          trial_ends_at: trial_ends_at
        })
        |> Repo.update()
    end
  end

  defp subscription_to_tier(status) when status in ["active", "trialing"], do: "pro"
  defp subscription_to_tier(_), do: "free"

  ## Feature Gating

  def pro?(%User{tier: tier}), do: tier in ["pro", "team"]
  def pro?(_), do: false

  def trialing?(%User{subscription_status: "trialing"}), do: true
  def trialing?(_), do: false

  def trial_active?(%User{trial_ends_at: nil}), do: false

  def trial_active?(%User{trial_ends_at: ends_at}) do
    DateTime.compare(DateTime.utc_now(), ends_at) == :lt
  end

  def can_access_pro?(%User{} = user) do
    pro?(user) or trial_active?(user)
  end

  def within_free_limit?(resource, count) when resource in [:projects, :sessions] do
    count < Map.fetch!(@free_limits, resource)
  end

  def gate(%User{} = user, feature) when feature in [:workspaces, :intelligence, :search] do
    if can_access_pro?(user), do: :ok, else: {:error, :upgrade_required}
  end

  def gate(%User{} = user, {:projects, count}) do
    if can_access_pro?(user) or within_free_limit?(:projects, count),
      do: :ok,
      else: {:error, :upgrade_required}
  end

  def gate(%User{} = user, {:sessions, count}) do
    if can_access_pro?(user) or within_free_limit?(:sessions, count),
      do: :ok,
      else: {:error, :upgrade_required}
  end

  ## Config helpers

  def pro_price_id do
    Application.get_env(:cortex, :stripe_pro_price_id, @pro_price_id)
  end

  def trial_days, do: @trial_days
  def free_limits, do: @free_limits
end
