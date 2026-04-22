// mux0-status.js — opencode plugin that reports session state to mux0 via Unix socket.
// ESM module. opencode (v1.4.x) loads plugins via `await import(fileURL)` and expects
// either a default export `{ server: async (input) => hooks }` (v1 shape) or any named
// async function export `(input, options) => hooks` (legacy shape). The plugin returns
// a hooks object; there is NO event bus on the input — we subscribe via the `event` hook.
//
// Authoritative schema: packages/plugin/src/index.ts in sst/opencode.
// Written independently for mux0.

import net from "node:net";

const SOCK = process.env.MUX0_HOOK_SOCK;
const TID  = process.env.MUX0_TERMINAL_ID;

// In-memory per-plugin turn state. Reset on session.idle / session.error /
// session.status{type=idle}. No session file needed — the plugin process
// outlives the turn naturally (opencode keeps it alive across turns).
let turn = { hadError: false, tool: null, startedAt: null };

function emit(msg) {
    if (!SOCK || !TID) return;
    const payload = JSON.stringify({
        terminalId: TID,
        agent: "opencode",
        at: Date.now() / 1000,
        ...msg,
    }) + "\n";
    try {
        const client = net.createConnection(SOCK);
        client.on("error", () => {});
        client.setTimeout(500, () => { try { client.destroy(); } catch {} });
        client.on("connect", () => client.end(payload));
    } catch (_) {
        // swallow
    }
}

function shortPath(p) {
    if (!p) return "";
    const parts = p.split("/").filter(Boolean);
    return parts.length > 3 ? parts.slice(-3).join("/") : parts.join("/");
}

function describeOpencodeTool(tool, input) {
    if (!input || typeof input !== "object") return tool || "";
    const t = tool || "";
    if (t === "edit" || t === "write" || t === "read") {
        const p = shortPath(input.filePath || input.file_path || "");
        return p ? `${t.charAt(0).toUpperCase() + t.slice(1)} ${p}` : t;
    }
    if (t === "bash") {
        const cmd = (input.command || "").split("\n")[0].slice(0, 60);
        return cmd ? `Bash: ${cmd}` : "Bash";
    }
    return t;
}

function emitFinishedFromTurn() {
    emit({ event: "finished", exitCode: turn.hadError ? 1 : 0 });
    turn = { hadError: false, tool: null, startedAt: null };
}

export const Mux0StatusPlugin = async (_input) => ({
    event: async ({ event }) => {
        switch (event?.type) {
            case "session.created":
                // Do not reset turn state here — session.created fires before first turn too.
                return;
            case "session.idle":                // deprecated but still emitted
            case "session.error":
                return emitFinishedFromTurn();
            case "permission.asked":
                return emit({ event: "needsInput" });
            case "permission.replied":
                return emit({ event: "running" });
            case "session.status": {
                const t = event.properties?.status?.type;
                if (t === "busy") {
                    if (!turn.startedAt) turn.startedAt = Date.now() / 1000;
                    emit({ event: "running" });
                } else if (t === "idle") {
                    emitFinishedFromTurn();
                }
                return;
            }
        }
    },

    "tool.execute.before": async (args) => {
        turn.tool = args?.tool;
        if (!turn.startedAt) turn.startedAt = Date.now() / 1000;
        const detail = describeOpencodeTool(args?.tool, args?.input);
        emit({ event: "running", toolDetail: detail || undefined });
    },

    "tool.execute.after": async (args) => {
        // args.error present if tool threw; args.result.status === "error"
        // for tools that report failure in-band.
        const hadErr = !!(args?.error)
            || (args?.result?.status === "error");
        if (hadErr) turn.hadError = true;
        // No socket emit — icon only flips at session.idle / session.status{type=idle}.
    },
});
