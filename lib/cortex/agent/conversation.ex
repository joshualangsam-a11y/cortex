defmodule Cortex.Agent.Conversation do
  @moduledoc false
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}

  schema "agent_conversations" do
    field :title, :string
    field :messages, {:array, :map}, default: []
    field :cwd, :string
    field :model, :string
    field :input_tokens, :integer, default: 0
    field :output_tokens, :integer, default: 0

    timestamps(type: :utc_datetime)
  end

  def changeset(conversation, attrs) do
    conversation
    |> cast(attrs, [:title, :messages, :cwd, :model, :input_tokens, :output_tokens])
    |> validate_required([:cwd])
  end
end
