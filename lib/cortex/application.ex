defmodule Cortex.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      CortexWeb.Telemetry,
      Cortex.Repo,
      {DNSCluster, query: Application.get_env(:cortex, :dns_cluster_query) || :ignore},
      {Phoenix.PubSub, name: Cortex.PubSub},
      {Registry, keys: :unique, name: Cortex.Terminal.SessionRegistry},
      {DynamicSupervisor, name: Cortex.Terminal.SessionSupervisor, strategy: :one_for_one},
      Cortex.Projects.Registry,
      CortexWeb.Endpoint
    ]

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: Cortex.Supervisor]
    Supervisor.start_link(children, opts)
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    CortexWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
