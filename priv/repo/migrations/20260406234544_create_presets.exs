defmodule Cortex.Repo.Migrations.CreatePresets do
  use Ecto.Migration

  def change do
    create table(:presets, primary_key: false) do
      add :id, :binary_id, primary_key: true, default: fragment("gen_random_uuid()")
      add :name, :string, null: false
      add :project_name, :string
      add :commands, {:array, :string}, default: []
      add :cwd, :string
      add :auto_execute, :boolean, default: false

      timestamps(type: :utc_datetime)
    end

    create unique_index(:presets, [:name])
  end
end
