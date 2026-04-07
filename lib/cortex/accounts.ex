defmodule Cortex.Accounts do
  @moduledoc """
  The Accounts context -- users, authentication, sessions, license tiers.
  """

  import Ecto.Query
  alias Cortex.Repo
  alias Cortex.Accounts.{User, UserToken}

  ## User lookup

  def get_user_by_email(email) when is_binary(email) do
    Repo.get_by(User, email: String.downcase(email))
  end

  def get_user!(id), do: Repo.get!(User, id)

  ## Registration

  def register_user(attrs) do
    attrs = normalize_email(attrs)

    %User{}
    |> User.registration_changeset(attrs)
    |> Repo.insert()
  end

  ## Magic link tokens

  def generate_magic_link_token(user) do
    {raw_token, token_struct} = UserToken.build_magic_link_token(user)
    Repo.insert!(token_struct)
    Base.url_encode64(raw_token, padding: false)
  end

  def verify_magic_link_token(encoded_token) do
    with {:ok, raw_token} <- Base.url_decode64(encoded_token, padding: false),
         token_struct when not is_nil(token_struct) <- find_magic_link_token(raw_token),
         true <- token_not_expired?(token_struct) do
      user = Repo.get!(User, token_struct.user_id)
      # Delete used token
      Repo.delete!(token_struct)
      {:ok, user}
    else
      _ -> :error
    end
  end

  defp find_magic_link_token(raw_token) do
    Repo.one(
      from t in UserToken,
        where: t.token == ^raw_token and t.context == "magic_link"
    )
  end

  defp token_not_expired?(token_struct) do
    max_age = UserToken.magic_link_validity_seconds()
    inserted = token_struct.inserted_at

    DateTime.diff(DateTime.utc_now(), inserted, :second) <= max_age
  end

  ## Session tokens

  def generate_session_token(user) do
    {raw_token, token_struct} = UserToken.build_session_token(user)
    Repo.insert!(token_struct)
    raw_token
  end

  def get_user_by_session_token(token) when is_binary(token) do
    query =
      from t in UserToken,
        where: t.token == ^token and t.context == "session",
        join: u in assoc(t, :user),
        select: u

    Repo.one(query)
  end

  def delete_session_token(token) when is_binary(token) do
    Repo.delete_all(
      from t in UserToken,
        where: t.token == ^token and t.context == "session"
    )

    :ok
  end

  ## Tier helpers

  def pro?(%User{tier: tier}), do: tier in ["pro", "team"]
  def pro?(_), do: false

  ## Private

  defp normalize_email(%{"email" => email} = attrs) do
    Map.put(attrs, "email", String.downcase(String.trim(email)))
  end

  defp normalize_email(%{email: email} = attrs) do
    Map.put(attrs, :email, String.downcase(String.trim(email)))
  end

  defp normalize_email(attrs), do: attrs
end
