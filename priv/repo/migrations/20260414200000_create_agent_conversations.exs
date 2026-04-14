defmodule Cortex.Repo.Migrations.CreateAgentConversations do
  use Ecto.Migration

  def change do
    create table(:agent_conversations, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :title, :string
      add :messages, :jsonb, default: "[]"
      add :cwd, :string
      add :model, :string
      add :input_tokens, :integer, default: 0
      add :output_tokens, :integer, default: 0

      timestamps(type: :utc_datetime)
    end

    create index(:agent_conversations, [:updated_at])
  end
end
