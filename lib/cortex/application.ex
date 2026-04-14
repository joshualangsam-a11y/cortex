defmodule Cortex.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application
  require Logger

  @impl true
  def start(_type, _args) do
    # Kill orphaned PTY processes that inherited the listening socket fd
    # This prevents :eaddrinuse when restarting after a crash
    kill_orphaned_port_holders()

    children = [
      CortexWeb.Telemetry,
      Cortex.Repo,
      {DNSCluster, query: Application.get_env(:cortex, :dns_cluster_query) || :ignore},
      {Phoenix.PubSub, name: Cortex.PubSub},
      {Registry, keys: :unique, name: Cortex.Terminal.SessionRegistry},
      {DynamicSupervisor, name: Cortex.Terminal.SessionSupervisor, strategy: :one_for_one},
      {Registry, keys: :unique, name: Cortex.Agent.SessionRegistry},
      {DynamicSupervisor, name: Cortex.Agent.SessionSupervisor, strategy: :one_for_one},
      Cortex.Projects.Registry,
      Cortex.Intelligence.Prioritizer,
      Cortex.Intelligence.OutputMonitor,
      Cortex.Intelligence.MomentumEngine,
      Cortex.Intelligence.SessionDNA,
      Cortex.Intelligence.ThermalThrottle,
      Cortex.Intelligence.TokenEconomics,
      Cortex.Intelligence.EntropyDetector,
      # Restores crashed sessions after all dependencies are up
      {Task, &restore_crashed_sessions/0},
      CortexWeb.Endpoint
    ]

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: Cortex.Supervisor]
    Supervisor.start_link(children, opts)
  end

  defp kill_orphaned_port_holders do
    port = Application.get_env(:cortex, CortexWeb.Endpoint)[:http][:port] || 3012

    case System.cmd("lsof", ["-ti:#{port}"], stderr_to_stdout: true) do
      {output, 0} ->
        pids =
          output
          |> String.split("\n", trim: true)
          |> Enum.reject(fn pid_str ->
            # Don't kill our own BEAM process
            String.trim(pid_str) == "#{:os.getpid()}"
          end)

        if pids != [] do
          Logger.warning("Cortex: killing #{length(pids)} orphaned process(es) on port #{port}")

          Enum.each(pids, fn pid_str ->
            System.cmd("kill", ["-9", String.trim(pid_str)], stderr_to_stdout: true)
          end)

          # Brief pause to let OS reclaim the port
          Process.sleep(500)
        end

      _ ->
        :ok
    end
  end

  defp restore_crashed_sessions do
    # Small delay to ensure DynamicSupervisor + Projects.Registry are ready
    Process.sleep(500)

    case Cortex.Terminals.restore_sessions() do
      {:ok, []} ->
        Logger.info("Cortex: no crashed sessions to restore")

      {:ok, restored} ->
        count = length(restored)
        Logger.info("Cortex: restored #{count} session(s) from last crash")
    end
  rescue
    e -> Logger.warning("Cortex: session restore failed: #{inspect(e)}")
  end

  @doc """
  Graceful shutdown: stop all PTY sessions (flushing scrollback) before BEAM exits.
  """
  @impl true
  def prep_stop(state) do
    Logger.info("Cortex: graceful shutdown -- stopping all PTY sessions")

    Cortex.Terminal.SessionSupervisor
    |> DynamicSupervisor.which_children()
    |> Enum.each(fn
      {:undefined, pid, :worker, _} when is_pid(pid) ->
        try do
          GenServer.stop(pid, :shutdown, 5_000)
        catch
          :exit, _ -> :ok
        end

      _ ->
        :ok
    end)

    state
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    CortexWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
