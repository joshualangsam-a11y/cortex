defmodule Cortex.Agent.Conversations do
  @moduledoc false

  import Ecto.Query
  alias Cortex.Repo
  alias Cortex.Agent.Conversation

  def list_recent(limit \\ 20) do
    Conversation
    |> order_by(desc: :updated_at)
    |> limit(^limit)
    |> Repo.all()
  end

  def get(id) do
    Repo.get(Conversation, id)
  end

  def create(attrs) do
    %Conversation{}
    |> Conversation.changeset(attrs)
    |> Repo.insert()
  end

  def save(id, attrs) do
    case Repo.get(Conversation, id) do
      nil ->
        %Conversation{id: id}
        |> Conversation.changeset(attrs)
        |> Repo.insert(on_conflict: {:replace_all_except, [:id, :inserted_at]}, conflict_target: :id)

      conversation ->
        conversation
        |> Conversation.changeset(attrs)
        |> Repo.update()
    end
  end

  def delete(id) do
    case Repo.get(Conversation, id) do
      nil -> {:error, :not_found}
      conv -> Repo.delete(conv)
    end
  end

  def generate_title(messages) do
    case Enum.find(messages, &(&1["role"] == "user")) do
      %{"content" => content} when is_binary(content) ->
        content |> String.slice(0, 60) |> String.trim()

      _ ->
        "New conversation"
    end
  end
end
