defmodule Cortex.Agent.Tool do
  @moduledoc false

  @callback name() :: String.t()
  @callback description() :: String.t()
  @callback parameters() :: map()
  @callback execute(params :: map(), context :: map()) :: {:ok, String.t()} | {:error, String.t()}

  @tools [
    Cortex.Agent.Tools.FileRead,
    Cortex.Agent.Tools.FileWrite,
    Cortex.Agent.Tools.FileEdit,
    Cortex.Agent.Tools.Bash,
    Cortex.Agent.Tools.Grep,
    Cortex.Agent.Tools.Glob
  ]

  def all, do: @tools

  @doc "Returns all tools formatted for the Claude API tools parameter."
  def claude_format do
    Enum.map(@tools, fn mod ->
      %{
        name: mod.name(),
        description: mod.description(),
        input_schema: mod.parameters()
      }
    end)
  end

  @doc "Finds a tool module by name string."
  def find(name) do
    Enum.find(@tools, fn mod -> mod.name() == name end)
  end

  @doc "Executes a tool by name with given params and context."
  def execute(name, params, context \\ %{}) do
    case find(name) do
      nil -> {:error, "Unknown tool: #{name}"}
      mod -> mod.execute(params, context)
    end
  end
end
