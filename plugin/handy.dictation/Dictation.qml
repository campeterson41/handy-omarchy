import QtQuick
import Quickshell
import Quickshell.Io
import qs.Ui
import qs.Commons

BarWidget {
  id: root
  moduleName: "handy.dictation"
  property string phase: "idle"
  property string stage: "idle"
  property var levels: [0, 0, 0, 0, 0, 0, 0]
  property real pendingStopUntil: 0
  property real updatedAt: 0
  property real now: Date.now()
  readonly property bool fresh: now - updatedAt < 3000
  readonly property bool recording: fresh && phase === "recording"
  readonly property bool processing: fresh && phase === "processing"
  visible: recording || processing
  implicitWidth: visible ? 26 : 0
  implicitHeight: Style.bar.statusSlot

  function showStopRequested() {
    if (!root.recording) return
    root.pendingStopUntil = Date.now() + 800
    root.phase = "processing"
    root.stage = "stopping"
    root.updatedAt = Date.now()
    root.now = Date.now()
  }
  IpcHandler {
    target: "handy.dictation"
    function stopRequested(): void { root.broadcast("showStopRequested") }
    function status(): string { return root.phase }
  }

  FileView {
    id: state
    path: Quickshell.env("XDG_RUNTIME_DIR") + "/handy-bar.json"
    watchChanges: true
    printErrors: false
    onFileChanged: reload()
    onLoaded: {
      try {
        var data = JSON.parse(text())
        if (data.phase === "recording" && Date.now() < root.pendingStopUntil) return
        root.phase = data.phase
        root.stage = data.stage || "transcribing"
        root.levels = data.levels
        root.updatedAt = Number(data.at) * 1000
        root.now = Date.now()
      } catch (e) { root.phase = "idle" }
    }
  }
  Timer {
    interval: 100
    running: true
    repeat: true
    onTriggered: { root.now = Date.now(); state.reload() }
  }
  BarIconButton {
    id: button
    bar: root.bar
    anchors.fill: parent
    slotSize: 26
    opticalSize: 22
    tooltipText: root.recording ? "Recording your voice" : root.processing ? (root.stage === "stopping" ? "Finishing recording" : root.stage === "cleanup" ? "Cleaning up dictation" : root.stage === "pasting" ? "Pasting dictation" : "Transcribing your voice") : "Dictation ready"
    onTooltipTextChanged: { if (tooltipHovered && bar) bar.showTooltip(button, tooltipText) }
    onPressed: function(mouseButton) {
      if (mouseButton === Qt.LeftButton)
        Quickshell.execDetached([Quickshell.env("HOME") + "/.local/bin/handy-toggle"])
    }
    iconComponent: Component {
      Item {
        Canvas {
          id: spinner
          anchors.centerIn: parent
          width: 14; height: 14
          visible: root.processing
          onPaint: {
            var ctx = getContext("2d")
            ctx.clearRect(0, 0, width, height)
            ctx.lineWidth = 1.6
            ctx.strokeStyle = button.foreground
            ctx.lineCap = "round"
            ctx.beginPath()
            ctx.arc(7, 7, 5.3, 0, Math.PI * 1.5)
            ctx.stroke()
          }
          onVisibleChanged: if (visible) requestPaint()
          Connections {
            target: button
            function onForegroundChanged() { spinner.requestPaint() }
          }
          RotationAnimator on rotation {
            from: 0; to: 360; duration: 900
            loops: Animation.Infinite
            running: root.processing
          }
        }
        Row {
          visible: root.recording
          anchors.centerIn: parent
          spacing: 3
          Rectangle {
            anchors.verticalCenter: parent.verticalCenter
            width: 5; height: 5; radius: 2.5
            color: root.recording ? "#dc4a3d" : root.processing ? "#d9ac68" : button.foreground
            opacity: root.recording || root.processing ? 1 : 0.35
          }
          Row {
            anchors.verticalCenter: parent.verticalCenter
            spacing: 1
            Repeater {
              model: 4
              Rectangle {
                required property int index
                anchors.verticalCenter: parent.verticalCenter
                width: 2
                height: root.recording ? 2 + 13 * Math.min(1, Number(root.levels[index * 2]) || 0) : 2
                radius: 1
                color: button.foreground
                opacity: root.recording ? 0.95 : root.processing ? 0.65 : 0.25
                Behavior on height { NumberAnimation { duration: 75 } }
              }
            }
          }
        }
      }
    }
  }
}
