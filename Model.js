.pragma library

// Pure helpers for the Quick Share panel. No QML imports here so the logic
// stays easy to test on its own.

function parse(line) {
  if (!line) return null
  try {
    return JSON.parse(line)
  } catch (e) {
    return null
  }
}

function bytes(value) {
  var n = Number(value)
  if (!isFinite(n) || n < 0) n = 0
  if (n < 1024) return Math.round(n) + " B"
  var units = ["KB", "MB", "GB", "TB"]
  var i = -1
  do {
    n /= 1024
    i++
  } while (n >= 1024 && i < units.length - 1)
  return n.toFixed(n >= 100 ? 0 : 1) + " " + units[i]
}

function fileNames(files) {
  if (!files || !files.length) return ""
  var out = []
  for (var i = 0; i < files.length && i < 4; i++) {
    var f = files[i]
    if (typeof f === "string") out.push(f)
    else if (f && f.name) out.push(f.name)
    else if (f && f.fileName) out.push(f.fileName)
  }
  var text = out.join(", ")
  if (files.length > 4) text += " +" + (files.length - 4)
  return text
}

function short(value, limit) {
  var s = String(value == null ? "" : value)
  var n = limit || 40
  return s.length > n ? s.slice(0, n - 1) + "…" : s
}

function deviceName(device) {
  if (!device) return ""
  return String(device.name || device.id || "")
}

function stateLabel(state, backend, t) {
  if (state === "missing") return t("noBackend")
  if (state === "starting") return t("starting")
  if (state === "stopped") return t("stopped")
  if (state === "error") return t("error")
  if (state === "ready") return backend ? t("readyWith").arg(backend) : t("ready")
  return t("idle")
}

function statusColor(state, incoming, normal) {
  if (incoming) return "#F87171"
  if (state === "ready") return "#4ADE80"
  if (state === "missing" || state === "error" || state === "stopped") return "#FB923C"
  return normal
}

function percent(done, total) {
  var d = Number(done) || 0
  var t = Number(total) || 0
  if (t <= 0) return 0
  return Math.max(0, Math.min(1, d / t))
}
