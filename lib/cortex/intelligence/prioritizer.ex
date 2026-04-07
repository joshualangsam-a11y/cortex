defmodule Cortex.Intelligence.Prioritizer do
  @moduledoc """
  GenServer that periodically scans all projects and maintains
  a ranked list of what Josh should work on next.

  Broadcasts updates via PubSub so the dashboard stays live.
  """

  use GenServer

  alias Cortex.Intelligence.Scanner
  alias Cortex.Projects.Registry, as: ProjectRegistry

  @scan_interval :timer.minutes(5)
  @topic "intelligence:priorities"

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, [], name: __MODULE__)
  end

  @doc "Returns all scanned projects sorted by score descending."
  def ranked do
    GenServer.call(__MODULE__, :ranked)
  end

  @doc "Returns top N actionable items (projects with a non-nil action)."
  def top_actions(n \\ 3) do
    GenServer.call(__MODULE__, {:top_actions, n})
  end

  @doc "Force a rescan now."
  def refresh do
    GenServer.cast(__MODULE__, :refresh)
  end

  def topic, do: @topic

  # Server

  @impl true
  def init(_) do
    send(self(), :scan)
    {:ok, %{results: [], last_scanned_at: nil}}
  end

  @impl true
  def handle_call(:ranked, _from, %{results: results} = state) do
    {:reply, results, state}
  end

  def handle_call({:top_actions, n}, _from, %{results: results} = state) do
    actions =
      results
      |> Enum.filter(& &1.top_action)
      |> Enum.take(n)

    {:reply, actions, state}
  end

  @impl true
  def handle_cast(:refresh, state) do
    state = do_scan(state)
    {:noreply, state}
  end

  @impl true
  def handle_info(:scan, state) do
    state = do_scan(state)
    schedule_scan()
    {:noreply, state}
  end

  defp do_scan(state) do
    projects = ProjectRegistry.list_projects()
    results = Scanner.scan_all(projects)

    Phoenix.PubSub.broadcast(Cortex.PubSub, @topic, {:priorities_updated, results})

    %{state | results: results, last_scanned_at: DateTime.utc_now()}
  end

  defp schedule_scan do
    Process.send_after(self(), :scan, @scan_interval)
  end
end
