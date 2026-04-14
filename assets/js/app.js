import "phoenix_html";
import { Socket } from "phoenix";
import { LiveSocket } from "phoenix_live_view";
import topbar from "../vendor/topbar";
import TerminalHook from "./hooks/terminal_hook";
import CommandPaletteHook from "./hooks/command_palette_hook";
import DragHook from "./hooks/drag_hook";
import AgentChatHook, { AgentInputHook } from "./hooks/agent_chat_hook";

let csrfToken = document
  .querySelector("meta[name='csrf-token']")
  .getAttribute("content");

let liveSocket = new LiveSocket("/live", Socket, {
  longPollFallbackMs: 2500,
  params: { _csrf_token: csrfToken },
  hooks: {
    Terminal: TerminalHook,
    CommandPalette: CommandPaletteHook,
    Drag: DragHook,
    AgentChat: AgentChatHook,
    AgentInput: AgentInputHook,
  },
});

// Show progress bar on live navigation and form submits
topbar.config({
  barColors: { 0: "#ffd04a" },
  shadowColor: "rgba(0, 0, 0, .3)",
});
window.addEventListener("phx:page-loading-start", (_info) => topbar.show(300));
window.addEventListener("phx:page-loading-stop", (_info) => topbar.hide());

liveSocket.connect();

window.liveSocket = liveSocket;
