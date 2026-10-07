import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import QtQuick
import qs.Commons
import qs.Ui
import "match.js" as Match

// Find an open window by typing.
//
// Opening reads every window and the monitors from hyprctl in one go and lists
// the windows most recently used first, with the previous window selected, so
// Super+. Enter flips back like Alt+Tab. Typing filters on title, app and
// workspace (match.js). Enter focuses the window wherever it is; Shift+Enter
// brings it to the workspace you are looking at first.
Item {
  id: root

  property var shell: null
  property var manifest: null

  property bool opened: false
  property string monitorName: ""
  property int here: 0              // active workspace id on the focused monitor
  property var all: []              // every window, most recent first
  property string query: ""
  property var results: Match.filter(all, query)
  property int selected: 0
  readonly property int maxRows: 9

  property color background: Color.menu.background
  property color foreground: Color.menu.text
  property color accent: Color.menu.selectedText
  property color scrim: Color.menu.scrim
  property color selectedBackground: Color.menu.selectedBackground
  property var borderSpec: Border.surfaceSpec("menu", "border", Color.menu.border, Math.max(1, Style.space(2)))
  property string fontFamily: Style.font.menuFamily
  property int pad: Style.spacing.panelPadding
  property int rowHeight: Style.space(44)

  function tint(c, a) { return Qt.rgba(c.r, c.g, c.b, a) }

  onQueryChanged: root.selected = 0

  // ------------------------------------------------------------ shell hooks

  function open(payloadJson) {
    root.query = ""
    if (!probeProc.running) probeProc.running = true
  }

  function close() {
    root.opened = false
  }

  function dismiss() {
    root.opened = false
    if (root.shell && typeof root.shell.hide === "function")
      root.shell.hide((root.manifest && root.manifest.id) || "dbarke.windows")
  }

  // ---------------------------------------------------------------- windows

  // Edge and Chrome web apps are classed msedge-<site>__<path>-<profile>.
  function webAppSite(cls) {
    var m = /^(?:msedge|chrome|chromium|brave)-([^_]+)__/.exec(cls)
    return m ? m[1].replace(/^www\./, "") : ""
  }

  function appFor(cls) {
    var entry = cls ? DesktopEntries.heuristicLookup(cls) : null
    var site = root.webAppSite(cls)
    var name = entry && entry.name ? entry.name : (site || cls || "Window")
    var icon = entry && entry.icon ? entry.icon : cls
    var lib = root.shell ? root.shell.appLibrary : null
    var src = lib && typeof lib.iconSource === "function" ? lib.iconSource(icon) : Quickshell.iconPath(icon, true)
    return { name: name, icon: src || Quickshell.iconPath("application-x-executable", true) }
  }

  function workspaceLabel(ws) {
    var name = String((ws && ws.name) || "")
    if (name.indexOf("special:") === 0) return name.slice(8) || "special"
    return name || String(ws ? ws.id : "")
  }

  function probed(text) {
    var data = null
    try { data = JSON.parse(text) } catch (e) { data = null }
    if (!data) return
    var mons = data.mons || []
    var focused = null
    for (var i = 0; i < mons.length; i++) if (mons[i].focused) focused = mons[i]
    root.monitorName = focused ? focused.name : (mons.length ? mons[0].name : "")
    root.here = focused && focused.activeWorkspace ? focused.activeWorkspace.id : 0

    var list = []
    var clients = data.clients || []
    for (var j = 0; j < clients.length; j++) {
      var c = clients[j]
      if (!c.mapped || !c.address) continue
      var app = root.appFor(c.class || c.initialClass)
      list.push({
        address: c.address,
        title: c.title || c.initialTitle || app.name,
        app: app.name,
        icon: app.icon,
        workspace: root.workspaceLabel(c.workspace),
        workspaceId: c.workspace ? c.workspace.id : 0,
        focus: typeof c.focusHistoryID === "number" && c.focusHistoryID >= 0 ? c.focusHistoryID : 9999
      })
    }
    list.sort(function(a, b) { return a.focus - b.focus })
    root.all = list
    // The current window is first; preselect the one before it.
    root.selected = list.length > 1 && list[0].focus === 0 ? 1 : 0
    root.opened = true
  }

  function move(delta) {
    var n = root.results.length
    if (n) root.selected = (root.selected + delta + n) % n
  }

  function activate(index, bringHere) {
    var w = root.results[index]
    if (!w) return
    var target = "address:" + w.address
    var code = ""
    if (bringHere && root.here > 0 && w.workspaceId !== root.here)
      code += "hl.dispatch(hl.dsp.window.move({ workspace = " + root.here + ", follow = false, window = '" + target + "' })); "
    code += "hl.dispatch(hl.dsp.focus({ window = '" + target + "' }))"
    root.dismiss()
    runProc.command = ["hyprctl", "eval", code]
    runProc.running = true
  }

  Process {
    id: probeProc
    command: ["sh", "-c",
      "printf '{\"mons\":'; hyprctl -j monitors; printf ',\"clients\":'; hyprctl -j clients; printf '}'"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.probed(text)
    }
  }

  Process { id: runProc }

  // One window per monitor, each bound to its own screen for good; it shows
  // on the focused one. A screen binding that follows the focused monitor
  // re-evaluates against destroyed screens at shutdown and crashes Quickshell.
  Variants {
    model: Quickshell.screens

    PanelWindow {
      id: panel
      required property var modelData
      screen: modelData
      visible: root.opened && root.monitorName === modelData.name
      onVisibleChanged: if (visible) Qt.callLater(function() { search.forceActiveFocus(); search.selectAll() })
      anchors { top: true; bottom: true; left: true; right: true }
      color: "transparent"
      WlrLayershell.namespace: "dbarke-windows"
      WlrLayershell.layer: WlrLayer.Overlay
      WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive
      exclusionMode: ExclusionMode.Ignore

      Rectangle {
        anchors.fill: parent
        color: root.scrim
      }

      MouseArea {
        anchors.fill: parent
        onClicked: root.dismiss()
      }

      BorderSurface {
        id: card
        anchors.horizontalCenter: parent.horizontalCenter
        y: Math.round(parent.height * 0.2)
        width: Math.min(parent.width - Style.gapsOut * 4, Style.space(640))
        height: content.implicitHeight + contentTopInset + contentBottomInset
        radius: Style.cornerRadius
        color: root.background
        borderSpec: root.borderSpec
        padding: root.pad

        MouseArea { anchors.fill: parent; onClicked: {} }

        Column {
          id: content
          x: card.contentLeftInset
          y: card.contentTopInset
          width: card.width - card.contentLeftInset - card.contentRightInset
          spacing: Style.spacing.md

          TextField {
            id: search
            width: parent.width
            foreground: root.foreground
            accent: root.accent
            font.family: root.fontFamily
            font.pixelSize: Style.font.title
            placeholderText: "Search windows"
            text: root.query
            onTextEdited: root.query = text

            Keys.priority: Keys.BeforeItem
            Keys.onPressed: function(event) {
              var k = event.key
              var ctrl = event.modifiers & Qt.ControlModifier
              if (k === Qt.Key_Escape) root.dismiss()
              else if (k === Qt.Key_Down || k === Qt.Key_Tab || (ctrl && (k === Qt.Key_N || k === Qt.Key_J))) root.move(1)
              else if (k === Qt.Key_Up || k === Qt.Key_Backtab || (ctrl && (k === Qt.Key_P || k === Qt.Key_K))) root.move(-1)
              else if (k === Qt.Key_Return || k === Qt.Key_Enter) root.activate(root.selected, event.modifiers & Qt.ShiftModifier)
              else return
              event.accepted = true
            }
          }

          ListView {
            id: list
            width: parent.width
            height: Math.min(count, root.maxRows) * root.rowHeight
            visible: count > 0
            clip: true
            model: root.results
            currentIndex: root.selected
            boundsBehavior: Flickable.StopAtBounds
            highlightMoveDuration: 0
            onCurrentIndexChanged: positionViewAtIndex(currentIndex, ListView.Contain)

            delegate: Rectangle {
              id: row
              required property var modelData
              required property int index
              readonly property bool current: index === root.selected
              width: list.width
              height: root.rowHeight
              radius: Style.cornerRadius
              color: current ? root.selectedBackground : (hover.containsMouse ? root.tint(root.foreground, 0.06) : "transparent")

              Image {
                id: icon
                x: Style.spacing.md
                anchors.verticalCenter: parent.verticalCenter
                width: Style.space(24)
                height: width
                sourceSize.width: width * 2
                sourceSize.height: height * 2
                source: row.modelData.icon
                fillMode: Image.PreserveAspectFit
                asynchronous: true
              }

              Text {
                id: ws
                anchors.right: parent.right
                anchors.rightMargin: Style.spacing.md
                anchors.verticalCenter: parent.verticalCenter
                text: row.modelData.workspace
                color: row.current ? root.accent : root.tint(root.foreground, 0.55)
                font.family: root.fontFamily
                font.pixelSize: Style.font.body
              }

              Column {
                anchors.left: icon.right
                anchors.leftMargin: Style.spacing.md
                anchors.right: ws.left
                anchors.rightMargin: Style.spacing.md
                anchors.verticalCenter: parent.verticalCenter

                Text {
                  width: parent.width
                  text: row.modelData.title
                  elide: Text.ElideRight
                  color: row.current ? root.accent : root.foreground
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.body
                }

                Text {
                  width: parent.width
                  text: row.modelData.app
                  elide: Text.ElideRight
                  color: root.tint(row.current ? root.accent : root.foreground, 0.6)
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.bodySmall
                }
              }

              MouseArea {
                id: hover
                anchors.fill: parent
                hoverEnabled: true
                onClicked: function(mouse) { root.activate(row.index, mouse.modifiers & Qt.ShiftModifier) }
              }
            }
          }

          Text {
            width: parent.width
            visible: list.count === 0
            text: root.all.length ? "No window matches" : "No open windows"
            color: root.tint(root.foreground, 0.6)
            font.family: root.fontFamily
            font.pixelSize: Style.font.body
          }

          Text {
            width: parent.width
            text: "Enter  go to   ·   Shift+Enter  bring here   ·   ↑↓  select   ·   Esc  close"
            color: root.tint(root.foreground, 0.5)
            font.family: root.fontFamily
            font.pixelSize: Style.font.bodySmall
            elide: Text.ElideRight
          }
        }
      }
    }
  }
}
