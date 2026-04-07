defmodule Cortex.Repo.Migrations.CreateTerminalSessions do
  use Ecto.Migration

  def change do
    create table(:terminal_sessions, primary_key: false) do
      add :id, :binary_id, primary_key: true, default: fragment("gen_random_uuid()")
      add :title, :string
      add :command, :string, default: "/bin/zsh"
      add :cwd, :string
      add :project_name, :string
      add :status, :string, default: "running"
      add :exit_code, :integer
      add :cols, :integer, default: 120
      add :rows, :integer, default: 30
      add :started_at, :utc_datetime
      add :exited_at, :utc_datetime

      timestamps(type: :utc_datetime)
    end

    create index(:terminal_sessions, [:status])
    create index(:terminal_sessions, [:project_name])
  end
end
