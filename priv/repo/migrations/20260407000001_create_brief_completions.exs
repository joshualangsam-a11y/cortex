defmodule Cortex.Repo.Migrations.CreateBriefCompletions do
  use Ecto.Migration

  def change do
    create table(:brief_completions, primary_key: false) do
      add(:id, :binary_id, primary_key: true, default: fragment("gen_random_uuid()"))
      add(:date, :date, null: false)
      add(:action_hash, :string, null: false)
      add(:section, :string, null: false)
      timestamps(type: :utc_datetime)
    end

    create(unique_index(:brief_completions, [:date, :action_hash]))
    create(index(:brief_completions, [:date]))
  end
end
