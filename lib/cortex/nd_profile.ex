defmodule Cortex.NDProfile do
  @moduledoc """
  Neurodivergent Profile: the user's cognitive configuration.

  Every brain is different. This module lets users configure their
  neurodivergent profile so Cortex adapts to THEIR brain, not a
  neurotypical default.

  This is the moat: no other terminal tool asks "when does your brain
  peak?" or "how many parallel tracks can you run?" or "what does
  your wall signal feel like?"

  Default profile is Josh's (the founder's) — ADHD + Dyslexia optimized.
  Users can customize from settings.

  ## Profile Dimensions

  1. **Thinking Style**: parallel, linear, or mixed
  2. **Energy Cycle**: custom peak/mud hours
  3. **Flow Triggers**: what velocity/duration triggers flow detection
  4. **Wall Signals**: what patterns indicate cognitive overload
  5. **Parallel Capacity**: how many concurrent threads this brain handles
  6. **Context Switch Cost**: how expensive is a context switch (low/medium/high)
  7. **Interruption Tolerance**: how aggressively to guard flow
  """

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "nd_profiles" do
    belongs_to :user, Cortex.Accounts.User

    # Thinking style
    field :thinking_style, :string, default: "parallel"
    field :parallel_capacity, :integer, default: 6

    # Energy cycle (hours in local time)
    field :mud_start, :integer, default: 6
    field :mud_end, :integer, default: 11
    field :peak_start, :integer, default: 14
    field :peak_end, :integer, default: 22

    # Flow detection tuning
    field :flow_velocity_threshold, :integer, default: 15
    field :flow_sustain_seconds, :integer, default: 30
    field :flow_cooldown_seconds, :integer, default: 15

    # Context switch
    field :context_switch_cost, :string, default: "high"
    field :interruption_tolerance, :string, default: "low"

    # Thermal throttle tuning
    field :error_spike_threshold, :integer, default: 5
    field :marathon_hours_threshold, :integer, default: 4

    # Personalization
    field :wall_signal, :string, default: "headache"
    field :flow_signal, :string, default: "full-body resonance"
    field :focus_sound, :string, default: "house music"

    timestamps(type: :utc_datetime)
  end

  @fields [
    :thinking_style,
    :parallel_capacity,
    :mud_start,
    :mud_end,
    :peak_start,
    :peak_end,
    :flow_velocity_threshold,
    :flow_sustain_seconds,
    :flow_cooldown_seconds,
    :context_switch_cost,
    :interruption_tolerance,
    :error_spike_threshold,
    :marathon_hours_threshold,
    :wall_signal,
    :flow_signal,
    :focus_sound
  ]

  def changeset(profile, attrs) do
    profile
    |> cast(attrs, @fields ++ [:user_id])
    |> validate_inclusion(:thinking_style, ["parallel", "linear", "mixed"])
    |> validate_inclusion(:context_switch_cost, ["low", "medium", "high"])
    |> validate_inclusion(:interruption_tolerance, ["low", "medium", "high"])
    |> validate_number(:parallel_capacity, greater_than: 0, less_than_or_equal_to: 20)
    |> validate_number(:flow_velocity_threshold, greater_than: 0)
    |> validate_number(:mud_start, greater_than_or_equal_to: 0, less_than: 24)
    |> validate_number(:mud_end, greater_than_or_equal_to: 0, less_than: 24)
    |> validate_number(:peak_start, greater_than_or_equal_to: 0, less_than: 24)
    |> validate_number(:peak_end, greater_than_or_equal_to: 0, less_than: 24)
  end

  @doc """
  Load the current user's ND profile, or return default.
  Cached in process dictionary to avoid repeated DB hits.
  """
  def current do
    case Process.get(:nd_profile_cache) do
      nil ->
        profile = load_from_db() || default()
        Process.put(:nd_profile_cache, profile)
        profile

      cached ->
        cached
    end
  end

  @doc "Force reload from DB (after settings change)."
  def reload do
    Process.delete(:nd_profile_cache)
    current()
  end

  defp load_from_db do
    import Ecto.Query

    __MODULE__
    |> order_by(desc: :updated_at)
    |> limit(1)
    |> Cortex.Repo.one()
  rescue
    _ -> nil
  end

  @doc "Get or create a profile for a user. Used by settings page."
  def get_or_create_for_user(user_id) do
    import Ecto.Query

    case __MODULE__ |> where(user_id: ^user_id) |> Cortex.Repo.one() do
      nil ->
        %__MODULE__{}
        |> changeset(%{user_id: user_id})
        |> Cortex.Repo.insert()

      profile ->
        {:ok, profile}
    end
  end

  @doc "Update a profile with new attrs. Clears cache."
  def update_profile(%__MODULE__{} = profile, attrs) do
    result =
      profile
      |> changeset(attrs)
      |> Cortex.Repo.update()

    case result do
      {:ok, _} -> reload()
      _ -> :ok
    end

    result
  end

  @doc "Apply a preset to a profile."
  def apply_preset(%__MODULE__{} = profile, preset_key) do
    case Map.get(presets(), preset_key) do
      nil -> {:error, :unknown_preset}
      preset -> update_profile(profile, preset.profile)
    end
  end

  @doc """
  The default profile — optimized for ADHD + Dyslexia.
  Based on Josh's brain map: parallel bursts, high context switch cost,
  peak afternoon/night, mud mornings, headache as wall signal.
  """
  def default do
    %__MODULE__{
      thinking_style: "parallel",
      parallel_capacity: 10,
      mud_start: 6,
      mud_end: 11,
      peak_start: 14,
      peak_end: 22,
      flow_velocity_threshold: 15,
      flow_sustain_seconds: 30,
      flow_cooldown_seconds: 15,
      context_switch_cost: "high",
      interruption_tolerance: "low",
      error_spike_threshold: 5,
      marathon_hours_threshold: 4,
      wall_signal: "headache",
      flow_signal: "full-body resonance",
      focus_sound: "house music"
    }
  end

  @doc "Common ND presets for onboarding."
  def presets do
    %{
      "adhd_parallel" => %{
        name: "ADHD — Parallel Processor",
        description: "Multiple threads, high context-switch cost, burst energy",
        profile: %{
          thinking_style: "parallel",
          parallel_capacity: 8,
          context_switch_cost: "high",
          interruption_tolerance: "low",
          flow_velocity_threshold: 15,
          flow_sustain_seconds: 30
        }
      },
      "adhd_hyperfocus" => %{
        name: "ADHD — Hyperfocuser",
        description: "Deep single-track, very high context-switch cost, long flow states",
        profile: %{
          thinking_style: "linear",
          parallel_capacity: 3,
          context_switch_cost: "high",
          interruption_tolerance: "low",
          flow_velocity_threshold: 10,
          flow_sustain_seconds: 20,
          marathon_hours_threshold: 6
        }
      },
      "autism_systematic" => %{
        name: "Autism — Systematic Builder",
        description: "Deep patterns, routine-dependent, high detail sensitivity",
        profile: %{
          thinking_style: "linear",
          parallel_capacity: 4,
          context_switch_cost: "high",
          interruption_tolerance: "low",
          flow_velocity_threshold: 8,
          flow_sustain_seconds: 20
        }
      },
      "dyslexia_visual" => %{
        name: "Dyslexia — Visual-Spatial",
        description: "Pattern matching, spatial intuition, vision-articulation gap",
        profile: %{
          thinking_style: "parallel",
          parallel_capacity: 6,
          context_switch_cost: "medium",
          interruption_tolerance: "medium"
        }
      },
      "neurotypical" => %{
        name: "Neurotypical",
        description: "Standard defaults — but try parallel mode, you might like it",
        profile: %{
          thinking_style: "mixed",
          parallel_capacity: 4,
          context_switch_cost: "medium",
          interruption_tolerance: "medium",
          flow_velocity_threshold: 20,
          flow_sustain_seconds: 45
        }
      }
    }
  end
end
