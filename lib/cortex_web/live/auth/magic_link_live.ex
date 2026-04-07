defmodule CortexWeb.Auth.MagicLinkLive do
  use CortexWeb, :live_view

  alias Cortex.Accounts

  def mount(%{"token" => token}, _session, socket) do
    case Accounts.verify_magic_link_token(token) do
      {:ok, _user} ->
        # Redirect to a controller endpoint that sets the session
        {:ok, redirect(socket, to: "/auth/magic/#{token}/callback")}

      :error ->
        {:ok,
         socket
         |> assign(:page_title, "Invalid Link")
         |> assign(:error, true)}
    end
  end

  def render(assigns) do
    ~H"""
    <div class="min-h-screen bg-[#050505] flex items-center justify-center px-4">
      <div class="w-full max-w-sm text-center space-y-4">
        <h1 class="text-[#ffd04a] text-xl font-bold tracking-wide">CORTEX</h1>

        <div class="rounded-[8px] border border-[#1a1a1a] bg-[#080808] p-6 space-y-3">
          <div class="w-8 h-8 rounded-full bg-[#e05252]/10 border border-[#e05252]/20 flex items-center justify-center mx-auto">
            <span class="text-[#e05252] text-sm">!</span>
          </div>
          <p class="text-[#e8dcc0] text-sm">This magic link is invalid or expired</p>
          <p class="text-[#3a3a3a] text-xs">Links expire after 10 minutes.</p>
          <a
            href="/login"
            class="inline-block text-[#ffd04a] text-sm hover:text-[#ffe47a] transition-colors mt-2"
          >
            Request a new one
          </a>
        </div>
      </div>
    </div>
    """
  end
end
