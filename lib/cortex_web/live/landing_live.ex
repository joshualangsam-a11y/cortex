defmodule CortexWeb.LandingLive do
  use CortexWeb, :live_view

  alias Cortex.Marketing

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, "Terminal Mission Control")
     |> assign(:page_description, "Multi-project terminal dashboard for developers. Output intelligence, workspace presets, session persistence. Built with Elixir.")
     |> assign(:email, "")
     |> assign(:submitted, false)
     |> assign(:error, nil)
     |> assign(:waitlist_count, Marketing.waitlist_count())}
  end

  @impl true
  def handle_event("validate", %{"email" => email}, socket) do
    {:noreply, assign(socket, :email, email)}
  end

  @impl true
  def handle_event("join_waitlist", %{"email" => email}, socket) do
    case Marketing.join_waitlist(email) do
      {:ok, _entry} ->
        {:noreply,
         socket
         |> assign(:submitted, true)
         |> assign(:error, nil)
         |> assign(:email, "")
         |> assign(:waitlist_count, Marketing.waitlist_count())}

      {:error, changeset} ->
        error =
          case changeset.errors[:email] do
            {"already on the waitlist", _} -> "You're already on the list."
            {msg, _} -> msg
            _ -> "Something went wrong. Try again."
          end

        {:noreply, assign(socket, :error, error)}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="min-h-screen bg-[#050505] font-mono text-[#e8dcc0] overflow-x-hidden">
      <%!-- Hero Section --%>
      <section class="relative px-6 pt-20 pb-24 md:pt-32 md:pb-32">
        <div class="max-w-4xl mx-auto text-center">
          <div class="mb-2 text-[#5a5a5a] text-xs tracking-[0.3em] uppercase">v0.1 // early access</div>

          <h1 class="text-5xl md:text-7xl font-bold tracking-tight mb-6"
              style="text-shadow: 0 0 20px #ffd04a40, 0 0 40px #ffd04a20;">
            <span class="text-[#ffd04a]">CORTEX</span>
          </h1>

          <p class="text-lg md:text-xl text-[#e8dcc0] mb-2 max-w-xl mx-auto leading-relaxed">
            Terminal mission control for developers who ship.
          </p>
          <p class="text-sm text-[#5a5a5a] mb-10">
            Multi-project dashboard. Output intelligence. Session persistence.
          </p>

          <div class="max-w-md mx-auto mb-6">
            <.waitlist_form email={@email} submitted={@submitted} error={@error} />
          </div>

          <div :if={@waitlist_count > 0} class="text-sm text-[#5a5a5a]">
            <span class="text-[#ffd04a]">{@waitlist_count}</span>
            {if @waitlist_count == 1, do: "developer", else: "developers"} on the waitlist
          </div>
        </div>

        <%!-- Terminal boot effect --%>
        <div class="max-w-2xl mx-auto mt-16">
          <div class="bg-[#080808] border border-[#1a1a1a] rounded-lg p-4 md:p-6">
            <div class="flex items-center gap-2 mb-4">
              <div class="w-2.5 h-2.5 rounded-full bg-[#e05252]"></div>
              <div class="w-2.5 h-2.5 rounded-full bg-[#ffd04a]"></div>
              <div class="w-2.5 h-2.5 rounded-full bg-[#5ea85e]"></div>
              <span class="ml-2 text-xs text-[#3a3a3a]">cortex</span>
            </div>
            <div class="text-xs md:text-sm space-y-1.5 text-[#5a5a5a]">
              <div><span class="text-[#5ea85e]">$</span> cortex start</div>
              <div class="text-[#3a3a3a]">Loading projects...</div>
              <div>
                <span class="text-[#5a9bcf]">[api]</span>
                <span class="text-[#5ea85e]"> running</span>
                <span class="text-[#3a3a3a]"> pid 42891 // port 4000</span>
              </div>
              <div>
                <span class="text-[#ffd04a]">[web]</span>
                <span class="text-[#5ea85e]"> running</span>
                <span class="text-[#3a3a3a]"> pid 42892 // port 3000</span>
              </div>
              <div>
                <span class="text-[#e05252]">[worker]</span>
                <span class="text-[#e05252]"> build failed</span>
                <span class="text-[#3a3a3a]"> exit code 1</span>
              </div>
              <div class="pt-1">
                <span class="text-[#ffd04a]">!</span>
                <span class="text-[#e8dcc0]"> 1 project needs attention</span>
              </div>
              <div class="text-[#5ea85e]">Ready. 3 sessions active.</div>
            </div>
          </div>
        </div>
      </section>

      <%!-- Problem Section --%>
      <section class="px-6 py-20 md:py-28">
        <div class="max-w-2xl mx-auto">
          <div class="space-y-4 text-base md:text-lg">
            <p class="text-[#e8dcc0]">You have 8 terminals open.</p>
            <p class="text-[#e8dcc0]">You can't remember which one is which.</p>
            <p class="text-[#e8dcc0]">Your build failed 10 minutes ago and you didn't notice.</p>
          </div>
          <p class="mt-8 text-[#ffd04a] text-lg md:text-xl font-semibold">Sound familiar?</p>
        </div>
      </section>

      <%!-- Features Grid --%>
      <section class="px-6 py-20 md:py-28">
        <div class="max-w-5xl mx-auto">
          <h2 class="text-2xl md:text-3xl font-bold text-[#e8dcc0] mb-4 text-center">
            Everything in one view
          </h2>
          <p class="text-[#5a5a5a] text-center mb-14 max-w-lg mx-auto">
            Cortex replaces your terminal tabs with a mission control dashboard.
          </p>

          <div class="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-5">
            <.feature_card
              color="bg-[#5ea85e]"
              title="Multi-Project Dashboard"
              description="See all your terminals at once. Grid layout with focus mode, drag-and-drop, instant switching."
            />
            <.feature_card
              color="bg-[#ffd04a]"
              title="Output Intelligence"
              description="Cortex watches your terminals. Build errors, test failures, deploy success -- toasted to you in real-time."
            />
            <.feature_card
              color="bg-[#5a9bcf]"
              title="Workspace Presets"
              description={~s(Save your terminal layout. "Morning mode" boots your top projects with the right commands. One click.)}
            />
            <.feature_card
              color="bg-[#e05252]"
              title="Priority Engine"
              description="Cortex knows which project needs attention. Git status, deploy health, configurable priority weights."
            />
            <.feature_card
              color="bg-[#c084fc]"
              title="Terminal Search"
              description="Ctrl+Shift+F. Search through any terminal's scrollback. Find that error message from an hour ago."
            />
            <.feature_card
              color="bg-[#f97316]"
              title="Session Persistence"
              description="Crash? Restart? Your terminals survive. Scrollback saved to disk, sessions restored automatically."
            />
          </div>
        </div>
      </section>

      <%!-- Pricing Section --%>
      <section class="px-6 py-20 md:py-28">
        <div class="max-w-3xl mx-auto">
          <h2 class="text-2xl md:text-3xl font-bold text-[#e8dcc0] mb-4 text-center">
            Simple pricing
          </h2>
          <p class="text-[#5a5a5a] text-center mb-14">
            Start free. Upgrade when you need more.
          </p>

          <div class="grid grid-cols-1 md:grid-cols-2 gap-5">
            <%!-- Free Tier --%>
            <div class="bg-[#080808] border border-[#1a1a1a] rounded-lg p-6 md:p-8">
              <div class="text-sm text-[#5a5a5a] mb-1">Free</div>
              <div class="text-3xl font-bold text-[#e8dcc0] mb-6">$0</div>
              <ul class="space-y-3 text-sm text-[#e8dcc0]">
                <li class="flex items-center gap-2.5">
                  <span class="w-1.5 h-1.5 rounded-full bg-[#5a5a5a] shrink-0"></span>
                  3 projects
                </li>
                <li class="flex items-center gap-2.5">
                  <span class="w-1.5 h-1.5 rounded-full bg-[#5a5a5a] shrink-0"></span>
                  3 sessions
                </li>
                <li class="flex items-center gap-2.5">
                  <span class="w-1.5 h-1.5 rounded-full bg-[#5a5a5a] shrink-0"></span>
                  Basic terminal grid
                </li>
                <li class="flex items-center gap-2.5">
                  <span class="w-1.5 h-1.5 rounded-full bg-[#5a5a5a] shrink-0"></span>
                  Command palette
                </li>
              </ul>
            </div>

            <%!-- Pro Tier --%>
            <div class="bg-[#080808] border border-[#ffd04a]/30 rounded-lg p-6 md:p-8 relative">
              <div class="absolute top-0 right-0 bg-[#ffd04a] text-[#050505] text-[10px] font-bold px-2.5 py-0.5 rounded-bl-lg rounded-tr-lg tracking-wider uppercase">
                Popular
              </div>
              <div class="text-sm text-[#ffd04a] mb-1">Pro</div>
              <div class="text-3xl font-bold text-[#e8dcc0] mb-1">$19<span class="text-sm font-normal text-[#5a5a5a]">/mo</span></div>
              <div class="text-xs text-[#3a3a3a] mb-6">per developer</div>
              <ul class="space-y-3 text-sm text-[#e8dcc0]">
                <li class="flex items-center gap-2.5">
                  <span class="w-1.5 h-1.5 rounded-full bg-[#ffd04a] shrink-0"></span>
                  Unlimited projects
                </li>
                <li class="flex items-center gap-2.5">
                  <span class="w-1.5 h-1.5 rounded-full bg-[#ffd04a] shrink-0"></span>
                  Unlimited sessions
                </li>
                <li class="flex items-center gap-2.5">
                  <span class="w-1.5 h-1.5 rounded-full bg-[#ffd04a] shrink-0"></span>
                  Workspaces &amp; presets
                </li>
                <li class="flex items-center gap-2.5">
                  <span class="w-1.5 h-1.5 rounded-full bg-[#ffd04a] shrink-0"></span>
                  Output intelligence
                </li>
                <li class="flex items-center gap-2.5">
                  <span class="w-1.5 h-1.5 rounded-full bg-[#ffd04a] shrink-0"></span>
                  Priority engine
                </li>
                <li class="flex items-center gap-2.5">
                  <span class="w-1.5 h-1.5 rounded-full bg-[#ffd04a] shrink-0"></span>
                  Terminal search
                </li>
              </ul>
            </div>
          </div>
        </div>
      </section>

      <%!-- Bottom CTA --%>
      <section class="px-6 py-20 md:py-28 border-t border-[#1a1a1a]">
        <div class="max-w-2xl mx-auto text-center">
          <p class="text-sm text-[#5a5a5a] mb-2 tracking-wide">
            Built with Elixir. Powered by Phoenix LiveView.
          </p>
          <p class="text-sm text-[#5a5a5a] mb-10">
            Runs on your machine. Your terminals never leave.
          </p>

          <div class="max-w-md mx-auto mb-6">
            <.waitlist_form email={@email} submitted={@submitted} error={@error} label="Get Early Access" />
          </div>

          <div :if={@waitlist_count > 0} class="text-sm text-[#5a5a5a]">
            <span class="text-[#ffd04a]">{@waitlist_count}</span>
            {if @waitlist_count == 1, do: "developer", else: "developers"} on the waitlist
          </div>
        </div>
      </section>

      <%!-- Footer --%>
      <footer class="px-6 py-10 border-t border-[#0f0f0f]">
        <div class="max-w-5xl mx-auto text-center">
          <p class="text-xs text-[#3a3a3a]">Built by Roan Co.</p>
        </div>
      </footer>
    </div>
    """
  end

  # -- Components --

  defp waitlist_form(assigns) do
    assigns = assign_new(assigns, :label, fn -> "Join Waitlist" end)

    ~H"""
    <div :if={@submitted} class="bg-[#0a0a0a] border border-[#5ea85e]/30 rounded-lg px-5 py-4 text-sm text-[#5ea85e]">
      You're in. We'll notify you when Cortex is ready.
    </div>
    <form :if={!@submitted} phx-submit="join_waitlist" phx-change="validate" class="flex flex-col sm:flex-row gap-3">
      <input
        type="email"
        name="email"
        value={@email}
        placeholder="you@example.com"
        required
        class="flex-1 bg-[#0a0a0a] border border-[#1a1a1a] rounded-[7px] text-[#e8dcc0] placeholder-[#2a2a2a] px-4 py-3 focus:border-[#ffd04a]/40 focus:outline-none font-mono text-sm"
      />
      <button
        type="submit"
        class="bg-[#ffd04a] text-[#050505] font-bold px-6 py-3 rounded-[7px] hover:bg-[#ffe47a] transition-colors text-sm whitespace-nowrap cursor-pointer"
      >
        {@label}
      </button>
    </form>
    <div :if={@error} class="mt-2 text-xs text-[#e05252]">{@error}</div>
    """
  end

  defp feature_card(assigns) do
    ~H"""
    <div class="bg-[#080808] border border-[#1a1a1a] rounded-lg p-5 md:p-6">
      <div class={"w-2 h-2 rounded-full #{@color} mb-4"}></div>
      <h3 class="text-sm font-semibold text-[#e8dcc0] mb-2">{@title}</h3>
      <p class="text-xs text-[#5a5a5a] leading-relaxed">{@description}</p>
    </div>
    """
  end
end
