defmodule CortexWeb.Router do
  use CortexWeb, :router

  import CortexWeb.UserAuth

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, html: {CortexWeb.Layouts, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
    plug :fetch_current_user
  end

  pipeline :api do
    plug :accepts, ["json"]
  end

  # Public routes -- redirect to dashboard if already logged in
  scope "/", CortexWeb do
    pipe_through [:browser, :redirect_if_user_is_authenticated]

    live "/login", Auth.LoginLive, :login
  end

  # Magic link verification + logout (no auth redirect)
  scope "/auth", CortexWeb do
    pipe_through :browser

    live "/magic/:token", Auth.MagicLinkLive, :verify
    get "/magic/:token/callback", UserSessionController, :create
    delete "/logout", UserSessionController, :delete
  end

  # Protected routes
  live_session :authenticated,
    on_mount: [{CortexWeb.Live.UserAuth, :ensure_authenticated}] do
    scope "/", CortexWeb do
      pipe_through :browser

      live "/dashboard", DashboardLive.Index, :index
      live "/onboarding", Onboarding.WizardLive, :index
      live "/settings/projects", Settings.ProjectsLive, :index
      live "/settings/brain", Settings.BrainProfileLive, :index
      live "/settings/billing", Settings.BillingLive, :index
      live "/agent", AgentLive.Index, :index
    end
  end

  # In dev, root goes straight to dashboard
  scope "/", CortexWeb do
    pipe_through :browser

    live "/landing", LandingLive, :index
    get "/", PageController, :home
  end

  # Stripe webhooks — signature verified by StripeWebhookPlug
  pipeline :stripe_webhook do
    plug :accepts, ["json"]
    plug CortexWeb.StripeWebhookPlug
  end

  scope "/webhooks", CortexWeb do
    pipe_through :stripe_webhook

    post "/stripe", StripeWebhookController, :handle
  end

  # Twin API — local only, no auth
  scope "/api", CortexWeb do
    pipe_through :api

    get "/state", TwinApiController, :state
    post "/twin/insight", TwinApiController, :insight
  end
end
