# Session handoff — async.quickshare

This is the memory of the session that created the plugin. It is written for
the next agent so work can resume without rediscovery. Read `spec.md` and
`AGENT.md` first.

## 1. The question

The user asked, in order:

1. Can files be shared into a Linux system from Android Quick Share?
2. Can an Omarchy plugin (not a browser extension) support it?
3. Research whether it is possible and how.
4. Build it.
5. Debug why the phone could not find / connect to the PC.
6. Push the extension to GitHub.
7. Write README, AGENT.md, spec.md and this handoff.

## 2. Research conclusions (verified, not guesses)

- Google ships **no official Linux Quick Share client**. Supported platforms
  are Android 6+, ChromeOS 91+ and Windows. Google's own `google/nearby`
  README states **"Linux has no mediums implemented"**.
- Real community receivers exist and interoperate with the **stock Android
  share sheet** (no phone app):
  - `Martichou/rquickshare` (~3.7k★, upstream stale) — Wi‑Fi LAN/mDNS.
  - `nozwock/packet` (~1.2k★, Flathub) — Wi‑Fi LAN/mDNS.
  - `ignotusbucius/open-quickshare` (12★ at research time) — full stack:
    BLE `0xFEF3` GATT/L2CAP, Wi‑Fi LAN, Wi‑Fi Direct/hotspot, bidirectional.
  - `AuthenticSm1les/nearcast` — daemon with JSON-lines IPC, BLE + LAN +
    Wi‑Fi Direct, but very young.
  - `grishka/NearDrop` `PROTOCOL.md` is the foundational reverse engineering.
- Protocol essentials: mDNS `_FC9F5ED42C8A._tcp.local.` (SHA-256 of
  "NearbySharing"), BLE `0xFE2C` wake beacon / `0xFEF3` receiver advert and
  GATT service, 4-byte length-prefixed protobuf frames, UKEY2 (P-256 ECDH),
  SecureMessage (AES-256-CBC + HMAC-SHA256), 4-digit PIN derived from the
  auth string, `PairedKeyResult: UNABLE` fallback for third parties,
  `INTRODUCTION` → accept → `PAYLOAD_TRANSFER` chunks.
- "Contacts"/"Your devices" and cloud relays are impossible for third parties
  (Google account certificates / servers).

Full research notes were written to (outside the repo):
`/home/async/research/quick-share-official-and-protocol.md`
`/home/async/research/quick-share-linux-implementations.md`

## 3. What was built

Plugin directory: `~/.config/omarchy/plugins/async.quickshare`

| File | Role |
|---|---|
| `manifest.json` | Omarchy plugin id `async.quickshare`, bar-widget kind |
| `Panel.qml` | Bar ↗ icon, KeyboardPanel, PIN/accept card, scan, progress, history, ShellIpc with `manageIpc: false` |
| `Model.js` | JSON parse, byte formatting, file names, status colors/plurals helpers |
| `bin/quickshare-bridge` | Python supervisor + JSON event normalizer + decision socket |
| `bin/quickshare-ask` | Legacy `--ask` shim for the old CLI backend |
| `backend/` | Rust `quickshare-rx` wrapper around `rqs_lib` |
| `i18n/en.json`, `install.sh`, `README.md`, `spec.md`, `AGENT.md`, `tests/` | Support files |

Architecture: QML → Python bridge (JSON lines) → Rust receiver (stdin/stdout
JSON lines). The receiver advertises BLE `0xFEF3`, performs UKEY2/SecureMessage,
shows a 4-digit PIN and requires explicit accept/decline. No auto-accept.

## 4. Setup performed on this machine

- Plugin registered in `~/.config/omarchy/shell.json` under `bar.layout.right`
  (replaced a dead `macondo.quickshare` entry that had been present).
- Rust toolchain installed via rustup into `~/.cargo` (minimal profile);
  `protoc` 29.3 installed into `~/.local/bin`.
- `quickshare-rx` built and installed to `~/.local/bin/quickshare-rx`.
  Source/vendor tree: `~/.local/share/quickshare-backend/{oqs-core,bridge-rs}`.
- Firewall rule added by the user:
  `sudo ufw allow 53318/tcp comment quickshare` — `quickshare doctor` reports
  OK for Bluetooth, firewall and downloads.
- Receiver advertised as **Omarchy Share** (default in the Python bridge via
  `RQS_DEVICE_NAME`). Earlier names tried: `Omarchy PC`, `QuickShare Test`.
- Logs: `~/.local/state/quickshare/bridge.log`, `backend.log`.
- SSH config and private keys were chmod'ed to `600` so `gh`/git SSH works.
- Repo created and pushed:
  `git@github.com:raghavdwd/omarchy-quickshare.git` (public, branch `master`).

## 5. Backend history (why the current one was chosen)

1. **`JaxonWright/quickshare` CLI** (built to `~/.local/bin/quickshare`).
   LAN/mDNS only. Phone could see the PC after BLE wake but connections
   failed; phone hotspot blocks/restricts mDNS. Rejected.
2. **`AuthenticSm1les/nearcast`** (built to `~/.local/bin/nearcastd`).
   BLE advertising worked (log: "advertising over BLE (extended, 55 bytes)"),
   phone saw **Omarchy PC**, but **no connection ever reached the daemon** —
   no `incoming Bluetooth connection` log, no TCP. Rejected.
3. **`open-quickshare` `rx_service` example** (temporary, auto-accept,
   device name `QuickShare Test`) — **worked**: Samsung connected over
   `ble-l2cap`, PIN/consent flow ran, and `IMG-20261121-WA0021 (1).jpeg`
   (1,320,202 bytes) was saved to `~/Downloads/Quick Share` at 01:39.
4. **`quickshare-rx` wrapper** (current): same `rqs_lib`, but emits JSON
   events and requires consent via stdin. Built and installed.

## 6. Bugs found and fixed

- Python bridge wrote bytes to a **text-mode** stdin for the Rust backend:
  `decision: write() argument must be str, not bytes`. Accept never reached
  the backend. Fixed by writing `json.dumps(decision) + "\n"` (a string).
  Verified with `ctl accept test-id` → `{"ok": true}` and a `decision` event.
- nearcastd logs go to **stdout**, not stderr; the bridge was only draining
  stderr, so logs were invisible and the pipe could fill. Fixed by draining
  both pipes.
- `RUST_LOG` was not reaching the child. Fixed by passing an explicit `env=`
  in `spawn()`.
- Orphaned receiver processes held port 53318 after shell restarts. Fixed
  with `PR_SET_PDEATHSIG` in `preexec_fn`.
- Bar IPC collision warning fixed with `manageIpc: false` on the `Panel`.
- QML right-click Scan originally passed `--no-wake` (disabled BLE wake);
  removed.

## 7. Current state at pause

- Plugin loads cleanly; bridge `ping` responds; `quickshare-rx` is running and
  BLE advertising is active (`0xFEF3`, GATT service registered, L2CAP PSM 128).
- One real end-to-end receive succeeded with the temporary auto-accept
  control receiver, not with the final consenting plugin.
- The final plugin displayed a PIN once (PIN `5031`, from `Raghav's A27`,
  id `ble-weave`) at 01:45:51, but the Accept button hit the bytes/str bug.
- After that, repeated attempts showed **no connection attempt at all** in
  `backend.log` and no BlueZ activity. Even re-running the exact control
  receiver that had previously worked produced no connection. Conclusion at
  pause: **phone-side stale "Connecting" state**, not a PC code defect.
  Suggested fix: Airplane mode toggle / Bluetooth restart / phone reboot.
- Temporary control receivers were stopped. User said "no worries, pause the
  work for now".

## 8. Environment facts for the next agent

- Test phone: **Samsung Galaxy A27** (`Raghav's A27`), connected as hotspot
  host; laptop is a Wi‑Fi client on that hotspot (IP changed between
  `10.102.55.58` and `192.168.1.43`).
- Bluetooth controller: `94:BB:43:CD:BF:1D BumbleBee`, appears as `hci1`
  after power-cycle (was `hci0` earlier).
- BLE can transiently fail after restarts:
  `Couldn't init ReceiverGattServer / ReceiverAdvertiser: target object was
  either not present or removed`. Fix used: `bluetoothctl power off`, wait,
  power on, `omarchy restart shell`.
- The user must run passworded sudo commands themselves; the agent cannot.

## 9. Next steps (recommended order)

1. **Reproduce with a healthy phone**: ask the user to Airplane-toggle or
   reboot the Samsung, then send to **Omarchy Share** and confirm a `ask`
   event appears in `bridge.log`.
2. **Verify the fixed Accept path end to end**: after clicking Accept, expect
   `decision` → `progress` → `received` events and a new file in
   `~/Downloads/Quick Share`. Confirm Decline writes nothing.
3. **Add a BLE startup watchdog**: if backend logs contain
   `Couldn't init ReceiverAdvertiser`, restart the receiver after a few
   seconds (power-cycle may still be needed for BlueZ).
4. **Reduce log noise**: `info,rqs_lib=info` still produces many BWU lines;
   consider filtering.
5. **Optional**: implement PC→phone sending (not in current backend), or add
   a QR-code receive path.
6. Update `spec.md` acceptance criteria as each item is verified.

## 10. Useful commands

```sh
cd ~/.config/omarchy/plugins/async.quickshare
python3 -m py_compile bin/quickshare-bridge
node tests/model.test.mjs
omarchy restart shell
python3 bin/quickshare-bridge ping
python3 bin/quickshare-bridge ctl accept <id>
quickshare doctor
tail -f ~/.local/state/quickshare/bridge.log
tail -f ~/.local/state/quickshare/backend.log
journalctl --user | grep -i quickshare
git status --short --branch
```
