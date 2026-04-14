defmodule CortexWeb.Settings.BillingLive do
  use CortexWeb, :live_view

  alias Cortex.Billing

  import CortexWeb.Settings.SettingsLayout

  @impl true
  def mount(_params, _session, socket) do
    user = socket.assigns.current_user

    socket =
      socket
      |> assign(:page_title, "Billing - Settings")
      |> assign(:user, user)
      |> assign(:loading, false)

    {:ok, socket}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <.settings_layout current_page={:billing}>
      <div class="max-w-2xl">
        <div class="mb-6">
          <h1 class="text-xl font-semibold text-[#ffd04a]">Billing</h1>
          <p class="text-xs text-[#5a5a5a] mt-1">
            Manage your subscription and billing details
          </p>
        </div>
        
    <!-- Current Plan -->
        <div class="border border-[#1a1a1a] rounded-lg bg-[#0a0a0a] p-6 mb-6">
          <div class="flex items-center justify-between mb-4">
            <div>
              <div class="text-sm text-[#5a5a5a] mb-1">Current plan</div>
              <div class="flex items-center gap-3">
                <span class={"text-2xl font-bold #{tier_color(@user.tier)}"}>
                  {String.capitalize(@user.tier)}
                </span>
                <span
                  :if={Billing.trialing?(@user)}
                  class="text-xs px-2 py-0.5 rounded-md bg-[#ffd04a]/15 text-[#ffd04a]"
                >
                  Trial
                </span>
              </div>
            </div>
            <div class="text-right">
              <div class="text-2xl font-bold text-[#e8dcc0]">
                {if Billing.pro?(@user), do: "$19", else: "$0"}
                <span class="text-sm font-normal text-[#5a5a5a]">/mo</span>
              </div>
            </div>
          </div>
          
    <!-- Trial info -->
          <div
            :if={Billing.trialing?(@user) and @user.trial_ends_at}
            class="bg-[#050505] border border-[#1a1a1a] rounded-md px-4 py-3 mb-4"
          >
            <p class="text-xs text-[#5a5a5a]">
              Trial ends
              <span class="text-[#ffd04a]">
                {Calendar.strftime(@user.trial_ends_at, "%B %d, %Y")}
              </span>
            </p>
          </div>
          
    <!-- Subscription status -->
          <div
            :if={@user.subscription_status not in [nil, "incomplete"]}
            class="flex items-center gap-2 mb-4"
          >
            <span class={"w-2 h-2 rounded-full #{status_dot(@user.subscription_status)}"} />
            <span class="text-xs text-[#5a5a5a]">
              {status_label(@user.subscription_status)}
            </span>
          </div>
          
    <!-- Plan features -->
          <div class="border-t border-[#1a1a1a] pt-4">
            <div class="text-xs text-[#5a5a5a] mb-3">Includes</div>
            <ul class="space-y-2">
              <%= if Billing.pro?(@user) do %>
                <.plan_feature text="Unlimited projects" />
                <.plan_feature text="Unlimited sessions" />
                <.plan_feature text="Workspaces & presets" />
                <.plan_feature text="Output intelligence" />
                <.plan_feature text="Priority engine" />
                <.plan_feature text="Terminal search" />
              <% else %>
                <.plan_feature text="3 projects" />
                <.plan_feature text="3 sessions" />
                <.plan_feature text="Basic terminal grid" />
                <.plan_feature text="Command palette" />
              <% end %>
            </ul>
          </div>
        </div>
        
    <!-- Actions -->
        <div class="border border-[#1a1a1a] rounded-lg bg-[#0a0a0a] p-6">
          <%= if Billing.pro?(@user) do %>
            <p class="text-sm text-[#e8dcc0] mb-4">
              Manage your subscription, update payment method, or download invoices.
            </p>
            <button
              phx-click="manage_billing"
              disabled={@loading}
              class="px-4 py-2 text-sm rounded-md border border-[#1a1a1a] text-[#e8dcc0] hover:border-[#ffd04a] hover:text-[#ffd04a] transition-colors disabled:opacity-50"
            >
              {if @loading, do: "Loading...", else: "Manage Subscription"}
            </button>
          <% else %>
            <p class="text-sm text-[#e8dcc0] mb-2">
              Upgrade to Pro for unlimited projects, sessions, and intelligence features.
            </p>
            <p class="text-xs text-[#5a5a5a] mb-4">
              Includes a {Billing.trial_days()}-day free trial. Cancel anytime.
            </p>
            <button
              phx-click="upgrade"
              disabled={@loading}
              class="px-6 py-2.5 text-sm rounded-md bg-[#ffd04a] text-[#050505] font-medium hover:opacity-90 transition-opacity disabled:opacity-50"
            >
              {if @loading, do: "Loading...", else: "Upgrade to Pro — $19/mo"}
            </button>
          <% end %>
        </div>
      </div>
    </.settings_layout>
    """
  end

  # -- Components --

  defp plan_feature(assigns) do
    ~H"""
    <li class="flex items-center gap-2.5 text-xs text-[#e8dcc0]">
      <span class="w-1.5 h-1.5 rounded-full bg-[#ffd04a] shrink-0" />
      {@text}
    </li>
    """
  end

  # -- Events --

  @impl true
  def handle_event("upgrade", _params, socket) do
    socket = assign(socket, :loading, true)
    user = socket.assigns.user
    base_url = CortexWeb.Endpoint.url()

    case Billing.create_checkout_session(
           user,
           "#{base_url}/settings/billing?success=true",
           "#{base_url}/settings/billing?canceled=true"
         ) do
      {:ok, session} ->
        {:noreply, redirect(socket, external: session.url)}

      {:error, _reason} ->
        {:noreply,
         socket
         |> assign(:loading, false)
         |> put_flash(:error, "Could not start checkout. Try again.")}
    end
  end

  def handle_event("manage_billing", _params, socket) do
    socket = assign(socket, :loading, true)
    user = socket.assigns.user
    return_url = "#{CortexWeb.Endpoint.url()}/settings/billing"

    case Billing.create_portal_session(user, return_url) do
      {:ok, session} ->
        {:noreply, redirect(socket, external: session.url)}

      {:error, _reason} ->
        {:noreply,
         socket
         |> assign(:loading, false)
         |> put_flash(:error, "Could not open billing portal. Try again.")}
    end
  end

  # -- Helpers --

  defp tier_color("pro"), do: "text-[#ffd04a]"
  defp tier_color("team"), do: "text-[#5a9bcf]"
  defp tier_color(_), do: "text-[#e8dcc0]"

  defp status_dot("active"), do: "bg-[#5ea85e]"
  defp status_dot("trialing"), do: "bg-[#ffd04a]"
  defp status_dot("past_due"), do: "bg-[#e05252]"
  defp status_dot("canceled"), do: "bg-[#5a5a5a]"
  defp status_dot(_), do: "bg-[#3a3a3a]"

  defp status_label("active"), do: "Active"
  defp status_label("trialing"), do: "Trialing"
  defp status_label("past_due"), do: "Past due — update payment method"
  defp status_label("canceled"), do: "Canceled"
  defp status_label("incomplete"), do: "Incomplete"
  defp status_label(s), do: s
end
