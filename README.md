# async.quickshare — Quick Share plugin for Omarchy

An Omarchy bar widget and panel for Android Quick Share. The QML plugin is
only the UI: all Bluetooth, Wi‑Fi, protocol and crypto work lives in a
headless receiver so the shell stays small and the protocol can be updated
independently.

Confirmed working with a Samsung Galaxy A27 sending to an Omarchy laptop that
is connected to the phone's hotspot.

## How it works

```
Quickshell panel ──JSON lines──> bin/quickshare-bridge ──stdin/stdout──> quickshare-rx
        │                                │                                  │
        ├─ accept/decline                ├─ normalizes events              BLE 0xFEF3 GATT/L2CAP
        └─ status/progress               └─ decision socket                + mDNS / Wi-Fi LAN
```

- `Panel.qml` — bar icon (↗), incoming PIN card with Accept/Decline, scan,
  transfer progress and recent transfers.
- `bin/quickshare-bridge` — Python bridge. Starts the receiver, forwards
  events to the panel as JSON lines and relays Accept/Decline back to it.
- `backend/` — small Rust wrapper around `rqs_lib` from
  [open-quickshare](https://github.com/ignotusbucius/open-quickshare). It
  exposes the receiver as a JSON-lines process and requires explicit consent
  for every inbound transfer (no auto-accept).
- `Model.js`, `i18n/en.json` — pure helpers and strings.

The receiver advertises a Quick Share endpoint over BLE (`0xFEF3`) and uses
UKEY2 + SecureMessage with a 4-digit PIN, so discovery works even when mDNS
is unreliable (for example on a phone hotspot). "Everyone" visibility is
required; Contacts/Your devices need Google-account certificates that a
third-party client cannot provide.

## Install

```sh
cd ~/.config/omarchy/plugins/async.quickshare
./install.sh
```

The installer puts `quickshare-rx` in `~/.local/bin`, builds the protocol
library under `~/.local/share/quickshare-backend`, enables Avahi and
Bluetooth, and opens TCP 53318 in ufw if it is active. Review it before
running — it uses sudo only for services and the firewall rule.

Then add the plugin to `~/.config/omarchy/shell.json` under `bar.layout.right`:

```json
{ "id": "async.quickshare" }
```

Reload with `omarchy restart shell`.

## Use

1. Set Quick Share visibility on the phone to **Everyone**.
2. Open the phone's share sheet and choose the PC (advertised as
   **Omarchy Share** by default).
3. The panel opens with the sender, file list and 4-digit PIN. Confirm the
   PIN matches the phone and click **Accept**.
4. Received files land in `~/Downloads/Quick Share`.

Right-click the bar icon for an explicit scan. Recent transfers and progress
are shown in the panel.

Logs for troubleshooting: `~/.local/state/quickshare/bridge.log` and
`backend.log`. Run `RUST_LOG=info,rqs_lib=debug` via the bridge environment
for verbose protocol logs.

## Notes and limitations

- Receive-focused: the backend does not send files. Use the `quickshare` CLI
  or another tool for sending from the PC.
- If the phone gets stuck on "Connecting" after a failed attempt, toggle its
  Airplane mode or restart Bluetooth on the phone.
- This is a reverse-engineered protocol. A Google change can break it, and
  no independent security review exists for the upstream protocol library.
- `rqs_lib` is GPL-3.0; this plugin's Rust wrapper follows that license.

## Layout

| File | Purpose |
|---|---|
| `manifest.json` | Omarchy plugin registration |
| `Panel.qml` | Bar widget, panel, IPC, process management |
| `Model.js` | Parsing and formatting helpers |
| `bin/quickshare-bridge` | Backend bridge and decision socket |
| `bin/quickshare-ask` | Legacy CLI backend `--ask` hook |
| `backend/` | Rust receiver source (`quickshare-rx`) |
| `i18n/en.json` | English strings |
| `install.sh` | Backend and prerequisites installer |
| `tests/` | Model helper tests |
