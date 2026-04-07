defmodule CortexWeb.Router do
  use CortexWeb, :router

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, html: {CortexWeb.Layouts, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
  end

  pipeline :api do
    plug :accepts, ["json"]
  end

  scope "/", CortexWeb do
    pipe_through :browser

    live "/", DashboardLive.Index, :index
  end

  # Other scopes may use custom stacks.
  # scope "/api", CortexWeb do
  #   pipe_through :api
  # end
end
