defmodule Cortex.Terminals.BurstMode do
  @moduledoc """
  Burst Mode: instant parallel context for neurodivergent brains.

  One keypress spawns a full project context — server, tests, agent, git log —
  all at once. Designed for brains that need all threads running simultaneously.

  "Your brain doesn't think in one thread. Neither should your terminal."
  """

  alias Cortex.Terminals
  alias Cortex.Projects

  @doc """
  Launch burst mode for a project.

  Detects project type and spawns the right set of terminals:
  - Elixir/Phoenix: server, iex, tests, claude agent
  - Next.js: dev server, tests, claude agent
  - Generic: shell, claude agent
  """
  def launch(project_name) do
    case Projects.get_project(project_name) do
      nil -> {:error, :project_not_found}
      project -> launch_project(project)
    end
  end

  @doc "Launch burst mode from a project struct."
  def launch_project(project) do
    sessions = burst_config(project)

    results =
      Enum.map(sessions, fn config ->
        Terminals.create_session(%{
          project: project,
          title: config.title,
          auto_command: config.command
        })
      end)

    {:ok, results}
  end

  @doc "Get the burst config for a project (what sessions would be spawned)."
  def burst_config(project) do
    type = detect_type(project.path)
    base_sessions = sessions_for_type(type, project)

    # Always include a Claude agent session
    base_sessions ++ [%{title: "#{project.name} agent", command: "claude"}]
  end

  defp detect_type(path) do
    cond do
      File.exists?(Path.join(path, "mix.exs")) -> :elixir
      File.exists?(Path.join(path, "package.json")) -> detect_js_type(path)
      File.exists?(Path.join(path, "Cargo.toml")) -> :rust
      File.exists?(Path.join(path, "go.mod")) -> :go
      File.exists?(Path.join(path, "requirements.txt")) -> :python
      File.exists?(Path.join(path, "Gemfile")) -> :ruby
      true -> :generic
    end
  end

  defp detect_js_type(path) do
    case File.read(Path.join(path, "package.json")) do
      {:ok, content} ->
        cond do
          content =~ "next" -> :nextjs
          content =~ "expo" -> :expo
          content =~ "react" -> :react
          content =~ "vite" -> :vite
          true -> :node
        end

      _ ->
        :node
    end
  end

  defp sessions_for_type(:elixir, project) do
    [
      %{title: "#{project.name} server", command: "mix phx.server"},
      %{title: "#{project.name} iex", command: "iex -S mix"},
      %{title: "#{project.name} test", command: "mix test --watch"}
    ]
  end

  defp sessions_for_type(:nextjs, project) do
    [
      %{title: "#{project.name} dev", command: "npm run dev"},
      %{title: "#{project.name} shell", command: nil}
    ]
  end

  defp sessions_for_type(:expo, project) do
    [
      %{title: "#{project.name} start", command: "npx expo start"},
      %{title: "#{project.name} shell", command: nil}
    ]
  end

  defp sessions_for_type(:vite, project) do
    [
      %{title: "#{project.name} dev", command: "npm run dev"},
      %{title: "#{project.name} shell", command: nil}
    ]
  end

  defp sessions_for_type(:rust, project) do
    [
      %{title: "#{project.name} watch", command: "cargo watch -x run"},
      %{title: "#{project.name} shell", command: nil}
    ]
  end

  defp sessions_for_type(:python, project) do
    [
      %{title: "#{project.name} shell", command: nil},
      %{title: "#{project.name} run", command: "python main.py"}
    ]
  end

  defp sessions_for_type(_, project) do
    [
      %{title: "#{project.name} shell", command: nil}
    ]
  end
end
