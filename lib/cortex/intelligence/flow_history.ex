defmodule Cortex.Intelligence.FlowHistory do
  @moduledoc """
  Tracks flow sessions over time. Not gamification — evidence.

  When self-doubt hits, this module has the receipts:
  "You've logged 14 hours of deep flow this week across 23 sessions."

  Based on brain map insight: when self-doubt appears, point to
  concrete evidence (145 systems, the paper, recovery arc).
  """

  use Ecto.Schema
  import Ecto.Changeset
  import Ecto.Query

  alias Cortex.Repo

  @primary_key {:id, :binary_id, autogenerate: true}

  schema "flow_sessions" do
    field :started_at, :utc_datetime
    field :ended_at, :utc_datetime
    field :duration_seconds, :integer
    field :peak_velocity, :integer, default: 0
    field :active_sessions, :integer, default: 0

    timestamps(type: :utc_datetime)
  end

  def changeset(flow_session, attrs) do
    flow_session
    |> cast(attrs, [:started_at, :ended_at, :duration_seconds, :peak_velocity, :active_sessions])
    |> validate_required([:started_at])
  end

  @doc "Record the start of a flow session."
  def start_flow(peak_velocity, active_sessions) do
    %__MODULE__{}
    |> changeset(%{
      started_at: DateTime.utc_now(),
      peak_velocity: peak_velocity,
      active_sessions: active_sessions
    })
    |> Repo.insert()
  end

  @doc "Record the end of the most recent open flow session."
  def end_flow(peak_velocity) do
    case current_flow() do
      nil ->
        {:error, :no_active_flow}

      flow ->
        now = DateTime.utc_now()
        duration = DateTime.diff(now, flow.started_at, :second)

        flow
        |> changeset(%{
          ended_at: now,
          duration_seconds: duration,
          peak_velocity: max(flow.peak_velocity, peak_velocity)
        })
        |> Repo.update()
    end
  end

  @doc "Get the current open flow session (if any)."
  def current_flow do
    __MODULE__
    |> where([f], is_nil(f.ended_at))
    |> order_by([f], desc: f.started_at)
    |> limit(1)
    |> Repo.one()
  end

  @doc "Get flow stats for today."
  def today_stats do
    today_start = Date.utc_today() |> DateTime.new!(~T[00:00:00], "Etc/UTC")

    flows =
      __MODULE__
      |> where([f], f.started_at >= ^today_start)
      |> Repo.all()

    completed = Enum.filter(flows, & &1.duration_seconds)

    %{
      sessions: length(flows),
      total_minutes: completed |> Enum.map(& &1.duration_seconds) |> Enum.sum() |> div(60),
      longest_minutes:
        case completed do
          [] -> 0
          list -> list |> Enum.map(& &1.duration_seconds) |> Enum.max() |> div(60)
        end,
      peak_velocity:
        case flows do
          [] -> 0
          list -> list |> Enum.map(& &1.peak_velocity) |> Enum.max()
        end
    }
  end

  @doc "Get flow stats for this week."
  def week_stats do
    # Monday of current week
    today = Date.utc_today()
    day_of_week = Date.day_of_week(today)
    monday = Date.add(today, -(day_of_week - 1))
    week_start = DateTime.new!(monday, ~T[00:00:00], "Etc/UTC")

    flows =
      __MODULE__
      |> where([f], f.started_at >= ^week_start and not is_nil(f.duration_seconds))
      |> Repo.all()

    total_seconds = flows |> Enum.map(& &1.duration_seconds) |> Enum.sum()

    %{
      sessions: length(flows),
      total_hours: Float.round(total_seconds / 3600, 1),
      avg_session_minutes:
        case flows do
          [] -> 0
          list -> list |> Enum.map(& &1.duration_seconds) |> Enum.sum() |> div(length(list) * 60)
        end,
      peak_velocity:
        case flows do
          [] -> 0
          list -> list |> Enum.map(& &1.peak_velocity) |> Enum.max()
        end,
      streak: count_streak()
    }
  end

  @doc "Count consecutive days with at least one flow session."
  def count_streak do
    today = Date.utc_today()
    count_streak_days(today, 0)
  end

  defp count_streak_days(date, count) do
    day_start = DateTime.new!(date, ~T[00:00:00], "Etc/UTC")
    day_end = DateTime.new!(date, ~T[23:59:59], "Etc/UTC")

    has_flow =
      __MODULE__
      |> where([f], f.started_at >= ^day_start and f.started_at <= ^day_end)
      |> where([f], not is_nil(f.duration_seconds))
      |> Repo.exists?()

    if has_flow do
      count_streak_days(Date.add(date, -1), count + 1)
    else
      count
    end
  end
end
