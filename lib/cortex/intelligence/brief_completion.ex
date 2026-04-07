defmodule Cortex.Intelligence.BriefCompletion do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}

  schema "brief_completions" do
    field(:date, :date)
    field(:action_hash, :string)
    field(:section, :string)
    timestamps(type: :utc_datetime)
  end

  def changeset(completion, attrs) do
    completion
    |> cast(attrs, [:date, :action_hash, :section])
    |> validate_required([:date, :action_hash, :section])
    |> unique_constraint([:date, :action_hash])
  end
end
