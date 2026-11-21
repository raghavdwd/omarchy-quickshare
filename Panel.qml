import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Commons as Commons
import qs.Ui
import "Model.js" as Model

Panel {
  id: root
  moduleName: "async.quickshare"
  ipcTarget: "async.quickshare"
  // Own the single IPC handler for this target; the shell would otherwise
  // auto-create one and our ShellIpc below would be ignored.
  manageIpc: false

  Commons.Translations {
    id: strings
    directory: Qt.resolvedUrl("i18n")
  }

  readonly property string pluginDir: Qt.resolvedUrl(".").toString().replace(/^file:\/\//, "").replace(/\/$/, "")
  readonly property string bridge: pluginDir + "/bin/quickshare-bridge"
  readonly property string python: "python3"

  property string backend: ""
  property string state: "idle"
  property string statusMessage: ""
  property var incoming: null
  property bool scanning: false
  readonly property bool hasIncoming: root.incoming !== null

  ListModel { id: devices }
  ListModel { id: activity }

  function t(key) { return strings.t(key) }

  function statusText() {
    return Model.stateLabel(root.state, root.backend, t)
  }

  function notify(title, body) {
    var clean = String(body || "").replace(/[<>&]/g, "")
    Quickshell.execDetached(["notify-send", title, Model.short(clean, 140)])
  }

  function onLine(data) {
    var msg = Model.parse(data)
    if (!msg) return

    switch (msg.t) {
      case "status":
        root.backend = msg.backend || ""
        root.state = msg.state || "idle"
        root.statusMessage = msg.message || ""
        break
      case "ask":
        root.incoming = msg
        notify(t("incomingTitle"), (msg.from || "") + " · " + Model.fileNames(msg.files))
        root.open()
        break
      case "device":
        upsertDevice(msg)
        break
      case "gone":
        removeDevice(String(msg.id || ""))
        break
      case "progress":
        updateActivity(msg)
        break
      case "received":
        addActivity(t("received").arg(msg.from || ""), msg, true)
        root.incoming = null
        break
      case "result":
        if (msg.code === "declined" || msg.code === "cancelled") root.incoming = null
        addActivity(resultLabel(msg.code), msg, msg.code === "delivered")
        break
      case "error":
        root.statusMessage = Model.short(msg.message, 160)
        break
    }
  }

  function resultLabel(code) {
    switch (code) {
      case "delivered": return t("delivered").arg("")
      case "declined": return t("declined")
      case "cancelled": return t("cancelled")
      case "failed": return t("failed")
      default: return code || t("failed")
    }
  }

  function upsertDevice(msg) {
    var id = String(msg.id || "")
    if (!id) return
    var data = {
      id: id,
      name: Model.deviceName(msg),
      kind: msg.kind || "",
      addr: msg.addr || ""
    }
    for (var i = 0; i < devices.count; i++) {
      if (devices.get(i).id === id) {
        devices.set(i, data)
        return
      }
    }
    devices.append(data)
  }

  function removeDevice(id) {
    if (!id) return
    for (var i = devices.count - 1; i >= 0; i--) {
      if (devices.get(i).id === id) {
        devices.remove(i)
        return
      }
    }
  }

  function updateActivity(msg) {
    var id = String(msg.id || "")
    if (!id) return
    for (var i = 0; i < activity.count; i++) {
      var row = activity.get(i)
      if (row.id === id) {
        activity.set(i, {
          id: id,
          label: row.label,
          done: msg.done || 0,
          total: msg.total || 0,
          incoming: row.incoming
        })
        return
      }
    }
    activity.insert(0, {
      id: id,
      label: t("receiving"),
      done: msg.done || 0,
      total: msg.total || 0,
      incoming: true
    })
    if (activity.count > 8) activity.remove(activity.count - 1)
  }

  function addActivity(label, msg, incoming) {
    activity.insert(0, {
      id: String(msg.id || ("local" + Date.now())),
      label: label,
      done: msg.bytes || 0,
      total: msg.bytes || 0,
      incoming: !!incoming
    })
    if (activity.count > 8) activity.remove(activity.count - 1)
  }

  function decide(accept) {
    if (!root.incoming) return
    ctlProc.command = [root.python, root.bridge, "ctl", accept ? "accept" : "decline", String(root.incoming.id || "")]
    ctlProc.running = true
    root.incoming = null
  }

  function scanDevices() {
    if (root.scanning) return
    root.scanning = true
    devices.clear()
    scanProc.running = true
  }

  ShellIpc {
    target: "async.quickshare"

    function open() { root.open() }
    function close() { root.close() }
    function toggle() { root.toggle() }
    function scan() { root.scanDevices() }
  }

  Process {
    id: bridgeProc
    command: [root.python, root.bridge, "watch"]
    stdout: SplitParser {
      onRead: function(data) { root.onLine(data) }
    }
    onExited: function(code) {
      root.state = "stopped"
      restartTimer.restart()
    }
  }

  Process { id: ctlProc }

  Process {
    id: scanProc
    command: [root.python, root.bridge, "scan"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: function() {
        var lines = text.split("\n")
        for (var i = 0; i < lines.length; i++) root.onLine(lines[i])
      }
    }
    onExited: function() { root.scanning = false }
  }

  Timer {
    id: restartTimer
    interval: 3000
    repeat: false
    onTriggered: bridgeProc.running = true
  }

  Component.onCompleted: bridgeProc.running = true

  visible: true
  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: "\u2197"
    labelText: root.hasIncoming ? "!" : ""
    useActiveColor: false
    foreground: Model.statusColor(root.state, root.hasIncoming, root.bar ? root.bar.foreground : Commons.Color.foreground)
    slotSize: Style.bar.statusSlot
    tooltipText: root.statusText() + (root.hasIncoming ? " · " + t("incomingTitle") : "")
    onPressed: function(b) {
      if (b === Qt.RightButton) root.scanDevices()
      else root.toggle()
    }
  }

  KeyboardPanel {
    id: panel
    anchorItem: button
    owner: root
    bar: root.bar
    open: root.opened
    focusTarget: panel.loadedContent
    contentWidth: panel.fittedContentWidth(Style.space(420))
    contentHeight: panel.fittedContentHeight(panel.loadedContentHeight)

    content: PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      implicitHeight: column.implicitHeight
      onCloseRequested: root.close()
      onMoveRequested: function(dx, dy) {}
      onActivateRequested: {}
      onTabRequested: function(direction) { root.switchPanel(direction) }

      Column {
        id: column
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        spacing: Style.space(12)

        // Header
        Row {
          width: parent.width
          spacing: Style.space(12)

          Text {
            textFormat: Text.PlainText
            text: "\u2197"
            color: Model.statusColor(root.state, root.hasIncoming, root.bar.foreground)
            font.family: root.bar.fontFamily
            font.pixelSize: Style.font.display
            anchors.verticalCenter: parent.verticalCenter
          }

          Column {
            anchors.verticalCenter: parent.verticalCenter
            spacing: Style.space(2)

            Text {
              textFormat: Text.PlainText
              text: strings.t("title")
              color: root.bar.foreground
              font.family: root.bar.fontFamily
              font.pixelSize: Style.font.title
              font.bold: true
            }

            Text {
              textFormat: Text.PlainText
              text: root.statusText()
              color: Qt.darker(root.bar.foreground, 1.4)
              font.family: root.bar.fontFamily
              font.pixelSize: Style.font.caption
            }
          }
        }

        // Backend / hint line
        Text {
          visible: root.statusMessage.length > 0
          textFormat: Text.PlainText
          text: Model.short(root.statusMessage, 160)
          color: root.bar.foreground
          opacity: 0.66
          width: parent.width
          wrapMode: Text.Wrap
          font.family: root.bar.fontFamily
          font.pixelSize: Style.font.bodySmall
        }

        // Incoming transfer card
        Rectangle {
          visible: root.hasIncoming
          width: parent.width
          implicitHeight: incomingColumn.implicitHeight + Style.space(20)
          radius: Style.cornerRadius
          color: Qt.rgba(0.98, 0.45, 0.45, 0.12)

          Column {
            id: incomingColumn
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.margins: Style.space(10)
            spacing: Style.space(8)

            Text {
              textFormat: Text.PlainText
              text: strings.t("incomingTitle")
              color: root.bar.foreground
              font.family: root.bar.fontFamily
              font.pixelSize: Style.font.body
              font.bold: true
            }

            Text {
              textFormat: Text.PlainText
              text: strings.t("from") + ": " + Model.short(root.incoming ? root.incoming.from : "", 40)
              color: root.bar.foreground
              opacity: 0.8
              font.family: root.bar.fontFamily
              font.pixelSize: Style.font.caption
            }

            Text {
              textFormat: Text.PlainText
              text: root.incoming ? String(root.incoming.pin || "") : ""
              color: "#F87171"
              font.family: root.bar.fontFamily
              font.pixelSize: Style.font.displayLarge
              font.bold: true
              font.letterSpacing: 4
            }

            Text {
              textFormat: Text.PlainText
              text: strings.t("pinHint")
              color: root.bar.foreground
              opacity: 0.6
              font.family: root.bar.fontFamily
              font.pixelSize: Style.font.caption
            }

            Text {
              textFormat: Text.PlainText
              text: strings.t("files") + ": " + Model.short(Model.fileNames(root.incoming ? root.incoming.files : []), 90)
              color: root.bar.foreground
              opacity: 0.8
              width: parent.width
              wrapMode: Text.Wrap
              font.family: root.bar.fontFamily
              font.pixelSize: Style.font.caption
            }

            Row {
              spacing: Style.space(8)

              Button {
                text: strings.t("accept")
                bordered: true
                active: true
                foreground: root.bar.foreground
                fontFamily: root.bar.fontFamily
                fontSize: Style.font.bodySmall
                horizontalPadding: Style.spacing.controlPaddingX
                verticalPadding: Style.spacing.controlPaddingY
                onClicked: root.decide(true)
              }

              Button {
                text: strings.t("decline")
                bordered: true
                foreground: root.bar.foreground
                fontFamily: root.bar.fontFamily
                fontSize: Style.font.bodySmall
                horizontalPadding: Style.spacing.controlPaddingX
                verticalPadding: Style.spacing.controlPaddingY
                onClicked: root.decide(false)
              }
            }
          }
        }

        PanelSeparator { foreground: root.bar.foreground }

        // Nearby devices
        PanelSectionHeader {
          text: strings.t("nearby")
          foreground: root.bar.foreground
          fontFamily: root.bar.fontFamily
        }

        Button {
          text: root.scanning ? strings.t("scanning") : strings.t("scan")
          bordered: true
          enabled: !root.scanning
          foreground: root.bar.foreground
          fontFamily: root.bar.fontFamily
          fontSize: Style.font.bodySmall
          horizontalPadding: Style.spacing.controlPaddingX
          verticalPadding: Style.spacing.controlPaddingY
          onClicked: root.scanDevices()
        }

        Column {
          width: parent.width
          spacing: Style.space(4)
          visible: devices.count > 0

          Repeater {
            model: devices

            Row {
              width: parent.width
              spacing: Style.space(8)

              Text {
                textFormat: Text.PlainText
                text: "•"
                color: "#4ADE80"
                font.family: root.bar.fontFamily
                font.pixelSize: Style.font.body
                anchors.verticalCenter: parent.verticalCenter
              }

              Text {
                textFormat: Text.PlainText
                text: Model.short(model.name, 36)
                color: root.bar.foreground
                font.family: root.bar.fontFamily
                font.pixelSize: Style.font.bodySmall
                anchors.verticalCenter: parent.verticalCenter
              }

              Text {
                textFormat: Text.PlainText
                text: Model.short(model.addr, 32)
                color: root.bar.foreground
                opacity: 0.5
                font.family: root.bar.fontFamily
                font.pixelSize: Style.font.caption
                anchors.verticalCenter: parent.verticalCenter
              }
            }
          }
        }

        Text {
          visible: devices.count === 0 && !root.scanning
          textFormat: Text.PlainText
          text: strings.t("noDevices")
          color: root.bar.foreground
          opacity: 0.6
          width: parent.width
          wrapMode: Text.Wrap
          font.family: root.bar.fontFamily
          font.pixelSize: Style.font.caption
        }

        PanelSeparator { foreground: root.bar.foreground }

        // Recent activity
        PanelSectionHeader {
          text: strings.t("activity")
          foreground: root.bar.foreground
          fontFamily: root.bar.fontFamily
        }

        Repeater {
          model: activity

          Column {
            width: parent.width
            spacing: Style.space(4)

            Text {
              textFormat: Text.PlainText
              text: Model.short(model.label, 60)
              color: root.bar.foreground
              font.family: root.bar.fontFamily
              font.pixelSize: Style.font.caption
            }

            Item {
              width: parent.width
              height: Style.space(4)

              Rectangle {
                anchors.fill: parent
                radius: height / 2
                color: Qt.rgba(root.bar.foreground.r, root.bar.foreground.g, root.bar.foreground.b, 0.12)
              }

              Rectangle {
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                height: parent.height
                radius: height / 2
                width: Math.max(height, parent.width * Model.percent(model.done, model.total))
                color: model.incoming ? "#4ADE80" : "#60A5FA"

                Behavior on width {
                  NumberAnimation {
                    duration: Style.duration(180)
                    easing.type: Easing.OutCubic
                  }
                }
              }
            }
          }
        }

        Text {
          visible: activity.count === 0
          textFormat: Text.PlainText
          text: strings.t("noActivity")
          color: root.bar.foreground
          opacity: 0.6
          font.family: root.bar.fontFamily
          font.pixelSize: Style.font.caption
        }
      }
    }
  }
}
