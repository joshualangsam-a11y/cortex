defmodule Cortex.Projects.UserProject do
  @moduledoc """
  Schema for user-configured projects stored in the database.
  Replaces hardcoded CLAUDE.md parsing with user-editable config.
  """

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @statuses ~w(active building maintenance archived)
  @project_types ~w(elixir node python rust go other)

  schema "user_projects" do
    field :user_id, :binary_id
    field :name, :string
    field :path, :string
    field :status, :string, default: "active"
    field :port, :integer
    field :priority_weight, :integer, default: 50
    field :project_type, :string
    field :dev_command, :string
    field :description, :string

    timestamps(type: :utc_datetime)
  end

  def changeset(project, attrs) do
    project
    |> cast(attrs, [
      :name,
      :path,
      :status,
      :port,
      :priority_weight,
      :project_type,
      :dev_command,
      :description,
      :user_id
    ])
    |> validate_required([:name, :path])
    |> validate_inclusion(:status, @statuses)
    |> validate_inclusion(:project_type, @project_types ++ [nil])
    |> validate_number(:priority_weight,
      greater_than_or_equal_to: 1,
      less_than_or_equal_to: 100
    )
    |> validate_number(:port, greater_than: 0)
    |> unique_constraint([:user_id, :name])
  end

  def statuses, do: @statuses
  def project_types, do: @project_types
end
