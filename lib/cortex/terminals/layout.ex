defmodule Cortex.Terminals.Layout do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}

  schema "layouts" do
    field :name, :string
    field :grid_cols, :integer, default: 3
    field :session_order, {:array, :string}, default: []
    field :is_default, :boolean, default: false

    timestamps(type: :utc_datetime)
  end

  def changeset(layout, attrs) do
    layout
    |> cast(attrs, [:name, :grid_cols, :session_order, :is_default])
    |> validate_required([:name])
    |> validate_number(:grid_cols, greater_than: 0, less_than_or_equal_to: 4)
  end
end
