defmodule Cortex.Repo.Migrations.CreateUserProjects do
  use Ecto.Migration

  def change do
    create table(:user_projects, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :user_id, references(:users, type: :binary_id, on_delete: :delete_all)
      add :name, :string, null: false
      add :path, :string, null: false
      add :status, :string, default: "active"
      add :port, :integer
      add :priority_weight, :integer, default: 50
      add :project_type, :string
      add :dev_command, :string
      add :description, :string

      timestamps(type: :utc_datetime)
    end

    create index(:user_projects, [:user_id])
    create unique_index(:user_projects, [:user_id, :name])
  end
end
