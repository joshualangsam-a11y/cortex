defmodule CortexWeb.Settings.SettingsLayout do
  @moduledoc """
  Layout component for settings pages with sidebar navigation.
  """
  use Phoenix.Component
  use CortexWeb, :verified_routes

  attr :current_page, :atom, required: true
  slot :inner_block, required: true

  def settings_layout(assigns) do
    ~H"""
    <div class="flex h-screen bg-[#050505] text-[#e8dcc0]">
      <!-- Sidebar -->
      <nav class="w-56 border-r border-[#1a1a1a] p-4 flex flex-col gap-1">
        <.link
          navigate={~p"/"}
          class="flex items-center gap-2 px-3 py-2 text-xs text-[#5a5a5a] hover:text-[#ffd04a] transition-colors"
        >
          <span>&larr;</span>
          <span>Dashboard</span>
        </.link>

        <div class="mt-4 mb-2 px-3 text-[10px] uppercase tracking-wider text-[#3a3a3a] font-semibold">
          Settings
        </div>

        <.nav_item page={:projects} current={@current_page} href={~p"/settings/projects"}>
          Projects
        </.nav_item>

        <.nav_item page={:brain_profile} current={@current_page} href={~p"/settings/brain"}>
          Brain Profile
        </.nav_item>

        <.nav_item page={:billing} current={@current_page} href={~p"/settings/billing"}>
          Billing
        </.nav_item>

        <.nav_item page={:preferences} current={@current_page} href="#" disabled={true}>
          Preferences
        </.nav_item>

        <.nav_item page={:account} current={@current_page} href="#" disabled={true}>
          Account
        </.nav_item>
      </nav>
      
    <!-- Content -->
      <main class="flex-1 overflow-y-auto p-6">
        {render_slot(@inner_block)}
      </main>
    </div>
    """
  end

  attr :page, :atom, required: true
  attr :current, :atom, required: true
  attr :href, :string, required: true
  attr :disabled, :boolean, default: false
  slot :inner_block, required: true

  defp nav_item(assigns) do
    active = assigns.page == assigns.current

    assigns =
      assigns
      |> assign(:active, active)
      |> assign(
        :class,
        cond do
          active ->
            "block px-3 py-2 rounded-md text-sm bg-[#1a1a1a] text-[#ffd04a] font-medium"

          assigns.disabled ->
            "block px-3 py-2 rounded-md text-sm text-[#3a3a3a] cursor-not-allowed"

          true ->
            "block px-3 py-2 rounded-md text-sm text-[#e8dcc0] hover:bg-[#1a1a1a] hover:text-[#ffd04a] transition-colors"
        end
      )

    ~H"""
    <%= if @disabled do %>
      <span class={@class}>{render_slot(@inner_block)}</span>
    <% else %>
      <.link navigate={@href} class={@class}>
        {render_slot(@inner_block)}
      </.link>
    <% end %>
    """
  end
end
