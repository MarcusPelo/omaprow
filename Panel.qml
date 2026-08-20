import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui

Panel {
  id: root
  moduleName: "marcuspelo.omaprow"
  ipcTarget: "marcuspelo.omaprow"

  // ---- config

  readonly property string baseUrl: {
    var v = settings ? settings.baseUrl : undefined
    if (typeof v === "string" && v.length > 0) return v
    if (root.envBaseUrl) return root.envBaseUrl
    return "http://localhost:9696"
  }
  readonly property int pageSize: {
    var v = settings ? settings.pageSize : undefined
    return (typeof v === "number" && v >= 10) ? v : 100
  }
  readonly property int defaultCategoryId: {
    var v = settings ? settings.defaultCategoryId : undefined
    return (typeof v === "number") ? v : 0
  }

  readonly property color fg: root.bar ? root.bar.foreground : Color.foreground
  readonly property color dim: Qt.darker(fg, 1.45)
  readonly property string fontFamily: root.bar ? root.bar.fontFamily : "JetBrainsMono Nerd Font"
  readonly property string barIcon: "" // nf-fa-search

  // ---- credentials

  property string apiKey: ""
  property string envBaseUrl: ""
  property bool apiKeyLoaded: false

  // Sent over each curl process's stdin via -K - (see the Process blocks
  // below) instead of a -H argument, so the API key never appears in argv.
  function apiKeyHeaderConfig() {
    return 'header = "X-Api-Key: ' + root.apiKey + '"\n'
  }

  function parseEnv(raw) {
    var lines = String(raw || "").split("\n")
    for (var i = 0; i < lines.length; i++) {
      var line = lines[i].trim()
      if (!line || line.indexOf("#") === 0) continue
      var eq = line.indexOf("=")
      if (eq < 0) continue
      var key = line.substring(0, eq).trim()
      var value = line.substring(eq + 1).trim().replace(/^["']|["']$/g, "")
      if (key === "API_KEY") root.apiKey = value
      else if (key === "URL_BASE") root.envBaseUrl = value
    }
    apiKeyLoaded = true
  }

  // ---- categories

  readonly property var categoryOptions: [
    { id: 0, label: "All" },
    { id: 1000, label: "Consoles" },
    { id: 4000, label: "PC" },
    { id: 2000, label: "Movies" },
    { id: 5000, label: "TV" },
    { id: 7000, label: "Books" },
    { id: 3000, label: "Audio" }
  ]

  property int categoryId: root.defaultCategoryId

  function categoryLabel(id) {
    for (var i = 0; i < root.categoryOptions.length; i++)
      if (root.categoryOptions[i].id === id) return root.categoryOptions[i].label
    return "All"
  }

  // ---- search

  property string viewMode: "search"
  property string searchQuery: ""
  property var results: []
  property bool searching: false
  property string searchError: ""

  function switchView(mode) {
    root.viewMode = mode
    if (mode === "history" && root.historyRecords.length === 0 && !root.historyLoading)
      root.fetchHistory()
  }

  // ---- settings

  property string draftBaseUrl: ""
  property string settingsStatusText: ""

  function openSettingsView() {
    root.viewMode = "settings"
    root.draftBaseUrl = root.baseUrl
    root.settingsStatusText = ""
  }

  function canPersistSettings() {
    return !!(root.bar && root.bar.shell && typeof root.bar.shell.updateEntryInline === "function")
  }

  function saveSettings() {
    var url = String(root.draftBaseUrl || "").trim()
    if (!url) url = root.envBaseUrl || "http://localhost:9696"
    var next = { baseUrl: url, pageSize: root.pageSize, defaultCategoryId: root.defaultCategoryId }

    root.draftBaseUrl = url
    root.settings = next

    if (root.canPersistSettings()) {
      root.bar.shell.updateEntryInline(root.moduleName, next)
      root.settingsStatusText = "Saved"
    } else {
      root.settingsStatusText = "Saved for this session only (bar unavailable)"
    }

    root.searchError = ""
    root.historyError = ""
  }

  function performSearch() {
    if (!root.apiKeyLoaded) return
    if (!root.apiKey) {
      root.searchError = "API key not configured in .env"
      return
    }
    if (searchProc.running) return
    root.searching = true
    root.searchError = ""
    root.grabStatus = ({})
    var url = root.baseUrl + "/api/v1/search?type=search&limit=" + root.pageSize
    if (root.searchQuery) url += "&query=" + encodeURIComponent(root.searchQuery)
    if (root.categoryId !== 0) url += "&categories=" + root.categoryId
    searchProc.command = ["curl", "-fsS", "--max-time", "30", "-K", "-", url]
    searchProc.stdinEnabled = true
    searchProc.running = true
  }

  function handleSearchResults(raw) {
    root.searching = false
    try {
      var data = JSON.parse(String(raw || ""))
      root.results = Array.isArray(data) ? data : []
    } catch (e) {
      root.results = []
      root.searchError = "Failed to read Prowlarr response"
    }
  }

  // ---- sort

  property string sortKey: "age"
  property int sortDir: 1

  function sortValue(r, key) {
    if (key === "age") return Number(r.ageMinutes || 0)
    if (key === "title") return String(r.title || "").toLowerCase()
    if (key === "size") return Number(r.size || 0)
    if (key === "grabs") return Number(r.grabs || 0)
    if (key === "peers") return Number(r.seeders || 0)
    if (key === "category") return root.categoryName(r)
    if (key === "indexer") return String(r.indexer || "").toLowerCase()
    return 0
  }

  property var sortedResults: {
    var list = root.results.slice()
    var key = root.sortKey
    var dir = root.sortDir
    list.sort(function(a, b) {
      var va = root.sortValue(a, key)
      var vb = root.sortValue(b, key)
      if (va < vb) return -1 * dir
      if (va > vb) return 1 * dir
      return 0
    })
    return list
  }

  function setSort(key) {
    if (root.sortKey === key) {
      root.sortDir = -root.sortDir
    } else {
      root.sortKey = key
      root.sortDir = (key === "title" || key === "category" || key === "indexer") ? 1 : -1
    }
  }

  readonly property var sortOptions: [
    { value: "age", label: "Age" },
    { value: "title", label: "Title" },
    { value: "size", label: "Size" },
    { value: "grabs", label: "Grabs" },
    { value: "peers", label: "Peers" },
    { value: "category", label: "Category" },
    { value: "indexer", label: "Indexer" }
  ]

  // ---- selection

  property var selectedGuids: ({})

  readonly property int selectedCount: {
    var n = 0
    for (var k in root.selectedGuids) if (root.selectedGuids[k]) n++
    return n
  }

  function toggleSelect(guid) {
    var next = Object.assign({}, root.selectedGuids)
    if (next[guid]) delete next[guid]
    else next[guid] = true
    root.selectedGuids = next
  }

  function clearSelection() {
    root.selectedGuids = ({})
  }

  // ---- grab

  property var grabQueue: []
  property string grabbingGuid: ""
  property var currentGrab: null
  property var grabStatus: ({})

  function grabRelease(release) {
    root.grabQueue = root.grabQueue.concat([release])
    root.processGrabQueue()
  }

  function grabSelected() {
    var chosen = root.sortedResults.filter(function(r) { return !!root.selectedGuids[r.guid] })
    if (chosen.length === 0) return
    root.grabQueue = root.grabQueue.concat(chosen)
    root.clearSelection()
    root.processGrabQueue()
  }

  function processGrabQueue() {
    if (root.grabbingGuid || root.grabQueue.length === 0) return
    var next = root.grabQueue[0]
    root.grabQueue = root.grabQueue.slice(1)
    root.grabbingGuid = next.guid
    root.currentGrab = next
    grabProc.command = ["curl", "-fsS", "--max-time", "20", "-X", "POST", "-K", "-",
      "-H", "Content-Type: application/json",
      "-d", JSON.stringify({ guid: next.guid, indexerId: next.indexerId }),
      root.baseUrl + "/api/v1/search"]
    grabProc.stdinEnabled = true
    grabProc.running = true
  }

  function handleGrabExit(code) {
    var guid = root.grabbingGuid
    var next = Object.assign({}, root.grabStatus)
    next[guid] = code === 0 ? "ok" : "error"
    root.grabStatus = next
    root.grabbingGuid = ""
    root.currentGrab = null
    root.processGrabQueue()
  }

  // ---- history

  property var historyRecords: []
  property bool historyLoading: false
  property string historyError: ""
  property int historyPage: 1
  readonly property int historyPageSize: 25
  property int historyTotal: 0

  function fetchHistory() {
    if (!root.apiKey || historyProc.running) return
    root.historyLoading = true
    root.historyError = ""
    var url = root.baseUrl + "/api/v1/history?page=" + root.historyPage
      + "&pageSize=" + root.historyPageSize + "&sortKey=date&sortDirection=descending"
    historyProc.command = ["curl", "-fsS", "--max-time", "15", "-K", "-", url]
    historyProc.stdinEnabled = true
    historyProc.running = true
  }

  function handleHistory(raw) {
    root.historyLoading = false
    try {
      var data = JSON.parse(String(raw || "")) || {}
      root.historyRecords = data.records || []
      root.historyTotal = data.totalRecords || 0
    } catch (e) {
      root.historyRecords = []
      root.historyError = "Failed to read Prowlarr response"
    }
  }

  function goHistoryPage(delta) {
    var next = Math.max(1, root.historyPage + delta)
    if (next === root.historyPage) return
    root.historyPage = next
    root.fetchHistory()
  }

  function eventLabel(eventType) {
    var map = {
      indexerQuery: "Search", indexerRss: "RSS", releaseGrabbed: "Grabbed",
      indexerAuth: "Auth", indexerQueryResult: "Query result"
    }
    return map[eventType] || eventType || "Event"
  }

  function eventColor(eventType) {
    if (eventType === "releaseGrabbed") return "#8fd694"
    if (eventType === "indexerQuery") return root.fg
    return root.dim
  }

  // ---- formatting

  function formatBytes(bytes) {
    var v = Number(bytes) || 0
    if (v < 1024) return v.toFixed(0) + " B"
    if (v < 1024 * 1024) return (v / 1024).toFixed(0) + " KiB"
    if (v < 1024 * 1024 * 1024) return (v / 1024 / 1024).toFixed(1) + " MiB"
    return (v / 1024 / 1024 / 1024).toFixed(1) + " GiB"
  }

  function formatAge(r) {
    var days = Number(r.age)
    if (days >= 1) return days + (days === 1 ? " day" : " days")
    var hours = Number(r.ageHours) || 0
    if (hours >= 1) return Math.round(hours) + "h"
    return Math.round(Number(r.ageMinutes) || 0) + "m"
  }

  function formatPeers(r) {
    return (Number(r.seeders) || 0) + " / " + (Number(r.leechers) || 0)
  }

  function categoryName(r) {
    if (r.categories && r.categories.length > 0 && r.categories[0].name)
      return r.categories[0].name
    return "-"
  }

  function flagsText(r) {
    return (r.indexerFlags && r.indexerFlags.length > 0) ? r.indexerFlags.join(", ") : "-"
  }

  // Only ever hand xdg-open a plain http(s) URL: infoUrl points at the
  // indexer's own release page and never carries the API key (unlike
  // downloadUrl, which embeds it — never open that one this way).
  function openExternalUrl(url) {
    if (!/^https?:\/\//i.test(String(url || ""))) return
    xdgOpenProc.command = ["xdg-open", url]
    xdgOpenProc.running = true
  }

  function triggerPress(button) {
    if (button === Qt.MiddleButton) {
      if (root.viewMode === "search") root.performSearch(); else root.fetchHistory()
      return
    }
    if (opened) close(); else open()
  }

  // ---- components

  component SelectBox: Rectangle {
    id: box
    property bool checked: false
    signal toggled()
    implicitWidth: 16
    implicitHeight: 16
    radius: 3
    color: "transparent"
    border.color: root.dim
    border.width: 1

    Text {
      anchors.centerIn: parent
      visible: box.checked
      text: "✓"
      color: Color.accent
      font.pixelSize: 11
    }

    MouseArea {
      anchors.fill: parent
      cursorShape: Qt.PointingHandCursor
      onClicked: box.toggled()
    }
  }

  component ProtocolBadge: Rectangle {
    id: badge
    property string protocol: ""
    implicitWidth: label.implicitWidth + 10
    implicitHeight: label.implicitHeight + 4
    radius: 3
    color: Qt.rgba(0.35, 0.75, 0.45, 0.18)

    Text {
      id: label
      anchors.centerIn: parent
      text: badge.protocol
      color: "#8fd694"
      font.family: root.fontFamily
      font.pixelSize: Style.font.caption - 1
    }
  }

  // ---- io

  FileView {
    id: envFile
    path: Quickshell.env("HOME") + "/.config/omaprow/.env"
    watchChanges: true
    printErrors: false
    onLoaded: {
      root.parseEnv(text())
      envPermProc.command = ["chmod", "600", envFile.path]
      envPermProc.running = true
    }
    onLoadFailed: {
      root.apiKeyLoaded = true
      root.searchError = "~/.config/omaprow/.env not found (see README)"
    }
  }

  // Enforces 0600 on the credential file every time it's (re-)loaded, since
  // it holds the Prowlarr API key and nothing else guarantees its mode.
  Process {
    id: envPermProc
  }

  Process {
    id: xdgOpenProc
  }

  // ---- networking

  Process {
    id: searchProc
    stdinEnabled: true
    onStarted: {
      searchProc.write(root.apiKeyHeaderConfig())
      searchProc.stdinEnabled = false
    }
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.handleSearchResults(text)
    }
    onExited: function(code) {
      if (code !== 0) {
        root.searching = false
        root.searchError = "Search failed (Prowlarr unavailable or timed out)"
      }
    }
  }

  Process {
    id: grabProc
    stdinEnabled: true
    onStarted: {
      grabProc.write(root.apiKeyHeaderConfig())
      grabProc.stdinEnabled = false
    }
    onExited: function(code) { root.handleGrabExit(code) }
  }

  Process {
    id: historyProc
    stdinEnabled: true
    onStarted: {
      historyProc.write(root.apiKeyHeaderConfig())
      historyProc.stdinEnabled = false
    }
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.handleHistory(text)
    }
    onExited: function(code) {
      if (code !== 0) {
        root.historyLoading = false
        root.historyError = "History unavailable"
      }
    }
  }

  // ---- lifecycle

  onOpenedChanged: {
    if (opened) root.viewMode = "search"
  }

  // ---- bar chip

  WidgetButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: root.searchError !== "" ? root.barIcon + " !" : root.barIcon
    fixedWidth: root.bar && root.bar.vertical ? -1 : Style.space(34)
    fixedHeight: root.bar && root.bar.vertical ? Style.space(26) : -1
    tooltipText: root.searchError !== "" ? root.searchError : "OmaProw — search Prowlarr"
    onPressed: function(b) { root.triggerPress(b) }
  }

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  // ---- panel

  KeyboardPanel {
    id: panel
    anchorItem: button
    owner: root
    bar: root.bar
    open: root.opened
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(540))
    contentHeight: panel.fittedContentHeight(contentColumn.implicitHeight, Style.space(680))

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      blocked: searchField.activeFocus || baseUrlField.activeFocus
      onCloseRequested: root.close()
      onTextKey: function(t) {
        if (t === "/") { searchField.forceActiveFocus(); return }
        if (root.viewMode === "search") {
          if (t === "g" || t === "G") { root.grabSelected(); return }
          if (t === "r" || t === "R") { root.performSearch(); return }
          if (t === "v" || t === "V") { root.switchView("history"); return }
        } else if (root.viewMode === "history") {
          if (t === "r" || t === "R") { root.fetchHistory(); return }
          if (t === "v" || t === "V") { root.switchView("search"); return }
        } else if (root.viewMode === "settings") {
          if (t === "v" || t === "V") { root.viewMode = "search"; return }
        }
      }

      ColumnLayout {
        id: contentColumn
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        spacing: Style.space(10)

        RowLayout {
          Layout.fillWidth: true
          spacing: 8

          Text {
            text: root.barIcon + "  " + (root.viewMode === "settings" ? "Settings" : root.viewMode === "history" ? "History" : "OmaProw")
            color: root.fg
            font.family: root.fontFamily
            font.pixelSize: Style.font.title
            font.bold: true
            Layout.fillWidth: true
          }

          Button {
            visible: root.viewMode === "search"
            text: "History"
            foreground: root.fg
            fontFamily: root.fontFamily
            fontSize: Style.font.caption
            horizontalPadding: Style.spacing.controlPaddingX
            verticalPadding: Style.spacing.controlPaddingY
            onClicked: root.switchView("history")
          }

          Button {
            visible: root.viewMode === "search" || root.viewMode === "history"
            text: (root.viewMode === "search" ? root.searching : root.historyLoading) ? "Refreshing…" : "Refresh"
            foreground: root.fg
            fontFamily: root.fontFamily
            fontSize: Style.font.caption
            horizontalPadding: Style.spacing.controlPaddingX
            verticalPadding: Style.spacing.controlPaddingY
            active: root.viewMode === "search" ? root.searching : root.historyLoading
            onClicked: root.viewMode === "search" ? root.performSearch() : root.fetchHistory()
          }

          Button {
            visible: root.viewMode === "search"
            text: "⚙"
            foreground: root.fg
            tooltipText: "Settings"
            fontFamily: root.fontFamily
            fontSize: Style.font.caption
            horizontalPadding: Style.spacing.controlPaddingX
            verticalPadding: Style.spacing.controlPaddingY
            onClicked: root.openSettingsView()
          }

          Button {
            visible: root.viewMode !== "search"
            text: "Back"
            foreground: root.fg
            fontFamily: root.fontFamily
            fontSize: Style.font.caption
            horizontalPadding: Style.spacing.controlPaddingX
            verticalPadding: Style.spacing.controlPaddingY
            onClicked: root.viewMode = "search"
          }
        }

        // ---- settings view

        ColumnLayout {
          visible: root.viewMode === "settings"
          Layout.fillWidth: true
          spacing: Style.space(10)

          Text {
            text: "Prowlarr base URL"
            color: root.dim
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
          }

          TextField {
            id: baseUrlField
            Layout.fillWidth: true
            placeholderText: "http://localhost:9696"
            foreground: root.fg
            text: root.draftBaseUrl
            onTextChanged: root.draftBaseUrl = text
            Keys.onEscapePressed: keyCatcher.forceActiveFocus()
          }

          Text {
            visible: root.settingsStatusText !== ""
            Layout.fillWidth: true
            text: root.settingsStatusText
            color: root.dim
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
            wrapMode: Text.WordWrap
          }

          Button {
            text: "Save"
            foreground: root.fg
            accent: Color.accent
            fontFamily: root.fontFamily
            fontSize: Style.font.caption
            horizontalPadding: Style.spacing.controlPaddingX
            verticalPadding: Style.spacing.controlPaddingY
            onClicked: root.saveSettings()
          }

          Text {
            Layout.fillWidth: true
            text: "The API key stays in ~/.config/omaprow/.env and is not editable here."
            color: root.dim
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
            wrapMode: Text.WordWrap
          }

          Text {
            Layout.fillWidth: true
            text: "Tip: disabling and re-enabling the plugin resets this field. Add URL_BASE=... to ~/.config/omaprow/.env to keep a fallback that survives that."
            color: root.dim
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
            wrapMode: Text.WordWrap
          }
        }

        // ---- search view

        ColumnLayout {
          visible: root.viewMode === "search"
          Layout.fillWidth: true
          spacing: Style.space(10)

          Flow {
            Layout.fillWidth: true
            spacing: 6

            Repeater {
              model: root.categoryOptions
              delegate: Button {
                required property var modelData
                text: modelData.label
                foreground: root.fg
                accent: Color.accent
                fontFamily: root.fontFamily
                fontSize: Style.font.caption
                horizontalPadding: Style.spacing.controlPaddingX
                verticalPadding: Style.spacing.controlPaddingY
                selected: root.categoryId === modelData.id
                onClicked: {
                  root.categoryId = modelData.id
                  root.performSearch()
                }
              }
            }
          }

          RowLayout {
            Layout.fillWidth: true
            spacing: 6

            TextField {
              id: searchField
              Layout.fillWidth: true
              placeholderText: "Search releases…"
              foreground: root.fg
              text: root.searchQuery
              onTextChanged: root.searchQuery = text
              onAccepted: root.performSearch()
              // Escape only drops focus back to the key catcher, matching
              // omatv/omalink — the catcher's own Escape handler (closeRequested)
              // is what actually closes the panel, and it's unreachable while
              // this field is focused (keyCatcher.blocked is true).
              Keys.onEscapePressed: keyCatcher.forceActiveFocus()
            }

            Button {
              text: "Search"
              foreground: root.fg
              accent: Color.accent
              fontFamily: root.fontFamily
              fontSize: Style.font.caption
              horizontalPadding: Style.spacing.controlPaddingX
              verticalPadding: Style.spacing.controlPaddingY
              onClicked: root.performSearch()
            }
          }

          RowLayout {
            Layout.fillWidth: true
            spacing: 6

            Dropdown {
              Layout.fillWidth: true
              label: "Sort by"
              value: root.sortKey
              options: root.sortOptions
              foreground: root.fg
              accent: Color.accent
              fontFamily: root.fontFamily
              onChanged: function(v) { root.setSort(v) }
            }

            Button {
              text: root.sortDir === 1 ? "▲" : "▼"
              foreground: root.fg
              fontFamily: root.fontFamily
              fontSize: Style.font.caption
              horizontalPadding: Style.spacing.controlPaddingX
              verticalPadding: Style.spacing.controlPaddingY
              onClicked: root.sortDir = -root.sortDir
            }
          }

          Text {
            visible: root.searchError !== ""
            Layout.fillWidth: true
            text: root.searchError
            color: Color.urgent
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
            wrapMode: Text.WordWrap
          }

          Text {
            visible: root.searchError === "" && !root.searching && root.sortedResults.length === 0
            Layout.fillWidth: true
            Layout.topMargin: 8
            horizontalAlignment: Text.AlignHCenter
            text: "No results yet — type a query and press Enter"
            color: root.dim
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
          }

          ListView {
            id: resultsList
            visible: root.sortedResults.length > 0
            Layout.fillWidth: true
            Layout.preferredHeight: Style.space(380)
            clip: true
            spacing: Style.space(8)
            model: root.sortedResults
            boundsBehavior: Flickable.StopAtBounds
            ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

            delegate: ColumnLayout {
              id: row
              required property var modelData
              width: resultsList.width
              height: implicitHeight
              spacing: 3

              readonly property bool selectedRow: !!root.selectedGuids[row.modelData.guid]
              readonly property bool busy: root.grabbingGuid === row.modelData.guid
              readonly property string status: root.grabStatus[row.modelData.guid] || ""

              RowLayout {
                Layout.fillWidth: true
                spacing: 6

                SelectBox {
                  checked: row.selectedRow
                  onToggled: root.toggleSelect(row.modelData.guid)
                }

                ProtocolBadge { protocol: row.modelData.protocol || "" }

                Text {
                  Layout.fillWidth: true
                  text: row.modelData.title
                  color: root.fg
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.caption
                  font.bold: true
                  elide: Text.ElideRight

                  MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.openExternalUrl(row.modelData.infoUrl)
                  }
                }
              }

              Text {
                Layout.fillWidth: true
                text: root.formatAge(row.modelData) + " · " + root.formatBytes(row.modelData.size)
                  + " · " + (row.modelData.grabs || 0) + " grabs · " + root.formatPeers(row.modelData) + " peers"
                  + " · " + root.categoryName(row.modelData) + " · " + row.modelData.indexer
                  + (row.modelData.indexerFlags && row.modelData.indexerFlags.length > 0
                     ? " · " + root.flagsText(row.modelData) : "")
                color: root.dim
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
                elide: Text.ElideRight
              }

              RowLayout {
                Layout.fillWidth: true
                spacing: 6

                Button {
                  text: row.busy ? "Grabbing…" : row.status === "ok" ? "Grabbed ✓" : row.status === "error" ? "Failed — retry" : "Grab"
                  foreground: row.status === "error" ? Color.urgent : root.fg
                  accent: Color.accent
                  fontFamily: root.fontFamily
                  fontSize: Style.font.caption
                  horizontalPadding: Style.spacing.controlPaddingX
                  verticalPadding: Style.spacing.controlPaddingY
                  active: row.busy
                  onClicked: { if (!row.busy) root.grabRelease(row.modelData) }
                }

                Item { Layout.fillWidth: true }
              }
            }
          }

          RowLayout {
            visible: root.sortedResults.length > 0
            Layout.fillWidth: true
            Layout.topMargin: 4
            spacing: 8

            Text {
              text: root.sortedResults.length + " release" + (root.sortedResults.length === 1 ? "" : "s") + " found"
                + (root.selectedCount > 0 ? " · " + root.selectedCount + " selected" : "")
              color: root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
              Layout.fillWidth: true
            }

            Button {
              visible: root.selectedCount > 0
              text: "Grab Release(s)"
              foreground: root.fg
              accent: Color.accent
              fontFamily: root.fontFamily
              fontSize: Style.font.caption
              horizontalPadding: Style.spacing.controlPaddingX
              verticalPadding: Style.spacing.controlPaddingY
              onClicked: root.grabSelected()
            }
          }
        }

        // ---- history view

        ColumnLayout {
          visible: root.viewMode === "history"
          Layout.fillWidth: true
          spacing: Style.space(8)

          Text {
            visible: root.historyError !== ""
            Layout.fillWidth: true
            text: root.historyError
            color: Color.urgent
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
            wrapMode: Text.WordWrap
          }

          Text {
            visible: root.historyError === "" && !root.historyLoading && root.historyRecords.length === 0
            Layout.fillWidth: true
            Layout.topMargin: 8
            horizontalAlignment: Text.AlignHCenter
            text: "No history yet"
            color: root.dim
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
          }

          ListView {
            id: historyList
            visible: root.historyRecords.length > 0
            Layout.fillWidth: true
            Layout.preferredHeight: Style.space(460)
            clip: true
            spacing: Style.space(6)
            model: root.historyRecords
            boundsBehavior: Flickable.StopAtBounds
            ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

            delegate: ColumnLayout {
              required property var modelData
              width: historyList.width
              height: implicitHeight
              spacing: 2

              RowLayout {
                Layout.fillWidth: true
                spacing: 6

                Text {
                  text: root.eventLabel(modelData.eventType)
                  color: root.eventColor(modelData.eventType)
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.caption
                  font.bold: true
                }

                Text {
                  Layout.fillWidth: true
                  text: (modelData.data && (modelData.data.query || modelData.data.source)) || ""
                  color: root.dim
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.caption
                  elide: Text.ElideRight
                }

                Text {
                  text: String(modelData.date || "").replace("T", " ").replace("Z", "")
                  color: root.dim
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.caption - 1
                }
              }
            }
          }

          RowLayout {
            visible: root.historyTotal > root.historyPageSize
            Layout.fillWidth: true
            spacing: 8

            Button {
              text: "◂ Prev"
              foreground: root.fg
              fontFamily: root.fontFamily
              fontSize: Style.font.caption
              horizontalPadding: Style.spacing.controlPaddingX
              verticalPadding: Style.spacing.controlPaddingY
              active: root.historyPage <= 1
              onClicked: { if (root.historyPage > 1) root.goHistoryPage(-1) }
            }

            Text {
              Layout.fillWidth: true
              horizontalAlignment: Text.AlignHCenter
              text: "Page " + root.historyPage + " · " + root.historyTotal + " events"
              color: root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
            }

            Button {
              text: "Next ▸"
              foreground: root.fg
              fontFamily: root.fontFamily
              fontSize: Style.font.caption
              horizontalPadding: Style.spacing.controlPaddingX
              verticalPadding: Style.spacing.controlPaddingY
              active: root.historyPage * root.historyPageSize >= root.historyTotal
              onClicked: { if (root.historyPage * root.historyPageSize < root.historyTotal) root.goHistoryPage(1) }
            }
          }
        }

        Text {
          Layout.fillWidth: true
          Layout.topMargin: 4
          text: root.viewMode === "search"
            ? "/ search · g grab selected · v history · r refresh · esc close"
            : root.viewMode === "history"
              ? "v search · r refresh · esc close"
              : "esc close"
          color: root.dim
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
        }
      }
    }
  }
}
