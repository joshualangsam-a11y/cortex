defmodule Cortex.Accounts.UserToken do
  use Ecto.Schema

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @magic_link_validity_seconds 10 * 60

  schema "user_tokens" do
    field :token, :binary
    field :context, :string
    field :sent_to, :string

    belongs_to :user, Cortex.Accounts.User

    timestamps(type: :utc_datetime, updated_at: false)
  end

  def magic_link_validity_seconds, do: @magic_link_validity_seconds

  @doc """
  Builds a token for magic link authentication.
  """
  def build_magic_link_token(user) do
    token = :crypto.strong_rand_bytes(32)

    {token,
     %__MODULE__{
       token: token,
       context: "magic_link",
       sent_to: user.email,
       user_id: user.id
     }}
  end

  @doc """
  Builds a session token.
  """
  def build_session_token(user) do
    token = :crypto.strong_rand_bytes(32)

    {token,
     %__MODULE__{
       token: token,
       context: "session",
       user_id: user.id
     }}
  end
end
