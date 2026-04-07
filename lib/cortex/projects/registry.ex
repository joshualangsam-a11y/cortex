defmodule Cortex.Projects.Registry do
  @moduledoc """
  GenServer that parses ~/CLAUDE.md project table at boot.
  Provides project list for the command palette.
  """

  use GenServer

  defmodule Project do
    defstruct [:name, :path, :status, :port]
  end

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, [], name: __MODULE__)
  end

  def list_projects do
    GenServer.call(__MODULE__, :list)
  end

  def get_project(name) do
    GenServer.call(__MODULE__, {:get, name})
  end

  @impl true
  def init(_) do
    projects = parse_claude_md()
    {:ok, %{projects: projects}}
  end

  @impl true
  def handle_call(:list, _from, %{projects: projects} = state) do
    {:reply, projects, state}
  end

  @impl true
  def handle_call({:get, name}, _from, %{projects: projects} = state) do
    project = Enum.find(projects, fn p -> p.name == name end)
    {:reply, project, state}
  end

  defp parse_claude_md do
    path = Path.expand("~/CLAUDE.md")

    case File.read(path) do
      {:ok, content} -> parse_project_table(content)
      {:error, _} -> []
    end
  end

  defp parse_project_table(content) do
    lines = String.split(content, "\n")

    # Find the header row containing "Project" in a table
    header_idx =
      Enum.find_index(lines, fn line ->
        String.starts_with?(String.trim(line), "|") &&
          String.contains?(line, "Project") &&
          String.contains?(line, "Path")
      end)

    case header_idx do
      nil ->
        []

      idx ->
        lines
        # Skip header + separator row
        |> Enum.drop(idx + 2)
        |> Enum.take_while(fn line -> String.starts_with?(String.trim(line), "|") end)
        |> Enum.map(&parse_project_row/1)
        |> Enum.reject(&is_nil/1)
    end
  end

  defp parse_project_row(row) do
    parts =
      row
      |> String.split("|")
      |> Enum.map(&String.trim/1)
      |> Enum.reject(&(&1 == ""))

    case parts do
      [name, path_raw, status, port | _] ->
        path =
          path_raw
          |> String.replace(~r/`/, "")
          |> String.replace("~", System.user_home!())

        port_val =
          case Integer.parse(String.trim(port)) do
            {p, _} -> p
            :error -> nil
          end

        %Project{
          name: String.trim(name),
          path: path,
          status: String.trim(status),
          port: port_val
        }

      _ ->
        nil
    end
  end
end
