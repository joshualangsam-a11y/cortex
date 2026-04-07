defmodule Cortex.Terminal.SessionServer do
  @moduledoc """
  GenServer managing a single PTY terminal session.
  Wraps ExPTY, buffers scrollback, broadcasts output via PubSub.
  """

  use GenServer, restart: :temporary
  require Logger

  alias Cortex.Terminal.Scrollback

  defstruct [
    :id,
    :pty_pid,
    :cols,
    :rows,
    :cwd,
    :command,
    :project,
    :scrollback,
    :status,
    :exit_code,
    :started_at,
    :title
  ]

  # Client API

  def start_link(opts) do
    id = Keyword.fetch!(opts, :id)
    GenServer.start_link(__MODULE__, opts, name: via(id))
  end

  def write(id, data) do
    GenServer.call(via(id), {:write, data})
  end

  def resize(id, cols, rows) do
    GenServer.call(via(id), {:resize, cols, rows})
  end

  def kill_session(id) do
    GenServer.call(via(id), :kill)
  end

  def get_scrollback(id) do
    GenServer.call(via(id), :get_scrollback)
  end

  def get_state(id) do
    GenServer.call(via(id), :get_state)
  end

  defp via(id) do
    {:via, Registry, {Cortex.Terminal.SessionRegistry, id}}
  end

  # Flush scrollback to disk every 30 seconds
  @flush_interval_ms 30_000

  # Server callbacks

  @impl true
  def init(opts) do
    id = Keyword.fetch!(opts, :id)
    cwd = Keyword.get(opts, :cwd, System.user_home!())
    cols = Keyword.get(opts, :cols, 80)
    rows = Keyword.get(opts, :rows, 24)
    shell = Keyword.get(opts, :command, System.get_env("SHELL") || "/bin/zsh")
    project = Keyword.get(opts, :project)
    title = Keyword.get(opts, :title, project_title(project))

    session_pid = self()

    on_data = fn _module, _pty_pid, data ->
      send(session_pid, {:pty_data, data})
    end

    on_exit = fn _module, _pty_pid, exit_code, signal ->
      send(session_pid, {:pty_exit, exit_code, signal})
    end

    effective_cwd = if project, do: project.path, else: cwd

    env =
      System.get_env()
      |> Map.put("TERM", "xterm-256color")
      |> Map.put("LANG", "en_US.UTF-8")
      |> Map.put("LC_ALL", "en_US.UTF-8")

    # Restore scrollback from disk if available
    scrollback =
      case Scrollback.load_from_disk(id) do
        nil ->
          Scrollback.new()

        data ->
          Logger.info("Restored scrollback from disk for session #{id}")
          Scrollback.new() |> Scrollback.push(data)
      end

    case ExPTY.spawn(shell, [],
           cols: cols,
           rows: rows,
           cwd: effective_cwd,
           name: "xterm-256color",
           env: env,
           on_data: on_data,
           on_exit: on_exit
         ) do
      {:ok, pty_pid} ->
        # Schedule periodic scrollback flush
        schedule_flush()

        state = %__MODULE__{
          id: id,
          pty_pid: pty_pid,
          cols: cols,
          rows: rows,
          cwd: effective_cwd,
          command: shell,
          project: project,
          scrollback: scrollback,
          status: :running,
          exit_code: nil,
          started_at: DateTime.utc_now(),
          title: title
        }

        Phoenix.PubSub.broadcast(
          Cortex.PubSub,
          "terminal:sessions",
          {:session_started, id, session_info(state)}
        )

        {:ok, state}

      {:error, reason} ->
        {:stop, reason}
    end
  end

  @impl true
  def handle_call({:write, data}, _from, %{status: :running, pty_pid: pty_pid} = state) do
    result = ExPTY.write(pty_pid, data)
    {:reply, result, state}
  end

  def handle_call({:write, _data}, _from, state) do
    {:reply, {:error, :not_running}, state}
  end

  @impl true
  def handle_call({:resize, cols, rows}, _from, %{status: :running, pty_pid: pty_pid} = state) do
    ExPTY.resize(pty_pid, cols, rows)
    {:reply, :ok, %{state | cols: cols, rows: rows}}
  end

  def handle_call({:resize, cols, rows}, _from, state) do
    {:reply, :ok, %{state | cols: cols, rows: rows}}
  end

  @impl true
  def handle_call(:kill, _from, %{status: :running, pty_pid: pty_pid} = state) do
    ExPTY.kill(pty_pid, 15)

    Process.send_after(self(), :force_kill, 3000)
    {:reply, :ok, state}
  end

  def handle_call(:kill, _from, state) do
    {:reply, :ok, state}
  end

  @impl true
  def handle_call(:get_scrollback, _from, state) do
    {:reply, Scrollback.to_binary(state.scrollback), state}
  end

  @impl true
  def handle_call(:get_state, _from, state) do
    {:reply, session_info(state), state}
  end

  @impl true
  def handle_info({:pty_data, data}, state) do
    scrollback = Scrollback.push(state.scrollback, data)

    Phoenix.PubSub.broadcast(
      Cortex.PubSub,
      "terminal:#{state.id}:output",
      {:terminal_output, state.id, data}
    )

    {:noreply, %{state | scrollback: scrollback}}
  end

  @impl true
  def handle_info({:pty_exit, exit_code, _signal}, state) do
    Logger.info("Terminal session #{state.id} exited with code #{exit_code}")

    # Persist exit status to DB for crash recovery
    Cortex.Terminals.mark_exited(state.id, exit_code)

    Phoenix.PubSub.broadcast(
      Cortex.PubSub,
      "terminal:sessions",
      {:session_exited, state.id, exit_code}
    )

    {:noreply, %{state | status: :exited, exit_code: exit_code}}
  end

  @impl true
  def handle_info(:force_kill, %{status: :running, pty_pid: pty_pid} = state) do
    ExPTY.kill(pty_pid, 9)
    {:noreply, state}
  end

  def handle_info(:force_kill, state), do: {:noreply, state}

  @impl true
  def handle_info(:flush_scrollback, state) do
    flush_scrollback_to_disk(state)
    schedule_flush()
    {:noreply, state}
  end

  @impl true
  def terminate(_reason, %{pty_pid: pty_pid} = state) when not is_nil(pty_pid) do
    # Flush scrollback one final time before exit
    flush_scrollback_to_disk(state)
    # Always try to kill the PTY, regardless of status
    ExPTY.kill(pty_pid, 9)
    :ok
  end

  def terminate(_reason, state) do
    flush_scrollback_to_disk(state)
    :ok
  end

  defp session_info(state) do
    %{
      id: state.id,
      title: state.title,
      status: state.status,
      project: state.project,
      cwd: state.cwd,
      cols: state.cols,
      rows: state.rows,
      exit_code: state.exit_code,
      started_at: state.started_at
    }
  end

  defp project_title(nil), do: "terminal"
  defp project_title(%{name: name}), do: name

  defp schedule_flush do
    Process.send_after(self(), :flush_scrollback, @flush_interval_ms)
  end

  defp flush_scrollback_to_disk(%{id: id, scrollback: scrollback}) do
    Scrollback.save_to_disk(scrollback, id)
  rescue
    e -> Logger.warning("Failed to flush scrollback for #{id}: #{inspect(e)}")
  end
end
