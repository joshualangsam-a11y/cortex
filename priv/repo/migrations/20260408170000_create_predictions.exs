defmodule Cortex.Repo.Migrations.CreatePredictions do
  use Ecto.Migration

  def change do
    create table(:predictions, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :type, :string, null: false
      add :predicted_at, :utc_datetime, null: false
      add :target_time, :utc_datetime, null: false
      add :prediction_value, :map, default: %{}
      add :actual_outcome, :string
      add :confidence, :float, default: 0.5
      add :scored, :boolean, default: false
      add :scored_at, :utc_datetime
      add :accurate, :boolean

      timestamps(type: :utc_datetime)
    end

    create index(:predictions, [:type])
    create index(:predictions, [:predicted_at])
    create index(:predictions, [:scored])
  end
end
