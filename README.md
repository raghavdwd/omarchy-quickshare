# async.quickshare — Quick Share plugin for Omarchy

An Omarchy bar widget and panel for **Android Quick Share**. The QML plugin is
only the UI: Bluetooth, Wi‑Fi, protocol and crypto work live in a headless
receiver so the shell stays small and the protocol can be updated separately.

**Status:** works on the bench (one confirmed receive from a Samsung Galaxy
A27), but a phone-side "Connecting..." hang is still being investigated. See
[`docs/SESSION_HANDOFF.md`](docs/SESSION_HANDOFF.md) before continuing work.

## How it works

```
Quickshell panel ──JSON lines──> bin/quickshare-bridge ──stdin/stdout──> quickshare-rx
        │                                │                                  │
        ├─ accept/decline                ├─ status/event normalization      BLE 0xFEF3 GATT/L2CAP
        └─ scan / status                 └─ decision relay                  + mDNS / Wi-Fi LAN
```

- `Panel.qml` — bar icon (↗), incoming PIN card with Accept/Decline, scan,
  transfer progress and recent transfers.
- `bin/quickshare-bridge` — Python bridge. Starts and supervises the receiver,
  forwards events to the panel as JSON lines, and relays Accept/Decline back.
- `backend/` — Rust wrapper around `rqs_lib` from
  [open-quickshare](https://github.com/ignotusbucius/open-quickshare). Exposes
  the receiver as a JSON-lines process and **requires explicit consent** for
  every inbound transfer — no auto-accept.
- `Model.js`, `i18n/en.json` — pure helpers and plugin-owned strings.

The receiver advertises a Quick Share endpoint over BLE (`0xFEF3`) and uses
UKEY2 + SecureMessage with a 4-digit PIN, so discovery can work even when
mDNS is unreliable (for example, when the laptop is connected to the phone's
hotspot). "Everyone" visibility is required; Contacts / Your devices need
Google-account certificates that a third-party client cannot provide.

## Install

```sh
cd ~/.config/omarchy/plugins/async.quickshare
./install.sh
```

The installer puts `quickshare-rx` in `~/.local/bin`, builds the protocol
library under `~/.local/share/quickshare-backend`, enables Avahi and
Bluetooth, and opens TCP 53318 in ufw if it is active. Review it before
running — it uses sudo only for services and the firewall rule.

Add the plugin to `~/.config/omarchy/shell.json` under `bar.layout.right`:

```json
{ "id": "async.quickshare" }
```

Reload with `omarchy restart shell`.

## Use

1. Set the phone's Quick Share visibility to **Everyone**.
2. Open the phone's share sheet and select the PC (advertised as
   **Omarchy Share** by default).
3. The panel opens with the sender, file list and 4-digit PIN. Confirm the
   PIN matches the phone, then click **Accept**.
4. Files land in `~/Downloads/Quick Share`.

Right-click the bar icon for an explicit scan. Recent transfers and progress
appear in the panel.

## Troubleshooting

- `quickshare doctor` must report `ok` for Bluetooth, firewall and downloads.
- Logs: `~/.local/state/quickshare/bridge.log` and `backend.log`.
- If the phone shows **"Connecting..."** with no connection reaching the PC,
  toggle Airplane mode on the phone or restart its Bluetooth; this has been
  observed after a failed attempt.
- If BLE advertising fails at startup with `target object ... not present`,
  power-cycle Bluetooth on the PC and restart the shell.
- `RUST_LOG=info,rqs_lib=debug` gives verbose protocol logs.

## Scope and limits

- **Receive-focused.** The current backend does not send files from the PC.
- Reverse-engineered protocol; a Google change can break interoperability.
- No independent security review of the upstream protocol library exists.
- `rqs_lib` is GPL-3.0; the Rust wrapper follows that license.

## Documents

| File | Purpose |
|---|---|
| [`spec.md`](spec.md) | Technical specification and acceptance criteria |
| [`AGENT.md`](AGENT.md) | Instructions for agents working in this repo |
| [`docs/SESSION_HANDOFF.md`](docs/SESSION_HANDOFF.md) | Full session memory and next steps |
| `manifest.json` | Omarchy plugin registration |
| `Panel.qml` / `Model.js` | Bar widget, panel, helpers |
| `bin/quickshare-bridge` | Python bridge and decision socket |
| `backend/` | Rust receiver source |
| `i18n/en.json` | English strings |
| `install.sh` | Backend and prerequisites installer |
| `tests/` | Helper tests |
