defmodule Cortex.Repo.Migrations.CreateNdProfiles do
  use Ecto.Migration

  def change do
    create table(:nd_profiles, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :user_id, references(:users, type: :binary_id, on_delete: :delete_all)

      # Thinking style
      add :thinking_style, :string, null: false, default: "parallel"
      add :parallel_capacity, :integer, null: false, default: 6

      # Energy cycle
      add :mud_start, :integer, null: false, default: 6
      add :mud_end, :integer, null: false, default: 11
      add :peak_start, :integer, null: false, default: 14
      add :peak_end, :integer, null: false, default: 22

      # Flow detection
      add :flow_velocity_threshold, :integer, null: false, default: 15
      add :flow_sustain_seconds, :integer, null: false, default: 30
      add :flow_cooldown_seconds, :integer, null: false, default: 15

      # Context switch
      add :context_switch_cost, :string, null: false, default: "high"
      add :interruption_tolerance, :string, null: false, default: "low"

      # Thermal throttle
      add :error_spike_threshold, :integer, null: false, default: 5
      add :marathon_hours_threshold, :integer, null: false, default: 4

      # Personal signals
      add :wall_signal, :string, default: "headache"
      add :flow_signal, :string, default: "full-body resonance"
      add :focus_sound, :string, default: "house music"

      timestamps(type: :utc_datetime)
    end

    create unique_index(:nd_profiles, [:user_id])
  end
end
