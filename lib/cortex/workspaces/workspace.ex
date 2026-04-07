defmodule Cortex.Workspaces.Workspace do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}

  schema "workspaces" do
    field :name, :string
    field :description, :string
    field :grid_cols, :integer, default: 3
    field :sessions, {:array, :map}, default: []

    timestamps(type: :utc_datetime)
  end

  def changeset(workspace, attrs) do
    workspace
    |> cast(attrs, [:name, :description, :grid_cols, :sessions])
    |> validate_required([:name])
    |> validate_number(:grid_cols, greater_than: 0, less_than_or_equal_to: 4)
    |> unique_constraint(:name)
  end
end
