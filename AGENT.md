# AGENT.md — working rules for this repository

Read this before changing anything. Read `spec.md` for the contract and
`docs/SESSION_HANDOFF.md` for what has already been tried.

## What this repo is

An Omarchy Quickshell plugin plus a headless Rust Quick Share receiver. Three
process boundaries matter:

1. `Panel.qml` runs **inside the long-lived, unsandboxed Omarchy shell**.
2. `bin/quickshare-bridge` is a Python process started by QML; it owns the
   receiver and the decision socket.
3. `quickshare-rx` (built from `backend/`) is the Rust process that speaks the
   Quick Share protocol and emits/consumes JSON lines.

Do not move protocol work into QML. The shell is for display and input only.

## Environment rules

- Edit files **only** in this repo / `~/.config/`. Never edit
  `/usr/share/omarchy/` — it is package-owned and resets on update.
- The plugin id is `async.quickshare`. It is registered in
  `~/.config/omarchy/shell.json` under `bar.layout.right`.
- Files saved under `~/.config/omarchy/plugins/` hot-reload automatically.
  Force with `omarchy-shell shell rescanPlugins` if needed; use
  `omarchy restart shell` after changing `shell.json` or backend binaries.
- The Omarchy shell logs to the user journal:
  `journalctl --user | grep -i quickshare`.

## Coding conventions

- QML: set `textFormat: Text.PlainText` on every `Text` that displays data
  from a device, file, network or process. Nothing untrusted goes into an
  AutoText sink.
- Strings belong in `i18n/en.json`, read through `Commons.Translations`.
  Keep them whole with `%1` placeholders; never concatenate translated
  fragments.
- Motion: use `Style.duration(ms)`, `Style.easeOut` or `Easing.OutCubic`;
  keep entrances ~180 ms and exits ~120 ms. No scale-from-zero, no bounce.
- Reuse `qs.Ui` components (`Panel`, `BarIconButton`, `KeyboardPanel`,
  `PanelKeyCatcher`, `PanelSectionHeader`, `PanelSeparator`, `Button`) and
  `qs.Commons` tokens. Do not hand-roll a bar widget.
- Python bridge: emit one JSON object per line, flush every line, and keep a
  local copy in `~/.local/state/quickshare/bridge.log`.
- Never auto-accept an inbound transfer. Consent must come from the panel.
  The only auto-accepting executable was a temporary diagnostic tool and is
  not part of this repo.

## Validation before pushing

```sh
python3 -m py_compile bin/quickshare-bridge
node tests/model.test.mjs
( cd backend && cargo check )          # needs rqs_lib sibling, see install.sh
omarchy restart shell                  # in a desktop session
python3 bin/quickshare-bridge ping     # must return {"ok": true}
```

Check `journalctl --user` for QML errors and
`~/.local/state/quickshare/bridge.log` for runtime events.

## Git / releases

- Default branch `master`, remote `origin` →
  `github.com/raghavdwd/omarchy-quickshare.git`.
- Commits should be small and descriptive. Do not commit state/log files,
  `target/`, `__pycache__/`, tokens, SSH keys or phone numbers.
- `gh` is authenticated as `raghavdwd`; SSH keys and `~/.ssh/config` are
  mode `600`. Keep them that way.

## Known traps

- Killing the bridge without killing its child can leave a receiver holding
  the TCP port. Children use `PR_SET_PDEATHSIG`; preserve that.
- BlueZ can refuse GATT/advertisement registration after a restart with
  `target object was either not present or removed`. Power-cycling Bluetooth
  fixes it; a startup watchdog is still on the wishlist.
- The phone may cache a failed device entry and show "Connecting..." without
  sending anything. Confirm in `backend.log` that a connection actually
  arrived before changing PC-side code.
- The Python bridge uses **text-mode** stdin for the Rust backend. Write
  strings, not bytes, to `_backend_stdin` (this bug already caused one bad
  Accept path).

## When in doubt

Prefer the smallest change that preserves explicit consent, the JSON-lines
contract, and Omarchy's UI conventions. Update `spec.md` when behavior
changes, and append notable findings to `docs/SESSION_HANDOFF.md`.
