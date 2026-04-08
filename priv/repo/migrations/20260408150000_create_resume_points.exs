defmodule Cortex.Repo.Migrations.CreateResumePoints do
  use Ecto.Migration

  def change do
    create table(:resume_points, primary_key: false) do
      add(:id, :binary_id, primary_key: true)
      add(:session_id, :binary_id)
      add(:project_name, :string)
      add(:context, :string, null: false)
      add(:next_action, :string, null: false)
      add(:status, :string, null: false, default: "pending")
      add(:urgency, :string, null: false, default: "normal")

      timestamps(type: :utc_datetime)
    end

    create(index(:resume_points, [:status]))
    create(index(:resume_points, [:inserted_at]))
  end
end
