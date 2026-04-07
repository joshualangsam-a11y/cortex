defmodule Cortex.Projects do
  @moduledoc """
  Context for project registry and presets.
  """

  alias Cortex.Projects.Registry

  defdelegate list_projects, to: Registry
  defdelegate get_project(name), to: Registry

  def active_projects do
    list_projects()
    |> Enum.filter(fn p -> p.status in ["ACTIVE", "BUILDING"] end)
  end
end
