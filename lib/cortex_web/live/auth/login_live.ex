defmodule CortexWeb.Auth.LoginLive do
  use CortexWeb, :live_view

  alias Cortex.Accounts

  def mount(_params, _session, socket) do
    {:ok,
     assign(socket, form: to_form(%{"email" => ""}, as: :user), sent: false, page_title: "Login")}
  end

  def handle_event("send_magic_link", %{"user" => %{"email" => email}}, socket) do
    email = String.trim(email)

    if email != "" do
      # Find or create user
      user =
        case Accounts.get_user_by_email(email) do
          nil ->
            {:ok, user} = Accounts.register_user(%{email: email})
            user

          user ->
            user
        end

      # Generate magic link token
      token = Accounts.generate_magic_link_token(user)
      magic_url = "/auth/magic/#{token}"

      if Application.get_env(:cortex, :env) == :dev do
        {:noreply, redirect(socket, to: magic_url)}
      else
        socket =
          socket
          |> put_flash(:info, "Magic link: #{magic_url}")
          |> assign(:sent, true)

        {:noreply, socket}
      end
    else
      {:noreply, put_flash(socket, :error, "Enter your email address.")}
    end
  end

  def handle_event("reset", _params, socket) do
    {:noreply, assign(socket, sent: false, form: to_form(%{"email" => ""}, as: :user))}
  end

  def render(assigns) do
    ~H"""
    <div class="min-h-screen bg-[#050505] flex items-center justify-center px-4">
      <div class="w-full max-w-sm space-y-6">
        <div class="text-center space-y-2">
          <h1 class="text-[#ffd04a] text-xl font-bold tracking-wide">CORTEX</h1>
          <p class="text-[#3a3a3a] text-sm">Terminal mission control</p>
        </div>

        <div class="rounded-[8px] border border-[#1a1a1a] bg-[#080808] p-6 space-y-4">
          <div :if={!@sent}>
            <h2 class="text-[#e8dcc0] text-sm font-medium mb-4">Sign in with magic link</h2>
            <.form for={@form} phx-submit="send_magic_link" class="space-y-4">
              <div>
                <label class="block text-[10px] text-[#3a3a3a] uppercase tracking-wider mb-1.5">
                  Email
                </label>
                <input
                  type="email"
                  name="user[email]"
                  value={@form[:email].value}
                  required
                  autofocus
                  placeholder="you@example.com"
                  class="w-full bg-[#0a0a0a] border border-[#1a1a1a] rounded-[6px] px-3 py-2 text-sm text-[#e8dcc0] placeholder-[#2a2a2a] outline-none focus:border-[#ffd04a]/40 transition-colors font-mono"
                />
              </div>
              <button
                type="submit"
                class="w-full bg-[#ffd04a]/10 border border-[#ffd04a]/20 hover:border-[#ffd04a]/40 text-[#ffd04a] text-sm rounded-[7px] px-4 py-2.5 transition-colors cursor-pointer"
              >
                Send magic link
              </button>
            </.form>
          </div>

          <div :if={@sent} class="text-center space-y-3 py-2">
            <div class="w-8 h-8 rounded-full bg-[#ffd04a]/10 border border-[#ffd04a]/20 flex items-center justify-center mx-auto">
              <span class="text-[#ffd04a] text-sm">@</span>
            </div>
            <p class="text-[#e8dcc0] text-sm">Check your email for the magic link</p>
            <p class="text-[#3a3a3a] text-xs">
              (Dev mode: check the flash message above for the link)
            </p>
            <button
              phx-click="reset"
              class="text-[10px] text-[#3a3a3a] hover:text-[#e8dcc0] transition-colors cursor-pointer"
            >
              Try a different email
            </button>
          </div>
        </div>

        <p class="text-center text-[10px] text-[#2a2a2a]">
          No password needed. We'll send you a magic link.
        </p>
      </div>
    </div>
    """
  end
end
