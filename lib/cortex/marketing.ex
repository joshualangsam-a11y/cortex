defmodule Cortex.Marketing do
  @moduledoc """
  Marketing context -- waitlist management.
  """

  alias Cortex.Repo
  alias Cortex.Marketing.WaitlistEntry

  def join_waitlist(email, source \\ "landing") do
    %WaitlistEntry{}
    |> WaitlistEntry.changeset(%{email: String.downcase(String.trim(email)), source: source})
    |> Repo.insert()
  end

  def waitlist_count do
    Repo.aggregate(WaitlistEntry, :count)
  end
end
