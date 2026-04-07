defmodule Cortex.Accounts.User do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "users" do
    field :email, :string
    field :name, :string
    field :tier, :string, default: "free"
    field :confirmed_at, :utc_datetime

    timestamps(type: :utc_datetime)
  end

  def registration_changeset(user, attrs) do
    user
    |> cast(attrs, [:email, :name])
    |> validate_required([:email])
    |> validate_format(:email, ~r/^[^\s]+@[^\s]+$/, message: "must be a valid email")
    |> validate_length(:email, max: 160)
    |> unique_constraint(:email)
    |> maybe_confirm()
  end

  def changeset(user, attrs) do
    user
    |> cast(attrs, [:email, :name, :tier])
    |> validate_required([:email])
    |> validate_inclusion(:tier, ["free", "pro", "team"])
    |> unique_constraint(:email)
  end

  defp maybe_confirm(changeset) do
    # Auto-confirm for now (no email verification yet)
    put_change(changeset, :confirmed_at, DateTime.utc_now() |> DateTime.truncate(:second))
  end
end
