defmodule Cortex.Terminals.Preset do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}

  schema "presets" do
    field :name, :string
    field :project_name, :string
    field :commands, {:array, :string}, default: []
    field :cwd, :string
    field :auto_execute, :boolean, default: false

    timestamps(type: :utc_datetime)
  end

  def changeset(preset, attrs) do
    preset
    |> cast(attrs, [:name, :project_name, :commands, :cwd, :auto_execute])
    |> validate_required([:name])
    |> unique_constraint(:name)
  end
end
