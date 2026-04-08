defmodule CortexWeb.Settings.BrainProfileLive do
  use CortexWeb, :live_view

  import CortexWeb.Settings.SettingsLayout

  alias Cortex.NDProfile
  alias Cortex.Intelligence.FlowCalibrator

  @impl true
  def mount(_params, _session, socket) do
    user_id = socket.assigns.current_user.id
    {:ok, profile} = NDProfile.get_or_create_for_user(user_id)
    calibration = safe_calibration()

    socket =
      socket
      |> assign(:page_title, "Brain Profile")
      |> assign(:profile, profile)
      |> assign(:changeset, NDProfile.changeset(profile, %{}))
      |> assign(:presets, NDProfile.presets())
      |> assign(:calibration, calibration)
      |> assign(:saved, false)

    {:ok, socket}
  end

  @impl true
  def handle_event("select_preset", %{"key" => key}, socket) do
    case NDProfile.apply_preset(socket.assigns.profile, key) do
      {:ok, updated} ->
        {:noreply,
         socket
         |> assign(:profile, updated)
         |> assign(:changeset, NDProfile.changeset(updated, %{}))
         |> assign(:saved, true)}

      _ ->
        {:noreply, socket}
    end
  end

  def handle_event("save", %{"nd_profile" => params}, socket) do
    case NDProfile.update_profile(socket.assigns.profile, params) do
      {:ok, updated} ->
        {:noreply,
         socket
         |> assign(:profile, updated)
         |> assign(:changeset, NDProfile.changeset(updated, %{}))
         |> assign(:saved, true)}

      {:error, changeset} ->
        {:noreply, assign(socket, :changeset, changeset)}
    end
  end

  def handle_event("validate", %{"nd_profile" => params}, socket) do
    changeset =
      socket.assigns.profile
      |> NDProfile.changeset(params)
      |> Map.put(:action, :validate)

    {:noreply, assign(socket, changeset: changeset, saved: false)}
  end

  def handle_event("calibrate_now", _params, socket) do
    case FlowCalibrator.calibrate_and_apply() do
      {:ok, :calibrated, updated, _changes} ->
        {:noreply,
         socket
         |> assign(:profile, updated)
         |> assign(:changeset, NDProfile.changeset(updated, %{}))
         |> assign(:calibration, safe_calibration())
         |> assign(:saved, true)}

      _ ->
        {:noreply, socket}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <.settings_layout current_page={:brain_profile}>
      <div class="max-w-2xl space-y-8">
        <div>
          <h1 class="text-xl font-bold text-[#ffd04a] tracking-wide">Brain Profile</h1>
          <p class="text-[#5a5a5a] text-sm mt-1">
            Configure how Cortex adapts to your brain. Every setting changes real behavior —
            flow detection thresholds, energy hours, interruption tolerance.
          </p>
        </div>

        <%!-- Saved indicator --%>
        <div :if={@saved} class="text-[10px] text-[#5ea85e] font-mono animate-slide-in">
          Profile saved. Changes take effect immediately.
        </div>

        <%!-- Preset Selector --%>
        <div class="space-y-3">
          <h2 class="text-sm font-medium text-[#e8dcc0]">Quick Start — Select Your Neurotype</h2>
          <div class="grid grid-cols-1 gap-2">
            <%= for {key, preset} <- @presets do %>
              <button
                phx-click="select_preset"
                phx-value-key={key}
                class={"w-full text-left px-4 py-3 rounded-[7px] border transition-colors cursor-pointer " <>
                  if(matches_preset?(@profile, preset.profile),
                    do: "border-[#ffd04a]/40 bg-[#ffd04a]/5",
                    else: "border-[#1a1a1a] hover:border-[#2a2a2a] bg-[#080808]"
                  )}
              >
                <div class="flex items-center justify-between">
                  <span class="text-sm text-[#e8dcc0] font-medium">{preset.name}</span>
                  <span
                    :if={matches_preset?(@profile, preset.profile)}
                    class="text-[10px] text-[#ffd04a] font-mono"
                  >
                    active
                  </span>
                </div>
                <p class="text-[11px] text-[#5a5a5a] mt-0.5">{preset.description}</p>
              </button>
            <% end %>
          </div>
        </div>

        <%!-- Custom Tuning --%>
        <.form for={@changeset} phx-change="validate" phx-submit="save" class="space-y-6">
          <h2 class="text-sm font-medium text-[#e8dcc0]">Fine Tuning</h2>

          <%!-- Thinking Style --%>
          <div class="space-y-4 rounded-[8px] border border-[#1a1a1a] bg-[#080808] p-4">
            <h3 class="text-[11px] text-[#3a3a3a] uppercase tracking-wider font-medium">
              Thinking Style
            </h3>

            <div class="grid grid-cols-2 gap-4">
              <.field_group label="Style" hint="How you process information">
                <select
                  name="nd_profile[thinking_style]"
                  class="bg-[#0a0a0a] border border-[#1a1a1a] rounded-[6px] text-sm text-[#e8dcc0] px-3 py-2 w-full outline-none focus:border-[#ffd04a]"
                >
                  <option value="parallel" selected={@profile.thinking_style == "parallel"}>
                    Parallel — multiple threads
                  </option>
                  <option value="linear" selected={@profile.thinking_style == "linear"}>
                    Linear — deep single track
                  </option>
                  <option value="mixed" selected={@profile.thinking_style == "mixed"}>
                    Mixed — depends on the task
                  </option>
                </select>
              </.field_group>

              <.field_group label="Parallel Capacity" hint="Max concurrent threads (1-20)">
                <.number_input
                  name="nd_profile[parallel_capacity]"
                  value={@profile.parallel_capacity}
                  min="1"
                  max="20"
                />
              </.field_group>
            </div>
          </div>

          <%!-- Energy Cycle --%>
          <div class="space-y-4 rounded-[8px] border border-[#1a1a1a] bg-[#080808] p-4">
            <h3 class="text-[11px] text-[#3a3a3a] uppercase tracking-wider font-medium">
              Energy Cycle
            </h3>

            <div class="grid grid-cols-2 gap-4">
              <.field_group label="Mud Hours Start" hint="When your brain is slowest (0-23)">
                <.number_input
                  name="nd_profile[mud_start]"
                  value={@profile.mud_start}
                  min="0"
                  max="23"
                />
              </.field_group>
              <.field_group label="Mud Hours End" hint="When fog starts lifting">
                <.number_input name="nd_profile[mud_end]" value={@profile.mud_end} min="0" max="23" />
              </.field_group>
              <.field_group label="Peak Start" hint="When deep work becomes possible">
                <.number_input
                  name="nd_profile[peak_start]"
                  value={@profile.peak_start}
                  min="0"
                  max="23"
                />
              </.field_group>
              <.field_group label="Peak End" hint="When energy starts dropping">
                <.number_input name="nd_profile[peak_end]" value={@profile.peak_end} min="0" max="23" />
              </.field_group>
            </div>
          </div>

          <%!-- Flow Detection --%>
          <div class="space-y-4 rounded-[8px] border border-[#1a1a1a] bg-[#080808] p-4">
            <div class="flex items-center justify-between">
              <h3 class="text-[11px] text-[#3a3a3a] uppercase tracking-wider font-medium">
                Flow Detection
              </h3>
              <div :if={@calibration.ready} class="flex items-center gap-2">
                <span class="text-[10px] text-[#5ea85e] font-mono">
                  auto-calibrating from {@calibration.sessions_recorded} sessions
                </span>
                <button
                  type="button"
                  phx-click="calibrate_now"
                  class="text-[10px] text-[#ffd04a] hover:text-[#ffe47a] font-mono cursor-pointer"
                >
                  calibrate now
                </button>
              </div>
              <div :if={!@calibration.ready} class="text-[10px] text-[#3a3a3a] font-mono">
                {@calibration.sessions_recorded}/{@calibration.sessions_needed} sessions for auto-calibration
              </div>
            </div>

            <div class="grid grid-cols-3 gap-4">
              <.field_group label="Velocity Threshold" hint="Keystrokes/10s to trigger flow">
                <.number_input
                  name="nd_profile[flow_velocity_threshold]"
                  value={@profile.flow_velocity_threshold}
                  min="1"
                  max="100"
                />
              </.field_group>
              <.field_group label="Sustain (seconds)" hint="How long before confirming flow">
                <.number_input
                  name="nd_profile[flow_sustain_seconds]"
                  value={@profile.flow_sustain_seconds}
                  min="5"
                  max="300"
                />
              </.field_group>
              <.field_group label="Cooldown (seconds)" hint="How long before flow breaks">
                <.number_input
                  name="nd_profile[flow_cooldown_seconds]"
                  value={@profile.flow_cooldown_seconds}
                  min="5"
                  max="120"
                />
              </.field_group>
            </div>
          </div>

          <%!-- Protection --%>
          <div class="space-y-4 rounded-[8px] border border-[#1a1a1a] bg-[#080808] p-4">
            <h3 class="text-[11px] text-[#3a3a3a] uppercase tracking-wider font-medium">
              Protection
            </h3>

            <div class="grid grid-cols-2 gap-4">
              <.field_group label="Context Switch Cost" hint="How expensive is switching tasks">
                <select
                  name="nd_profile[context_switch_cost]"
                  class="bg-[#0a0a0a] border border-[#1a1a1a] rounded-[6px] text-sm text-[#e8dcc0] px-3 py-2 w-full outline-none focus:border-[#ffd04a]"
                >
                  <option value="low" selected={@profile.context_switch_cost == "low"}>
                    Low — switch freely
                  </option>
                  <option value="medium" selected={@profile.context_switch_cost == "medium"}>
                    Medium — gentle guard
                  </option>
                  <option value="high" selected={@profile.context_switch_cost == "high"}>
                    High — protect flow aggressively
                  </option>
                </select>
              </.field_group>

              <.field_group
                label="Interruption Tolerance"
                hint="How aggressively to suppress notifications"
              >
                <select
                  name="nd_profile[interruption_tolerance]"
                  class="bg-[#0a0a0a] border border-[#1a1a1a] rounded-[6px] text-sm text-[#e8dcc0] px-3 py-2 w-full outline-none focus:border-[#ffd04a]"
                >
                  <option value="low" selected={@profile.interruption_tolerance == "low"}>
                    Low — suppress most during flow
                  </option>
                  <option value="medium" selected={@profile.interruption_tolerance == "medium"}>
                    Medium — suppress info only
                  </option>
                  <option value="high" selected={@profile.interruption_tolerance == "high"}>
                    High — show everything
                  </option>
                </select>
              </.field_group>

              <.field_group label="Error Spike Threshold" hint="Errors in 2min before thermal warning">
                <.number_input
                  name="nd_profile[error_spike_threshold]"
                  value={@profile.error_spike_threshold}
                  min="1"
                  max="20"
                />
              </.field_group>

              <.field_group label="Marathon Hours" hint="Hours before suggesting a break">
                <.number_input
                  name="nd_profile[marathon_hours_threshold]"
                  value={@profile.marathon_hours_threshold}
                  min="1"
                  max="12"
                />
              </.field_group>
            </div>
          </div>

          <%!-- Personal Signals --%>
          <div class="space-y-4 rounded-[8px] border border-[#1a1a1a] bg-[#080808] p-4">
            <h3 class="text-[11px] text-[#3a3a3a] uppercase tracking-wider font-medium">
              Your Signals
            </h3>
            <p class="text-[10px] text-[#3a3a3a]">
              These don't change behavior — they're reminders of what to watch for.
            </p>

            <div class="grid grid-cols-3 gap-4">
              <.field_group label="Wall Signal" hint="What does hitting the wall feel like?">
                <.text_input name="nd_profile[wall_signal]" value={@profile.wall_signal} />
              </.field_group>
              <.field_group label="Flow Signal" hint="What does entering flow feel like?">
                <.text_input name="nd_profile[flow_signal]" value={@profile.flow_signal} />
              </.field_group>
              <.field_group label="Focus Sound" hint="What audio helps you focus?">
                <.text_input name="nd_profile[focus_sound]" value={@profile.focus_sound} />
              </.field_group>
            </div>
          </div>

          <div class="flex items-center justify-between pt-2">
            <button
              type="submit"
              class="text-sm text-[#ffd04a] hover:text-[#ffe47a] px-5 py-2.5 rounded-[8px] border border-[#ffd04a]/20 hover:border-[#ffd04a]/40 transition-colors cursor-pointer"
            >
              Save Profile
            </button>
            <span class="text-[10px] text-[#2a2a2a] font-mono">
              Changes affect flow detection, energy awareness, and thermal throttle in real-time.
            </span>
          </div>
        </.form>
      </div>
    </.settings_layout>
    """
  end

  # Components

  defp field_group(assigns) do
    ~H"""
    <div>
      <label class="text-[11px] text-[#5a5a5a] font-medium block mb-1">{@label}</label>
      {render_slot(@inner_block)}
      <span :if={@hint} class="text-[9px] text-[#2a2a2a] mt-0.5 block">{@hint}</span>
    </div>
    """
  end

  attr :name, :string, required: true
  attr :value, :any, required: true
  attr :min, :string, default: "0"
  attr :max, :string, default: "100"

  defp number_input(assigns) do
    ~H"""
    <input
      type="number"
      name={@name}
      value={@value}
      min={@min}
      max={@max}
      class="bg-[#0a0a0a] border border-[#1a1a1a] rounded-[6px] text-sm text-[#e8dcc0] px-3 py-2 w-full outline-none focus:border-[#ffd04a] font-mono"
    />
    """
  end

  attr :name, :string, required: true
  attr :value, :any, required: true

  defp text_input(assigns) do
    ~H"""
    <input
      type="text"
      name={@name}
      value={@value}
      class="bg-[#0a0a0a] border border-[#1a1a1a] rounded-[6px] text-sm text-[#e8dcc0] px-3 py-2 w-full outline-none focus:border-[#ffd04a]"
    />
    """
  end

  defp matches_preset?(profile, preset_profile) do
    Enum.all?(preset_profile, fn {key, value} ->
      Map.get(profile, key) == value
    end)
  end

  defp safe_calibration do
    FlowCalibrator.status()
  rescue
    _ -> %{sessions_recorded: 0, sessions_needed: 10, ready: false, progress: 0}
  end
end
