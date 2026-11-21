# spec.md — async.quickshare technical specification

## 1. Intent

Let an Omarchy/Hyprland desktop receive files from the built-in Android Quick
Share (formerly Nearby Share) share sheet, with the same confirm-on-receive
 UX as a first-party client, without installing anything on the phone.

## 2. Goals

- Bar widget showing receiver status and an incoming-transfer badge.
- Panel showing sender, file list, 4-digit PIN, and Accept/Decline.
- Progress and recent-transfer history.
- Work when the laptop is a client on the phone's hotspot (mDNS unreliable).
- Explicit consent for every inbound transfer; no silent writes.
- Keep all protocol/radio work out of the Quickshell process.

## 3. Non-goals / anti-goals

- Sending files from the PC (current backend is receive-only).
- Contacts / "Your devices" visibility and cloud/WebRTC relays — require
  Google account certificates and servers.
- An official Google client; this is a reverse-engineered implementation.
- Auto-accept, silent background writes, or rendering untrusted text as rich
  text in the shell.

## 4. Architecture

```
Panel.qml  ──stdout JSON lines──  quickshare-bridge  ──stdin JSON lines──  quickshare-rx
     └──────── commands via Unix socket ────────────┘
```

| Component | Responsibility |
|---|---|
| `Panel.qml` | UI only: status, PIN card, buttons, progress, history, IPC |
| `bin/quickshare-bridge` | Process supervision, event normalization, decision relay, local logging |
| `backend/` (`quickshare-rx`) | BLE/mDNS advertisement, UKEY2/SecureMessage handshake, file writing, consent enforcement |
| `i18n/en.json` | Plugin-owned strings |
| `Model.js` | Pure parsing/formatting helpers |

## 5. Event contract

All lines are JSON objects with a `t` field. The bridge normalizes backend
output to this schema; the panel must tolerate unknown fields and types.

| `t` | Fields | Meaning |
|---|---|---|
| `status` | `backend`, `state` (`starting`, `ready`, `stopped`, `missing`, `error`), `message?`, `pid?`, `port?`, `name?` | Receiver lifecycle |
| `ask` | `id`, `from`, `pin`, `files[]`, `bytes` | Inbound transfer awaiting consent |
| `progress` | `id`, `done`, `total` | Byte progress |
| `received` | `id`, `from`, `files[]`, `dir`, `bytes?` | Transfer finished; file(s) saved |
| `result` | `id`, `code` (`declined`, `cancelled`, `failed`) | Terminal non-success |
| `decision` | `id`, `accepted` | Consent was sent to backend |
| `log` | `message` | Diagnostic output |
| `error` | `message` | Recoverable error; shown in panel status line |

Commands from the panel to the bridge (Unix socket at
`$XDG_RUNTIME_DIR/quickshare-omarchy/bridge.sock`):

| `cmd` | Fields | Meaning |
|---|---|---|
| `ctl` | `accept` / `decline`, `id` | Relay decision to backend stdin |
| `ping` | — | Liveness check |
| `scan`, `send` | — | CLI subcommands (scan is a no-op for the BLE backend) |

The Rust backend reads one JSON object per line on **stdin**:
`{"cmd":"accept"|"decline","id":"..."}` and emits the event table above on
stdout. stdin is text mode — write strings.

## 6. State machine (inbound)

```
IDLE → advertising/ready
     → connection over BLE 0xFEF3 GATT or L2CAP
     → UKEY2 + SecureMessage + 4-digit PIN
     → WaitingForUserConsent ── emit ask
          ├── accept → ReceivingFiles (progress) → Finished (received)
          └── decline → Rejected (result: declined)
     → Cancelled / Failed (result)
```

Each transfer id is announced once (`announced` set in the Rust wrapper).
Keep-alive frames are handled by `rqs_lib`.

## 7. Environment requirements

- Omarchy/Hyprland with Quickshell; plugin directory
  `~/.config/omarchy/plugins/async.quickshare`.
- BlueZ 5.x with a LE-capable adapter; Avahi running.
- ufw allows incoming TCP **53318** (`sudo ufw allow 53318/tcp comment quickshare`).
- Rust toolchain + `protoc` for building the backend (installer handles this).
- Phone Quick Share visibility: **Everyone**.

## 8. Security model

- Trust is per-transfer, established by out-of-band comparison of the
  4-digit PIN derived from the UKEY2 auth string.
- Third-party clients cannot produce Google contact certificates; therefore
  "Everyone" mode only.
- No credentials are stored. Download directory is the user's XDG download
  dir (`~/Downloads/Quick Share` by default).
- All untrusted strings are rendered as PlainText in QML.
- Consent is mandatory in the wrapper; auto-accept is forbidden.

## 9. Acceptance criteria

1. `./install.sh` on a fresh Omarchy machine produces `quickshare-rx` and a
   healthy bridge (`ping` → `{"ok": true}`).
2. Phone sees the PC, sends a file, panel shows sender + PIN, Accept writes
   the file into the download dir and emits `received`.
3. Decline emits `result: declined` and writes no file.
4. `node tests/model.test.mjs` and `python3 -m py_compile` pass.
5. No QML errors in `journalctl --user` after `omarchy restart shell`.
6. Bridge survives shell restarts without orphaned receivers holding port
   53318.

## 10. Open issues / deferred

- Phone sometimes remains on "Connecting..." with **no connection attempt
  arriving at the PC** after a failed transfer. Even the previously working
  control receiver was affected, so this is suspected phone-side stale state.
  See `docs/SESSION_HANDOFF.md`.
- No watchdog for BLE advertisement registration failures
  (`target object was either not present or removed`).
- Sending from the PC is not implemented.
- No independent security audit of `rqs_lib`.
