defmodule Cortex.Repo.Migrations.CreateFlowSessions do
  use Ecto.Migration

  def change do
    create table(:flow_sessions, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :started_at, :utc_datetime, null: false
      add :ended_at, :utc_datetime
      add :duration_seconds, :integer
      add :peak_velocity, :integer, default: 0
      add :active_sessions, :integer, default: 0

      timestamps(type: :utc_datetime)
    end

    create index(:flow_sessions, [:started_at])
  end
end
