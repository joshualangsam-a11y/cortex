defmodule Cortex.Repo.Migrations.CreateLayouts do
  use Ecto.Migration

  def change do
    create table(:layouts, primary_key: false) do
      add :id, :binary_id, primary_key: true, default: fragment("gen_random_uuid()")
      add :name, :string, null: false
      add :grid_cols, :integer, default: 3
      add :session_order, {:array, :string}, default: []
      add :is_default, :boolean, default: false

      timestamps(type: :utc_datetime)
    end
  end
end
