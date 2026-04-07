defmodule Cortex.Repo.Migrations.CreateWorkspaces do
  use Ecto.Migration

  def change do
    create table(:workspaces, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :name, :string, null: false
      add :description, :string
      add :grid_cols, :integer, default: 3
      add :sessions, {:array, :map}, default: []

      timestamps(type: :utc_datetime)
    end

    create unique_index(:workspaces, [:name])
  end
end
