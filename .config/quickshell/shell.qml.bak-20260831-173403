import Quickshell
import Quickshell.Wayland
import Quickshell.Io
import Quickshell.Hyprland
import Quickshell.Services.Notifications
import QtQuick
import QtQuick.Effects

Scope {
    id: shellScope

    Launcher {}

    NotificationServer {
        id: notificationServer
        keepOnReload: true
        bodySupported: true
        bodyMarkupSupported: false
        actionsSupported: true
        imageSupported: true
        onNotification: notification => notification.tracked = true
    }

    Variants {
        model: Quickshell.screens

        PanelWindow {
            id: root
            required property var modelData
            screen: modelData
            WlrLayershell.keyboardFocus: root.wifiPasswordOpen
                ? WlrKeyboardFocus.Exclusive
                : WlrKeyboardFocus.None

            onWifiPasswordOpenChanged: {
                if (root.wifiPasswordOpen) {
                    Qt.callLater(() => wifiPasswordInput.forceActiveFocus());
                }
            }

            // Theme (macOS Classic Dark - Monochrome / Clean Gray)
            property color colBg: "#1E1D1E"
            property color colBorder: "#3A3A3A"
            property color colFg: "#CACCCA"
            property color colMuted: "#9E9E9E"
            property color colActive: "#FFFFFF"
            property color colOccupied: "#8E8E93"
            property color colInactive: "#3A3A3A"
            property color colCard: "#262526"
            property color colCardHover: "#383738"
            property color colAccent: "#007AFF"
            property color colAccentSoft: "#17375F"
            property color colPurple: "#A78BFA"
            property color colGreen: "#52D273"
            property color colDanger: "#FF6B6B"
            property color colBarTrack: "#3A393A"
            property string fontFamily: "JetBrainsMono Nerd Font"
            property int fontSize: 14
            property int panelRadius: 10

            function scriptPath(name) {
                let url = Qt.resolvedUrl(name).toString();
                return url.startsWith("file://") ? decodeURIComponent(url.slice(7)) : url;
            }

            // Time & Date
            property string timeStr: Qt.formatDateTime(new Date(), "HH:mm")
            property string timeFullStr: Qt.formatDateTime(new Date(), "HH:mm:ss")
            property string dateStr: Qt.formatDateTime(new Date(), "dddd, MMMM d")

            Timer {
                interval: 1000
                running: true
                repeat: true
                onTriggered: {
                    let d = new Date();
                    root.timeStr = Qt.formatDateTime(d, "HH:mm");
                    root.timeFullStr = Qt.formatDateTime(d, "HH:mm:ss");
                    root.dateStr = Qt.formatDateTime(d, "dddd, MMMM d");
                }
            }

            // Audio / Volume state
            property bool isMuted: false
            property int volPercent: 50
            property string volIcon: "󰕾"

            function updateVolumeFromStr(data) {
                let str = data.trim();
                if (!str) return;
                let muted = str.includes("[MUTED]");
                root.isMuted = muted;
                let parts = str.split(" ");
                let val = parseFloat(parts[1]) || 0;
                root.volPercent = Math.max(0, Math.min(100, Math.round(val * 100)));
                if (muted || val <= 0.01) {
                    root.volIcon = "󰝟";
                } else if (val < 0.35) {
                    root.volIcon = "󰕿";
                } else if (val < 0.70) {
                    root.volIcon = "󰖀";
                } else {
                    root.volIcon = "󰕾";
                }
            }

            function setVolume(pct) {
                let clamped = Math.max(0, Math.min(100, pct));
                root.volPercent = clamped;
                Quickshell.execDetached(["wpctl", "set-volume", "-l", "1.0", "@DEFAULT_AUDIO_SINK@", (clamped / 100.0).toString()]);
            }

            function toggleMute() {
                Quickshell.execDetached(["wpctl", "set-mute", "@DEFAULT_AUDIO_SINK@", "toggle"]);
                volPollProc.running = true;
            }

            function switchLayout() {
                Quickshell.execDetached(["hyprctl", "switchxkblayout", "all", "next"]);
                kbPollProc.running = true;
            }

            Process {
                id: volPollProc
                command: ["wpctl", "get-volume", "@DEFAULT_AUDIO_SINK@"]
                running: true
                stdout: SplitParser {
                    onRead: data => root.updateVolumeFromStr(data)
                }
            }

            Timer {
                interval: 1200
                running: true
                repeat: true
                onTriggered: volPollProc.running = true
            }

            // Keyboard Layout (US / UA)
            property string kbLayout: "US"

            function updateLayoutFromStr(data) {
                let str = data.toLowerCase();
                if (str.includes("ukr") || str.includes("ua")) {
                    root.kbLayout = "UA";
                } else if (str.includes("eng") || str.includes("us")) {
                    root.kbLayout = "US";
                }
            }

            Process {
                id: kbPollProc
                command: ["sh", "-c", "hyprctl devices -j | grep -B 6 '\"main\": true' | grep '\"active_keymap\"' | head -n 1 || hyprctl devices -j | grep '\"active_keymap\"' | grep -v 'power' | head -n 1"]
                running: true
                stdout: SplitParser {
                    onRead: data => root.updateLayoutFromStr(data)
                }
            }

            Timer {
                interval: 500
                running: true
                repeat: true
                onTriggered: kbPollProc.running = true
            }

            Connections {
                target: Hyprland
                function onRawEvent(event) {
                    if (event.name === "activelayout") {
                        let d = (event.data || "").toLowerCase();
                        if (d.includes("ukr") || d.includes("ua")) {
                            root.kbLayout = "UA";
                        } else if (d.includes("eng") || d.includes("us")) {
                            root.kbLayout = "US";
                        }
                        kbPollProc.running = true;
                    }
                }
            }

            // Network status
            property string netIcon: "󰈀"
            property string netType: "Ethernet"

            // Media and screen recording. Missing optional tools degrade to an
            // explanatory empty state instead of leaving dead controls.
            property string mediaTitle: "Nothing playing"
            property string mediaArtist: "Open a player to see it here"
            property string mediaStatus: "Stopped"
            property string mediaService: ""
            property string preferredMediaService: ""
            property string mediaPlayerName: "Media"
            property string mediaArtUrl: ""
            property var mediaPlayers: []
            property var wifiNetworks: []
            property bool mediaSelectorOpen: false
            property bool wifiSelectorOpen: false
            property bool wifiPasswordOpen: false
            property string pendingWifiSsid: ""
            property bool mediaAvailable: false
            property int mediaMisses: 0
            property bool isRecording: false
            property bool micMuted: false
            property int micPercent: 0
            property int mediaPosition: 0
            property int mediaLength: 0
            property int gpuPercent: 0
            property int batteryPercent: -1
            property bool wifiEnabled: true
            property bool ethernetAvailable: false
            property bool ethernetConnected: false
            property string ethernetDevice: ""
            property bool bluetoothAvailable: false
            property bool bluetoothBlocked: false
            property string recordMode: "screen"
            property bool recordAudio: false
            property int recordSeconds: 0

            function formatMediaTime(seconds) {
                let value = Math.max(0, Math.floor(seconds));
                return Math.floor(value / 60) + ":" + (value % 60).toString().padStart(2, "0");
            }

            function toggleMic() {
                Quickshell.execDetached(["wpctl", "set-mute", "@DEFAULT_AUDIO_SOURCE@", "toggle"]);
                micPollProc.running = true;
            }

            function seekMedia(ratio) {
                if (!root.mediaService || root.mediaLength <= 0) return;
                let target = Math.round(Math.max(0, Math.min(1, ratio)) * root.mediaLength);
                root.mediaPosition = target;
                Quickshell.execDetached([root.scriptPath("media-seek.sh"), root.mediaService, (target * 1000000).toString()]);
                mediaPositionRefresh.restart();
            }

            function toggleWifi() {
                Quickshell.execDetached(["nmcli", "radio", "wifi", root.wifiEnabled ? "off" : "on"]);
                wifiPollProc.running = true;
            }

            function toggleEthernet() {
                if (!root.ethernetDevice) return;
                Quickshell.execDetached(["nmcli", "device", root.ethernetConnected ? "disconnect" : "connect", root.ethernetDevice]);
                netPollProc.running = true;
                ethernetPollDelay.restart();
            }

            function openWifiManager() {
                root.wifiSelectorOpen = false;
                root.mediaSelectorOpen = false;
                root.commandCenterOpen = false;
                Quickshell.execDetached(["nm-connection-editor"]);
            }

            function selectMediaPlayer(service) {
                root.preferredMediaService = service;
                root.mediaSelectorOpen = false;
                mediaPollProc.running = true;
            }

            function connectWifi(ssid, active, security, savedId) {
                if (active) return;
                if (savedId) {
                    Quickshell.execDetached(["nmcli", "connection", "up", "id", savedId]);
                    root.wifiSelectorOpen = false;
                    return;
                }
                if (security && security !== "--") {
                    root.pendingWifiSsid = ssid;
                    root.wifiPasswordOpen = true;
                    wifiPasswordInput.text = "";
                    wifiPasswordInput.forceActiveFocus();
                    return;
                }
                Quickshell.execDetached(["nmcli", "device", "wifi", "connect", ssid]);
                root.wifiSelectorOpen = false;
                wifiListRefresh.restart();
            }

            function submitWifiPassword() {
                if (!root.pendingWifiSsid || !wifiPasswordInput.text) return;
                Quickshell.execDetached(["nmcli", "device", "wifi", "connect", root.pendingWifiSsid, "password", wifiPasswordInput.text]);
                wifiPasswordInput.text = "";
                root.wifiPasswordOpen = false;
                root.wifiSelectorOpen = false;
                wifiListRefresh.restart();
            }

            function cycleMediaPlayer() {
                mediaCycleProc.running = true;
            }

            function toggleBluetooth() {
                if (!root.bluetoothAvailable) return;
                Quickshell.execDetached(["rfkill", root.bluetoothBlocked ? "unblock" : "block", "bluetooth"]);
                bluetoothPollProc.running = true;
            }

            function openBtop() {
                root.commandCenterOpen = false;
                Quickshell.execDetached(["kitty", "--class", "btop", "-e", "btop"]);
            }

            function mediaAction(action) {
                let method = action === "play-pause" ? "PlayPause" : (action === "previous" ? "Previous" : "Next");
                if (root.mediaService) {
                    Quickshell.execDetached(["busctl", "--user", "call", root.mediaService, "/org/mpris/MediaPlayer2", "org.mpris.MediaPlayer2.Player", method]);
                } else {
                    Quickshell.execDetached(["notify-send", "Command Centre", "No MPRIS media player found"]);
                }
                mediaPollProc.running = true;
            }

            function toggleRecording() {
                if (root.isRecording) {
                    Quickshell.execDetached(["sh", "-c", "pkill -INT -x wf-recorder"]);
                } else {
                    Quickshell.execDetached([
                        root.scriptPath("screen-record.sh"),
                        root.recordMode,
                        root.recordAudio ? "yes" : "no"
                    ]);
                    root.recordSeconds = 0;
                }
                recordRefreshTimer.restart();
            }

            Process {
                id: mediaPollProc
                command: [root.scriptPath("media-status.sh"), root.preferredMediaService]
                running: true
                stdout: SplitParser {
                    onRead: data => {
                        let p = data.trim().split("\x1f");
                        let service = p[3] || "";
                        let title = p[1] || "";
                        let artist = p[2] || "";
                        let hasRealMetadata = title !== ""
                            && title !== "Unknown title"
                            && title !== "Nothing playing";

                        // Some players (notably Spotify clients) briefly drop
                        // their MPRIS name while transitioning to Paused. Do not
                        // erase the current card because of one empty poll: the
                        // last known metadata remains useful and the service may
                        // return on the next tick.
                        if (service !== "" && hasRealMetadata) {
                            root.mediaMisses = 0;
                            root.mediaStatus = p[0] || "Paused";
                            root.mediaTitle = title;
                            if (artist !== "" && artist !== "Unknown artist") {
                                root.mediaArtist = artist;
                            }
                            root.mediaService = service;
                            root.mediaArtUrl = p[4] || "";
                            root.mediaLength = Math.floor((parseInt(p[5]) || 0) / 1000000);
                            root.mediaPlayerName = p[6] || "Media";
                            root.mediaAvailable = true;
                        } else if (service !== "" && root.mediaAvailable) {
                            // A paused player may briefly expose an empty
                            // Metadata dictionary. Keep the last valid track
                            // and, critically, do not switch to that endpoint.
                            root.mediaStatus = p[0] || "Paused";
                        } else if (root.mediaAvailable) {
                            root.mediaMisses++;
                            if (root.mediaMisses < 3) {
                                root.mediaStatus = "Paused";
                            } else {
                                root.mediaAvailable = false;
                                root.mediaService = "";
                                root.mediaArtUrl = "";
                                root.mediaPosition = 0;
                                root.mediaLength = 0;
                                root.mediaStatus = "Stopped";
                                root.mediaTitle = "Nothing playing";
                                root.mediaArtist = "Open a player to see it here";
                            }
                        } else {
                            root.mediaMisses = 0;
                            root.mediaStatus = "Stopped";
                            root.mediaTitle = "Nothing playing";
                            root.mediaArtist = "Open a player to see it here";
                        }
                    }
                }
            }

                    Rectangle {
                        id: selectorOverlay
                        z: 20
                        width: 390
                        height: root.wifiPasswordOpen ? 180 : (root.mediaSelectorOpen
                            ? 53 + Math.max(1, Math.min(6, root.mediaPlayers.length)) * 60
                            : 53 + (root.ethernetAvailable ? 54 : 0)
                                + Math.max(48, Math.min(6, root.wifiNetworks.length) * 54) + 50)
                        anchors.horizontalCenter: parent.horizontalCenter
                        y: commandCenterCard.y + 10
                        radius: 9
                        color: "#FC1E1D1E"
                        border.width: 1
                        border.color: "#45FFFFFF"
                        visible: root.commandCenterOpen
                            && (root.mediaSelectorOpen || root.wifiSelectorOpen)

                        Text {
                            anchors.left: parent.left; anchors.leftMargin: 14
                            anchors.top: parent.top; anchors.topMargin: 13
                            text: root.wifiPasswordOpen ? "CONNECT TO WI-FI" : (root.mediaSelectorOpen ? "MEDIA PLAYERS" : "WI-FI NETWORKS")
                            color: root.colActive
                            font { family: root.fontFamily; pixelSize: 10; bold: true; letterSpacing: 1.2 }
                        }
                        Rectangle {
                            id: selectorCloseButton
                            z: 100
                            anchors.right: parent.right; anchors.rightMargin: 14
                            anchors.top: parent.top; anchors.topMargin: 8
                            width: 28; height: 28; radius: 8
                            color: selectorCloseMouse.containsMouse ? "#28FFFFFF" : "transparent"
                            Text { anchors.centerIn: parent; text: "󰅖"; color: selectorCloseMouse.containsMouse ? root.colActive : root.colMuted; font { family: root.fontFamily; pixelSize: 13 } }
                            MouseArea { id: selectorCloseMouse; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onPressed: mouse => { mouse.accepted = true; root.mediaSelectorOpen = false; root.wifiSelectorOpen = false; root.wifiPasswordOpen = false; } }
                        }

                        Column {
                            anchors.left: parent.left; anchors.right: parent.right
                            anchors.top: parent.top; anchors.topMargin: 43
                            anchors.margins: 10; spacing: 6
                            visible: root.mediaSelectorOpen

                            Repeater {
                                model: root.mediaPlayers
                                Rectangle {
                                    required property var modelData
                                    width: parent.width; height: 54; radius: 9
                                    color: modelData.service === root.mediaService ? "#30FFFFFF" : (playerChoiceMouse.containsMouse ? "#24FFFFFF" : "#10FFFFFF")
                                    border.width: 1; border.color: modelData.service === root.mediaService ? "#55FFFFFF" : "#18FFFFFF"
                                    Text { anchors.left: parent.left; anchors.leftMargin: 12; anchors.verticalCenter: parent.verticalCenter; text: modelData.status === "Playing" ? "󰐊" : "󰏤"; color: modelData.status === "Playing" ? root.colActive : root.colMuted; font { family: root.fontFamily; pixelSize: 15 } }
                                    Column { anchors.left: parent.left; anchors.leftMargin: 42; anchors.verticalCenter: parent.verticalCenter; spacing: 2; Text { text: modelData.name; color: root.colFg; font { family: root.fontFamily; pixelSize: 10; bold: true } } Text { text: modelData.status; color: root.colMuted; font { family: root.fontFamily; pixelSize: 8 } } }
                                    Text { anchors.right: parent.right; anchors.rightMargin: 12; anchors.verticalCenter: parent.verticalCenter; text: modelData.service === root.mediaService ? "󰄬" : "󰅂"; color: root.colMuted; font { family: root.fontFamily; pixelSize: 12 } }
                                    MouseArea { id: playerChoiceMouse; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: root.selectMediaPlayer(modelData.service) }
                                }
                            }
                        }

                        Column {
                            anchors.left: parent.left; anchors.right: parent.right
                            anchors.top: parent.top; anchors.topMargin: 43
                            anchors.margins: 10; spacing: 6
                            visible: root.wifiSelectorOpen && !root.wifiPasswordOpen

                            Rectangle {
                                width: parent.width; height: 48; radius: 9
                                visible: root.ethernetAvailable
                                color: root.ethernetConnected ? "#28FFFFFF" : "#10FFFFFF"; border.width: 1; border.color: root.ethernetConnected ? "#45FFFFFF" : "#18FFFFFF"
                                Text { anchors.left: parent.left; anchors.leftMargin: 12; anchors.verticalCenter: parent.verticalCenter; text: "󰈀"; color: root.ethernetConnected ? root.colActive : root.colMuted; font { family: root.fontFamily; pixelSize: 15 } }
                                Column { anchors.left: parent.left; anchors.leftMargin: 42; anchors.verticalCenter: parent.verticalCenter; spacing: 2; Text { text: "Ethernet"; color: root.colFg; font { family: root.fontFamily; pixelSize: 10; bold: true } } Text { text: root.ethernetConnected ? "Connected · click to disconnect" : "Disconnected · click to reconnect"; color: root.colMuted; font { family: root.fontFamily; pixelSize: 8 } } }
                                Text { anchors.right: parent.right; anchors.rightMargin: 12; anchors.verticalCenter: parent.verticalCenter; text: root.ethernetConnected ? "󰄬" : "󰅂"; color: root.ethernetConnected ? root.colActive : root.colMuted; font { family: root.fontFamily; pixelSize: 12 } }
                                MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: root.toggleEthernet() }
                            }

                            Flickable {
                                width: parent.width
                                height: Math.max(48, Math.min(6, root.wifiNetworks.length) * 54)
                                contentWidth: width
                                contentHeight: wifiNetworkColumn.implicitHeight
                                clip: true
                                boundsBehavior: Flickable.StopAtBounds
                                flickableDirection: Flickable.VerticalFlick

                                Column {
                                    id: wifiNetworkColumn
                                    width: parent.width
                                    spacing: 6

                                    Text {
                                        width: parent.width; height: 48
                                        visible: root.wifiNetworks.length === 0
                                        verticalAlignment: Text.AlignVCenter
                                        horizontalAlignment: Text.AlignHCenter
                                        text: root.wifiEnabled ? "No Wi-Fi networks found" : "Wi-Fi is disabled"
                                        color: root.colMuted
                                        font { family: root.fontFamily; pixelSize: 9 }
                                    }

                                    Repeater {
                                        model: root.wifiNetworks
                                        Rectangle {
                                            required property var modelData
                                            width: wifiNetworkColumn.width; height: 48; radius: 9
                                            color: modelData.active ? "#30FFFFFF" : (wifiChoiceMouse.containsMouse ? "#24FFFFFF" : "#10FFFFFF")
                                            border.width: 1; border.color: modelData.active ? "#55FFFFFF" : "#18FFFFFF"
                                            Text { anchors.left: parent.left; anchors.leftMargin: 12; anchors.verticalCenter: parent.verticalCenter; text: modelData.signal > 70 ? "󰤨" : (modelData.signal > 35 ? "󰤥" : "󰤟"); color: modelData.active ? root.colActive : root.colMuted; font { family: root.fontFamily; pixelSize: 15 } }
                                            Text { anchors.left: parent.left; anchors.leftMargin: 42; anchors.right: wifiSignal.left; anchors.rightMargin: 8; anchors.verticalCenter: parent.verticalCenter; text: modelData.ssid; elide: Text.ElideRight; color: root.colFg; font { family: root.fontFamily; pixelSize: 10; bold: true } }
                                            Text { id: wifiSignal; anchors.right: parent.right; anchors.rightMargin: 12; anchors.verticalCenter: parent.verticalCenter; text: (modelData.security && modelData.security !== "--" ? "󰌾  " : "") + modelData.signal + "%"; color: root.colMuted; font { family: root.fontFamily; pixelSize: 8; bold: true } }
                                            MouseArea { id: wifiChoiceMouse; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: root.connectWifi(modelData.ssid, modelData.active, modelData.security, modelData.savedId) }
                                        }
                                    }
                                }

                                Rectangle {
                                    anchors.right: parent.right
                                    width: 3
                                    height: parent.height * Math.min(1, parent.height / Math.max(1, parent.contentHeight))
                                    y: parent.contentY * parent.height / Math.max(1, parent.contentHeight)
                                    radius: 2
                                    color: "#55FFFFFF"
                                    visible: parent.contentHeight > parent.height
                                }
                            }

                            Rectangle {
                                width: parent.width; height: 38; radius: 9
                                color: wifiSettingsMouse.containsMouse ? "#24FFFFFF" : "#10FFFFFF"; border.width: 1; border.color: "#18FFFFFF"
                                Text { anchors.centerIn: parent; text: "󰒓  Advanced network settings"; color: root.colMuted; font { family: root.fontFamily; pixelSize: 9; bold: true } }
                                MouseArea { id: wifiSettingsMouse; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: root.openWifiManager() }
                            }
                        }

                        Column {
                            anchors.left: parent.left; anchors.right: parent.right
                            anchors.top: parent.top; anchors.topMargin: 48
                            anchors.leftMargin: 14; anchors.rightMargin: 14
                            spacing: 9
                            visible: root.wifiPasswordOpen

                            Text {
                                width: parent.width
                                text: "Password for " + root.pendingWifiSsid
                                elide: Text.ElideRight
                                color: root.colFg
                                font { family: root.fontFamily; pixelSize: 10; bold: true }
                            }
                            Rectangle {
                                width: parent.width; height: 38; radius: 9
                                color: "#18FFFFFF"; border.width: 1
                                border.color: wifiPasswordInput.activeFocus ? "#66FFFFFF" : "#25FFFFFF"
                                TextInput {
                                    id: wifiPasswordInput
                                    anchors.fill: parent; anchors.leftMargin: 11; anchors.rightMargin: 11
                                    verticalAlignment: TextInput.AlignVCenter
                                    echoMode: TextInput.Password
                                    passwordCharacter: "•"
                                    color: root.colActive
                                    selectionColor: "#55FFFFFF"
                                    font { family: root.fontFamily; pixelSize: 10 }
                                    Keys.onReturnPressed: root.submitWifiPassword()
                                    Keys.onEnterPressed: root.submitWifiPassword()
                                }
                                Text {
                                    anchors.left: parent.left; anchors.leftMargin: 11; anchors.verticalCenter: parent.verticalCenter
                                    visible: wifiPasswordInput.text === "" && !wifiPasswordInput.activeFocus
                                    text: "Enter network password"
                                    color: root.colMuted
                                    font { family: root.fontFamily; pixelSize: 9 }
                                }
                                MouseArea { anchors.fill: parent; z: -1; onClicked: wifiPasswordInput.forceActiveFocus() }
                            }
                            Rectangle {
                                width: parent.width; height: 36; radius: 9
                                color: wifiConnectMouse.containsMouse ? "#35FFFFFF" : "#24FFFFFF"
                                border.width: 1; border.color: "#45FFFFFF"
                                Text { anchors.centerIn: parent; text: "Connect"; color: root.colActive; font { family: root.fontFamily; pixelSize: 9; bold: true } }
                                MouseArea { id: wifiConnectMouse; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: root.submitWifiPassword() }
                            }
                        }
                    }

            Process {
                id: recordingPollProc
                command: ["sh", "-c", "pgrep -x wf-recorder >/dev/null && echo yes || echo no"]
                running: true
                stdout: SplitParser { onRead: data => root.isRecording = data.trim() === "yes" }
            }

            Process {
                id: micPollProc
                command: ["wpctl", "get-volume", "@DEFAULT_AUDIO_SOURCE@"]
                running: true
                stdout: SplitParser {
                    onRead: data => {
                        root.micMuted = data.includes("[MUTED]");
                        let match = data.match(/Volume:\s+([0-9.]+)/);
                        root.micPercent = match ? Math.round(parseFloat(match[1]) * 100) : 0;
                    }
                }
            }

            Process {
                id: mediaPositionProc
                command: ["sh", "-c", "[ -n \"$1\" ] && busctl --user get-property \"$1\" /org/mpris/MediaPlayer2 org.mpris.MediaPlayer2.Player Position 2>/dev/null | awk '{print int($2/1000000)}' || echo 0", "sh", root.mediaService]
                running: root.mediaService !== ""
                stdout: SplitParser { onRead: data => root.mediaPosition = parseInt(data.trim()) || 0 }
            }

            Process {
                id: mediaLengthProc
                command: ["sh", "-c", "[ -n \"$1\" ] && busctl --user get-property \"$1\" /org/mpris/MediaPlayer2 org.mpris.MediaPlayer2.Player Metadata 2>/dev/null | sed -nE 's/.*\"mpris:length\" [a-z] ([0-9]+).*/\\1/p' | awk '{print int($1/1000000)}' || echo 0", "sh", root.mediaService]
                running: root.mediaService !== ""
                stdout: SplitParser { onRead: data => root.mediaLength = parseInt(data.trim()) || 0 }
            }

            Process {
                id: mediaCycleProc
                command: ["sh", "-c", "current=\"$1\"; first=''; next=''; seen=0; for name in $(busctl --user --no-pager --no-legend list 2>/dev/null | awk '/org.mpris.MediaPlayer2/ {print $1}'); do [ -z \"$first\" ] && first=\"$name\"; if [ $seen -eq 1 ]; then next=\"$name\"; break; fi; [ \"$name\" = \"$current\" ] && seen=1; done; [ -z \"$next\" ] && next=\"$first\"; printf '%s\\n' \"$next\"", "sh", root.mediaService]
                stdout: SplitParser {
                    onRead: data => {
                        let service = data.trim();
                        if (service) {
                            root.mediaService = service;
                            mediaPollProc.running = true;
                            mediaPositionProc.running = true;
                            mediaLengthProc.running = true;
                        }
                    }
                }
            }

            Process {
                id: mediaListProc
                command: [root.scriptPath("media-list.sh")]
                stdout: SplitParser {
                    onRead: data => {
                        let rows = data.trim() ? data.trim().split("\x1e") : [];
                        root.mediaPlayers = rows.map(row => {
                            let values = row.split("\x1f");
                            return { service: values[0] || "", name: values[1] || "Media", status: values[2] || "Stopped" };
                        });
                    }
                }
            }

            Process {
                id: wifiListProc
                command: [root.scriptPath("wifi-list.sh")]
                stdout: SplitParser {
                    onRead: data => {
                        let rows = data.trim() ? data.trim().split("\x1e") : [];
                        root.wifiNetworks = rows.map(row => {
                            let values = row.split("\x1f");
                            return { ssid: values[0] || "Unknown", signal: parseInt(values[1]) || 0, security: values[2] || "Open", active: values[3] === "yes", savedId: values[4] || "" };
                        });
                    }
                }
            }

            Process {
                id: gpuPollProc
                command: ["sh", "-c", "nvidia-smi --query-gpu=utilization.gpu --format=csv,noheader,nounits 2>/dev/null | head -1 || echo 0"]
                running: true
                stdout: SplitParser { onRead: data => root.gpuPercent = parseInt(data.trim()) || 0 }
            }

            Process {
                id: batteryPollProc
                command: ["sh", "-c", "for f in /sys/class/power_supply/BAT*/capacity; do [ -r \"$f\" ] && cat \"$f\" && exit; done; echo -1"]
                running: true
                stdout: SplitParser { onRead: data => root.batteryPercent = parseInt(data.trim()) }
            }

            Process {
                id: wifiPollProc
                command: ["sh", "-c", "nmcli radio wifi 2>/dev/null || echo disabled"]
                running: true
                stdout: SplitParser { onRead: data => root.wifiEnabled = data.trim() === "enabled" }
            }

            Process {
                id: bluetoothPollProc
                command: ["sh", "-c", "if rfkill list bluetooth >/dev/null 2>&1; then rfkill list bluetooth | awk '/Soft blocked:/ {print \"yes|||\" $3; exit}'; else echo 'no|||yes'; fi"]
                running: true
                stdout: SplitParser {
                    onRead: data => {
                        let values = data.trim().split("|||");
                        root.bluetoothAvailable = values[0] === "yes";
                        root.bluetoothBlocked = values[1] === "yes";
                    }
                }
            }

            Timer { interval: 1500; running: true; repeat: true; onTriggered: { mediaPollProc.running = true; mediaPositionProc.running = root.mediaService !== ""; mediaLengthProc.running = root.mediaService !== ""; recordingPollProc.running = true; micPollProc.running = true; } }
            Timer { interval: 5000; running: true; repeat: true; onTriggered: { gpuPollProc.running = true; batteryPollProc.running = true; wifiPollProc.running = true; wifiListProc.running = true; mediaListProc.running = true; bluetoothPollProc.running = true; } }
            Timer { interval: 1000; running: root.isRecording; repeat: true; onTriggered: root.recordSeconds++ }
            Timer { id: wifiListRefresh; interval: 1200; repeat: false; onTriggered: wifiListProc.running = true }
            Timer { id: ethernetPollDelay; interval: 900; repeat: false; onTriggered: netPollProc.running = true }
            Timer { id: recordRefreshTimer; interval: 500; repeat: false; onTriggered: recordingPollProc.running = true }
            Timer { id: mediaPositionRefresh; interval: 500; repeat: false; onTriggered: mediaPositionProc.running = true }

            Process {
                id: netPollProc
                command: ["sh", "-c", "devices=$(nmcli -t -f DEVICE,TYPE,STATE device 2>/dev/null); eth=$(printf '%s\\n' \"$devices\" | awk -F: '$2 == \"ethernet\" {available=1; if (iface == \"\") iface=$1; if ($3 == \"connected\") connected=1} END {printf \"%s|||%s|||%s\", available ? \"yes\" : \"no\", connected ? \"yes\" : \"no\", iface}'); if printf '%s' \"$eth\" | grep -q '^yes|||yes|||'; then printf '󰈀 Ethernet|||%s\\n' \"$eth\"; elif printf '%s\\n' \"$devices\" | awk -F: '$2 == \"wifi\" && $3 == \"connected\" {found=1} END {exit !found}'; then printf '󰤨 WiFi|||%s\\n' \"$eth\"; else printf '󰤭 Disconnected|||%s\\n' \"$eth\"; fi"]
                running: true
                stdout: SplitParser {
                    onRead: data => {
                        let s = data.trim();
                        if (s) {
                            let sections = s.split("|||");
                            let status = (sections[0] || "󰤭 Disconnected").split(" ");
                            root.netIcon = status[0];
                            root.netType = status[1] || "Disconnected";
                            root.ethernetAvailable = sections[1] === "yes";
                            root.ethernetConnected = sections[2] === "yes";
                            root.ethernetDevice = sections[3] || "";
                        }
                    }
                }
            }

            Timer {
                interval: 3000
                running: true
                repeat: true
                onTriggered: netPollProc.running = true
            }

            // System Metrics (CPU, RAM, Temp, Uptime)
            property int cpuPercent: 0
            property int ramPercent: 0
            property int cpuTemp: 40
            property string uptimeStr: "0:00"

            Process {
                id: sysMetricsProc
                command: ["bash", "-c", "cpu=$(awk '{u=$2+$4; t=$2+$4+$5; if (NR==1){u1=u; t1=t;} else {print int((u-u1)/(t-t1)*100)}}' <(grep 'cpu ' /proc/stat) <(sleep 0.08 && grep 'cpu ' /proc/stat) 2>/dev/null || echo '5'); ram=$(free -m | awk '/Mem:/ {printf \"%d\", ($3/$2)*100}'); temp=$(cat /sys/class/thermal/thermal_zone*/temp 2>/dev/null | head -n 1 | awk '{printf \"%d\", $1/1000}' || echo '40'); uptime_val=$(uptime | sed -E 's/.*up +([^,]+), .*/\\1/'); echo \"$cpu;$ram;$temp;$uptime_val\""]
                running: true
                stdout: SplitParser {
                    onRead: data => {
                        let parts = data.trim().split(";");
                        if (parts.length >= 4) {
                            root.cpuPercent = Math.max(0, Math.min(100, parseInt(parts[0]) || 0));
                            root.ramPercent = Math.max(0, Math.min(100, parseInt(parts[1]) || 0));
                            root.cpuTemp = Math.max(0, Math.min(120, parseInt(parts[2]) || 40));
                            root.uptimeStr = parts[3].trim();
                        }
                    }
                }
            }

            Timer {
                interval: 2500
                running: true
                repeat: true
                onTriggered: sysMetricsProc.running = true
            }

            // Anchors & Surface Setup
            anchors.top: true
            anchors.left: true
            anchors.right: true
            // Keep the layer surface geometry stable. Resizing it on open makes
            // Hyprland animate the entire Quickshell layer; only the input mask
            // should become fullscreen while a popup is visible.
            implicitHeight: root.screen.height
            exclusiveZone: 34
            color: "transparent"

            margins {
                top: 10
                left: 10
                right: 10
            }

            property bool commandCenterOpen: false
            property bool powerOpen: false

            // Input Mask
            mask: Region {
                Region { item: (root.commandCenterOpen || root.powerOpen) ? dismissOverlay : null }
                Region { item: wsIsland }
                Region { item: timeIsland }
                Region { item: sysIsland }
                Region { item: root.commandCenterOpen ? commandCenterCard : null }
                Region { item: root.powerOpen ? controlCenterCard : null }
            }

            // Dismiss overlay
            MouseArea {
                id: dismissOverlay
                anchors.fill: parent
                enabled: root.commandCenterOpen || root.powerOpen
                z: 0
                onClicked: {
                    root.commandCenterOpen = false;
                    root.powerOpen = false;
                    root.mediaSelectorOpen = false;
                    root.wifiSelectorOpen = false;
                    root.wifiPasswordOpen = false;
                }
            }

            Item {
                anchors.fill: parent

                // 1. Лівий острівець: Workspaces (Pills & Dots)
                Rectangle {
                    id: wsIsland
                    z: 10
                    anchors.left: parent.left
                    anchors.top: parent.top
                    height: 34
                    width: wsRow.width + 24
                    color: root.colBg
                    radius: root.panelRadius
                    border.width: 1
                    border.color: root.colBorder

                    Row {
                        id: wsRow
                        anchors.centerIn: parent
                        spacing: 6

                        Repeater {
                            model: 9
                            Item {
                                id: wsItem
                                width: pill.width
                                height: 20

                                property var ws: Hyprland.workspaces.values.find(w => w.id === index + 1)
                                property bool isActive: Hyprland.focusedWorkspace?.id === (index + 1)
                                property bool isOccupied: !!ws
                                property bool isHovered: mouseArea.containsMouse

                                Rectangle {
                                    id: pill
                                    anchors.verticalCenter: parent.verticalCenter
                                    height: 8
                                    radius: height / 2
                                    width: wsItem.isActive ? 28 : (wsItem.isOccupied ? 12 : 8)

                                    color: wsItem.isActive
                                        ? root.colActive
                                        : (wsItem.isHovered
                                            ? "#FFFFFF"
                                            : (wsItem.isOccupied ? root.colOccupied : root.colInactive))

                                    Behavior on width {
                                        NumberAnimation {
                                            duration: 250
                                            easing.type: Easing.OutCubic
                                        }
                                    }

                                    Behavior on color {
                                        ColorAnimation {
                                            duration: 200
                                            easing.type: Easing.OutCubic
                                        }
                                    }
                                }

                                MouseArea {
                                    id: mouseArea
                                    anchors.fill: parent
                                    anchors.leftMargin: -3
                                    anchors.rightMargin: -3
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: Hyprland.dispatch("hl.dsp.focus({ workspace = " + (index + 1) + " })")
                                }
                            }
                        }
                    }
                }

                // 2. Центральний острівець: Час (Клік відкриває Командний Центр)
                Rectangle {
                    id: timeIsland
                    z: 10
                    anchors.horizontalCenter: parent.horizontalCenter
                    anchors.top: parent.top
                    height: 34
                    width: timeRow.width + 24
                    color: root.colBg
                    radius: root.panelRadius
                    border.width: 1
                    border.color: (timeMouse.containsMouse || root.commandCenterOpen) ? "#555555" : root.colBorder

                    Behavior on border.color {
                        ColorAnimation { duration: 150 }
                    }

                    Row {
                        id: timeRow
                        anchors.centerIn: parent
                        spacing: 6

                        Text {
                            id: timeText
                            text: root.timeStr
                            color: (timeMouse.containsMouse || root.commandCenterOpen) ? "#FFFFFF" : root.colFg
                            font { family: root.fontFamily; pixelSize: root.fontSize; bold: true }
                            anchors.verticalCenter: parent.verticalCenter

                            Behavior on color {
                                ColorAnimation { duration: 150 }
                            }
                        }

                        Text {
                            text: "󰅀"
                            color: root.commandCenterOpen ? "#FFFFFF" : root.colMuted
                            font { family: root.fontFamily; pixelSize: 10 }
                            anchors.verticalCenter: parent.verticalCenter
                            rotation: root.commandCenterOpen ? 180 : 0

                            Behavior on rotation {
                                NumberAnimation { duration: 320; easing.type: Easing.OutBack; easing.overshoot: 2.0 }
                            }
                            Behavior on color {
                                ColorAnimation { duration: 150 }
                            }
                        }
                    }

                    MouseArea {
                        id: timeMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            root.commandCenterOpen = !root.commandCenterOpen;
                            if (!root.commandCenterOpen) {
                                root.mediaSelectorOpen = false;
                                root.wifiSelectorOpen = false;
                                root.wifiPasswordOpen = false;
                            }
                            root.powerOpen = false;
                        }
                    }
                }

                // 3. Правий острівець: Звук, Мова, Мережа, Живлення
                Rectangle {
                    id: sysIsland
                    z: 10
                    anchors.right: parent.right
                    anchors.top: parent.top
                    height: 34
                    width: sysRow.width + 28
                    color: root.colBg
                    radius: root.panelRadius
                    border.width: 1
                    border.color: root.colBorder

                    Row {
                        id: sysRow
                        anchors.centerIn: parent
                        spacing: 12

                        // Гучність (тільки іконка: клік — mute, скрол — зміна гучності)
                        Text {
                            id: volIconText
                            text: root.volIcon
                            color: volMouse.containsMouse ? "#FFFFFF" : (root.isMuted ? root.colMuted : root.colFg)
                            font { family: root.fontFamily; pixelSize: root.fontSize + 2 }
                            anchors.verticalCenter: parent.verticalCenter

                            MouseArea {
                                id: volMouse
                                anchors.fill: parent
                                anchors.margins: -6
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: root.toggleMute()
                                onWheel: wheel => {
                                    if (wheel.angleDelta.y > 0) {
                                        root.setVolume(root.volPercent + 5);
                                    } else {
                                        root.setVolume(root.volPercent - 5);
                                    }
                                }
                            }
                        }

                        Rectangle {
                            width: 1
                            height: 14
                            color: root.colBorder
                            anchors.verticalCenter: parent.verticalCenter
                        }

                        // Мова розкладки (клік — перемикання)
                        Text {
                            id: kbText
                            text: root.kbLayout
                            color: kbMouse.containsMouse ? "#FFFFFF" : root.colFg
                            font { family: root.fontFamily; pixelSize: root.fontSize; bold: true }
                            anchors.verticalCenter: parent.verticalCenter

                            MouseArea {
                                id: kbMouse
                                anchors.fill: parent
                                anchors.margins: -6
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: root.switchLayout()
                            }
                        }

                        Rectangle {
                            width: 1
                            height: 14
                            color: root.colBorder
                            anchors.verticalCenter: parent.verticalCenter
                        }

                        // Мережа
                        Text {
                            id: netText
                            text: root.netIcon
                            color: netMouse.containsMouse ? "#FFFFFF" : root.colFg
                            font { family: root.fontFamily; pixelSize: root.fontSize + 2 }
                            anchors.verticalCenter: parent.verticalCenter

                            MouseArea {
                                id: netMouse
                                anchors.fill: parent
                                anchors.margins: -6
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: {
                                    root.commandCenterOpen = true;
                                    root.powerOpen = false;
                                }
                            }
                        }

                        Rectangle {
                            width: 1
                            height: 14
                            color: root.colBorder
                            anchors.verticalCenter: parent.verticalCenter
                        }

                        // Кнопка живлення
                        Text {
                            id: powerText
                            text: "󰐥"
                            color: (powerMouse.containsMouse || root.powerOpen) ? "#c74028" : root.colFg
                            font { family: root.fontFamily; pixelSize: root.fontSize + 2 }
                            anchors.verticalCenter: parent.verticalCenter

                            Behavior on color {
                                ColorAnimation { duration: 150 }
                            }

                            MouseArea {
                                id: powerMouse
                                anchors.fill: parent
                                anchors.margins: -6
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: {
                                    root.powerOpen = !root.powerOpen;
                                    root.commandCenterOpen = false;
                                }
                            }
                        }
                    }
                }

                // Command Centre — monochrome glass, matching Hyprland itself.
                Rectangle {
                    id: commandCenterCard
                    z: 6
                    anchors.horizontalCenter: parent.horizontalCenter
                    y: root.commandCenterOpen ? 46 : 28
                    width: 410
                    height: (root.mediaSelectorOpen || root.wifiSelectorOpen)
                        ? selectorOverlay.height + 20
                        : 524
                    color: "#E61E1D1E"
                    radius: 10
                    border.width: 1
                    border.color: "#55FFFFFF"
                    opacity: root.commandCenterOpen ? 1 : 0
                    scale: root.commandCenterOpen ? 1 : 0.87
                    visible: opacity > 0.01
                    transformOrigin: Item.Top

                    Behavior on y { NumberAnimation { duration: 220; easing.type: Easing.OutQuint } }
                    Behavior on opacity { NumberAnimation { duration: 140; easing.type: Easing.OutQuad } }
                    Behavior on scale { NumberAnimation { duration: 240; easing.type: Easing.OutBack; easing.overshoot: 1.08 } }

                    Rectangle {
                        anchors.fill: parent
                        anchors.margins: 1
                        radius: 9
                        color: "transparent"
                        border.width: 1
                        border.color: "#12FFFFFF"
                    }

                    Column {
                        anchors.fill: parent
                        anchors.margins: 12
                        spacing: 8
                        visible: !root.mediaSelectorOpen && !root.wifiSelectorOpen

                        Item {
                            width: parent.width
                            height: 42

                            Column {
                                anchors.left: parent.left
                                anchors.verticalCenter: parent.verticalCenter
                                spacing: 2
                                Text {
                                    text: root.timeStr
                                    color: root.colActive
                                    font { family: root.fontFamily; pixelSize: 20; bold: true }
                                }
                                Text {
                                    text: root.dateStr
                                    color: root.colMuted
                                    font { family: root.fontFamily; pixelSize: 9 }
                                }
                            }
                            Rectangle {
                                anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter
                                width: uptimeRow.width + 14; height: 24; radius: 8
                                color: "#22FFFFFF"; border.width: 1; border.color: "#18FFFFFF"
                                Row { id: uptimeRow; anchors.centerIn: parent; spacing: 5; Text { text: "󰔛"; color: root.colMuted; font { family: root.fontFamily; pixelSize: 10 } } Text { text: root.uptimeStr; color: root.colFg; font { family: root.fontFamily; pixelSize: 9; bold: true } } }
                            }
                        }

                        Rectangle {
                            width: parent.width
                            height: 118; radius: 10; color: "#B3262526"; border.width: 1; border.color: "#18FFFFFF"
                            clip: true

                            Item {
                                z: 0
                                anchors.fill: parent
                                layer.enabled: true
                                layer.effect: MultiEffect {
                                    maskEnabled: true
                                    maskSource: ShaderEffectSource {
                                        sourceItem: Rectangle {
                                            width: mediaArtwork.width
                                            height: mediaArtwork.height
                                            radius: 10
                                            color: "white"
                                        }
                                    }
                                }

                                Image {
                                    id: mediaArtwork
                                    anchors.fill: parent
                                    source: root.mediaArtUrl
                                    visible: status === Image.Ready
                                    asynchronous: true
                                    cache: true
                                    fillMode: Image.PreserveAspectCrop
                                    opacity: 0.5
                                    Behavior on opacity { NumberAnimation { duration: 260; easing.type: Easing.OutCubic } }
                                }
                            }

                            Rectangle {
                                z: 1
                                anchors.fill: parent
                                radius: 10
                                color: "#801E1D1E"
                            }

                            Text {
                                id: mediaSourceLabel
                                z: 2; anchors.left: parent.left; anchors.leftMargin: 13; anchors.top: parent.top; anchors.topMargin: 12
                                text: (root.mediaAvailable ? root.mediaPlayerName.toUpperCase() : "MEDIA") + "  󰅀"
                                color: mediaSourceMouse.containsMouse ? root.colActive : root.colMuted
                                font { family: root.fontFamily; pixelSize: 8; bold: true; letterSpacing: 1.1 }
                                MouseArea { id: mediaSourceMouse; anchors.fill: parent; anchors.margins: -6; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: { root.mediaSelectorOpen = !root.mediaSelectorOpen; root.wifiSelectorOpen = false; root.wifiPasswordOpen = false; mediaListProc.running = true; } }
                            }
                            Text { z: 2; anchors.left: parent.left; anchors.leftMargin: 13; anchors.right: mediaControls.left; anchors.rightMargin: 10; anchors.top: parent.top; anchors.topMargin: 31; text: root.mediaTitle; elide: Text.ElideRight; color: root.colActive; font { family: root.fontFamily; pixelSize: 12; bold: true } }
                            Text { z: 2; anchors.left: parent.left; anchors.leftMargin: 13; anchors.right: mediaControls.left; anchors.rightMargin: 10; anchors.top: parent.top; anchors.topMargin: 51; text: root.mediaArtist; elide: Text.ElideRight; color: root.colFg; font { family: root.fontFamily; pixelSize: 9 } }
                            Row {
                                id: mediaControls; z: 2; anchors.right: parent.right; anchors.rightMargin: 12; anchors.verticalCenter: parent.verticalCenter; spacing: 5
                                Repeater { model: [{ icon: "󰒮", action: "previous" }, { icon: root.mediaStatus === "Playing" ? "󰏤" : "󰐊", action: "play-pause" }, { icon: "󰒭", action: "next" }]; Rectangle { required property var modelData; width: modelData.action === "play-pause" ? 38 : 30; height: 34; radius: 9; color: mediaButton.containsMouse ? "#30FFFFFF" : "#12FFFFFF"; Text { anchors.centerIn: parent; text: modelData.icon; color: root.colFg; font { family: root.fontFamily; pixelSize: modelData.action === "play-pause" ? 17 : 13 } } MouseArea { id: mediaButton; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: root.mediaAction(modelData.action) } } }
                            }
                            Rectangle {
                                id: mediaProgressTrack
                                z: 2
                                anchors.left: parent.left; anchors.leftMargin: 13
                                anchors.right: parent.right; anchors.rightMargin: 54
                                anchors.bottom: parent.bottom; anchors.bottomMargin: 12
                                height: 4; radius: 2; color: "#45FFFFFF"
                                Rectangle {
                                    height: parent.height; radius: 2; color: root.colActive
                                    width: parent.width * Math.min(1, root.mediaLength > 0 ? root.mediaPosition / root.mediaLength : 0)
                                    Behavior on width { NumberAnimation { duration: 180 } }
                                }
                                MouseArea {
                                    anchors.left: parent.left; anchors.right: parent.right
                                    anchors.top: parent.top; anchors.bottom: parent.bottom
                                    anchors.topMargin: -7; anchors.bottomMargin: -7
                                    cursorShape: Qt.PointingHandCursor
                                    onPressed: mouse => root.seekMedia(mouse.x / width)
                                }
                            }
                            Text {
                                z: 2; anchors.right: parent.right; anchors.rightMargin: 11; anchors.bottom: parent.bottom; anchors.bottomMargin: 8
                                text: root.mediaLength > 0 ? root.formatMediaTime(root.mediaPosition) : "—:—"
                                color: root.colMuted; font { family: root.fontFamily; pixelSize: 8; bold: true }
                            }
                        }

                        Grid {
                            width: parent.width; height: 114; columns: 2; spacing: 6
                            Repeater { model: [
                                { icon: root.wifiEnabled ? root.netIcon : "󰤭", title: "Wi-Fi", value: root.wifiEnabled ? root.netType : "Disabled", type: "wifi", active: root.wifiEnabled },
                                { icon: root.micMuted ? "󰍭" : "󰍬", title: "Microphone", value: root.micMuted ? "Muted" : root.micPercent + "%", type: "mic", active: !root.micMuted },
                                { icon: "󰂯", title: "Bluetooth", value: !root.bluetoothAvailable ? "Unavailable" : (root.bluetoothBlocked ? "Disabled" : "Enabled"), type: "bluetooth", active: root.bluetoothAvailable && !root.bluetoothBlocked },
                                { icon: "󰌌", title: "Layout", value: root.kbLayout, type: "lang", active: true }
                            ]; Rectangle { required property var modelData; width: (parent.width - 6) / 2; height: 54; radius: 10; color: toggleMouse.containsMouse ? "#30FFFFFF" : (modelData.active ? "#20FFFFFF" : "#10FFFFFF"); border.width: 1; border.color: modelData.active ? "#30FFFFFF" : "#18FFFFFF"; Text { anchors.left: parent.left; anchors.leftMargin: 11; anchors.verticalCenter: parent.verticalCenter; text: modelData.icon; color: modelData.active ? root.colActive : root.colMuted; font { family: root.fontFamily; pixelSize: 16 } } Column { anchors.left: parent.left; anchors.leftMargin: 42; anchors.verticalCenter: parent.verticalCenter; spacing: 2; Text { text: modelData.title; color: root.colFg; font { family: root.fontFamily; pixelSize: 10; bold: true } } Text { text: modelData.value; color: root.colMuted; font { family: root.fontFamily; pixelSize: 8 } } } MouseArea { id: toggleMouse; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: { if (modelData.type === "lang") root.switchLayout(); else if (modelData.type === "mic") root.toggleMic(); else if (modelData.type === "wifi") { root.wifiSelectorOpen = !root.wifiSelectorOpen; root.mediaSelectorOpen = false; wifiListProc.running = true; } else root.toggleBluetooth(); } } } }
                        }

                        Rectangle {
                            width: parent.width; height: 48; radius: 10; color: "#18FFFFFF"; border.width: 1; border.color: "#20FFFFFF"
                            Text { anchors.left: parent.left; anchors.leftMargin: 12; anchors.verticalCenter: parent.verticalCenter; text: root.volIcon; color: root.isMuted ? root.colMuted : root.colActive; font { family: root.fontFamily; pixelSize: 15 } }
                            Rectangle { id: monoVolumeTrack; anchors.left: parent.left; anchors.leftMargin: 42; anchors.right: parent.right; anchors.rightMargin: 52; anchors.verticalCenter: parent.verticalCenter; height: 6; radius: 3; color: "#30FFFFFF"; Rectangle { height: parent.height; radius: 3; width: parent.width * root.volPercent / 100; color: root.isMuted ? root.colMuted : root.colActive; Behavior on width { NumberAnimation { duration: 80 } } } }
                            Text { anchors.right: parent.right; anchors.rightMargin: 12; anchors.verticalCenter: parent.verticalCenter; text: root.volPercent + "%"; color: root.colMuted; font { family: root.fontFamily; pixelSize: 9; bold: true } }
                            MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: mouse => root.setVolume(Math.round(Math.max(0, Math.min(1, (mouse.x - 42) / (width - 94))) * 100)); onPositionChanged: mouse => { if (pressed) root.setVolume(Math.round(Math.max(0, Math.min(1, (mouse.x - 42) / (width - 94))) * 100)); } onWheel: wheel => root.setVolume(root.volPercent + (wheel.angleDelta.y > 0 ? 5 : -5)) }
                        }

                        Row {
                            width: parent.width; height: 44; spacing: 5
                            Repeater { model: [{ label: "CPU", value: root.cpuPercent + "%" }, { label: "RAM", value: root.ramPercent + "%" }, { label: "GPU", value: root.gpuPercent + "%" }, { label: root.batteryPercent >= 0 ? "BAT" : "TEMP", value: root.batteryPercent >= 0 ? root.batteryPercent + "%" : root.cpuTemp + "°C" }]; Rectangle { required property var modelData; width: (parent.width - 15) / 4; height: parent.height; radius: 10; color: metricMouse.containsMouse ? "#25FFFFFF" : "#12FFFFFF"; border.width: 1; border.color: "#18FFFFFF"; Column { anchors.centerIn: parent; spacing: 3; Text { anchors.horizontalCenter: parent.horizontalCenter; text: modelData.value; color: root.colFg; font { family: root.fontFamily; pixelSize: 10; bold: true } } Text { anchors.horizontalCenter: parent.horizontalCenter; text: modelData.label; color: root.colMuted; font { family: root.fontFamily; pixelSize: 7; bold: true } } } MouseArea { id: metricMouse; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: root.openBtop() } } }
                        }

                        Row {
                            width: parent.width; height: 32; spacing: 5
                            Rectangle {
                                width: (parent.width - 10) / 3; height: parent.height; radius: 8
                                color: root.recordMode === "screen" ? "#32FFFFFF" : "#12FFFFFF"; border.width: 1; border.color: "#20FFFFFF"
                                Text { anchors.centerIn: parent; text: "󰹑  Screen"; color: root.colFg; font { family: root.fontFamily; pixelSize: 8; bold: true } }
                                MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: root.recordMode = "screen" }
                            }
                            Rectangle {
                                width: (parent.width - 10) / 3; height: parent.height; radius: 8
                                color: root.recordMode === "area" ? "#32FFFFFF" : "#12FFFFFF"; border.width: 1; border.color: "#20FFFFFF"
                                Text { anchors.centerIn: parent; text: "󰩭  Area"; color: root.colFg; font { family: root.fontFamily; pixelSize: 8; bold: true } }
                                MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: root.recordMode = "area" }
                            }
                            Rectangle {
                                width: (parent.width - 10) / 3; height: parent.height; radius: 8
                                color: root.recordAudio ? "#32FFFFFF" : "#12FFFFFF"; border.width: 1; border.color: "#20FFFFFF"
                                Text { anchors.centerIn: parent; text: root.recordAudio ? "󰕾  System" : "󰖁  No audio"; color: root.recordAudio ? root.colFg : root.colMuted; font { family: root.fontFamily; pixelSize: 8; bold: true } }
                                MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: root.recordAudio = !root.recordAudio }
                            }
                        }

                        Row {
                            width: parent.width; height: 54; spacing: 5

                            Repeater { model: [{ label: "Snip", icon: "󰄀", command: "snip" }, { label: root.isRecording ? root.formatMediaTime(root.recordSeconds) : "Record", icon: root.isRecording ? "󰻃" : "󰑊", command: "record" }, { label: root.isMuted ? "Unmute" : "Mute", icon: root.volIcon, command: "mute" }, { label: "Lock", icon: "󰌾", command: "lock" }]; Rectangle { required property var modelData; width: (parent.width - 15) / 4; height: parent.height; radius: 10; color: modelData.command === "record" && root.isRecording ? "#38C74028" : (quickActionMouse.containsMouse ? "#30FFFFFF" : "#18FFFFFF"); border.width: 1; border.color: modelData.command === "record" && root.isRecording ? "#88C74028" : "#20FFFFFF"; Column { anchors.centerIn: parent; spacing: 3; Text { anchors.horizontalCenter: parent.horizontalCenter; text: modelData.icon; color: modelData.command === "record" && root.isRecording ? "#FF8A78" : root.colFg; font { family: root.fontFamily; pixelSize: 14 } } Text { anchors.horizontalCenter: parent.horizontalCenter; text: modelData.label; color: root.colMuted; font { family: root.fontFamily; pixelSize: 8; bold: true } } } MouseArea { id: quickActionMouse; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: { if (modelData.command === "record") root.toggleRecording(); else if (modelData.command === "mute") root.toggleMute(); else if (modelData.command === "lock") { root.commandCenterOpen = false; Quickshell.execDetached(["hyprlock"]); } else { root.commandCenterOpen = false; Quickshell.execDetached(["sh", "-c", "mkdir -p ~/Pictures/Screenshots && file=~/Pictures/Screenshots/screenshot_$(date +%Y%m%d_%H%M%S).png; grim -g \"$(slurp)\" \"$file\" && wl-copy < \"$file\""]); } } } } }
                        }
                    }
                }

                // 5. Випливаючий Power Control Center справа
                Rectangle {
                    id: controlCenterCard
                    z: 5
                    anchors.right: parent.right
                    y: root.powerOpen ? 44 : 20
                    width: 164
                    height: 164
                    color: root.colBg
                    radius: 12
                    border.width: 1
                    border.color: root.colBorder
                    opacity: root.powerOpen ? 1.0 : 0.0
                    scale: root.powerOpen ? 1.0 : 0.82
                    visible: opacity > 0.01
                    transformOrigin: Item.TopRight

                    Behavior on y {
                        NumberAnimation {
                            duration: 380
                            easing.type: Easing.OutBack
                            easing.overshoot: 2.2
                        }
                    }

                    Behavior on opacity {
                        NumberAnimation {
                            duration: 180
                            easing.type: Easing.OutQuad
                        }
                    }

                    Behavior on scale {
                        NumberAnimation {
                            duration: 380
                            easing.type: Easing.OutBack
                            easing.overshoot: 2.4
                        }
                    }

                    Grid {
                        id: grid
                        anchors.fill: parent
                        anchors.margins: 8
                        columns: 2
                        spacing: 6

                        // 1. Lock Screen
                        Rectangle {
                            width: 71
                            height: 71
                            radius: 8
                            color: lockMouse.containsMouse ? root.colCardHover : root.colCard

                            Behavior on color {
                                ColorAnimation { duration: 150 }
                            }

                            Column {
                                anchors.centerIn: parent
                                spacing: 4

                                Text {
                                    text: "󰌾"
                                    color: lockMouse.containsMouse ? "#FFFFFF" : root.colFg
                                    font { family: root.fontFamily; pixelSize: 20 }
                                    anchors.horizontalCenter: parent.horizontalCenter
                                }

                                Text {
                                    text: "Lock"
                                    color: lockMouse.containsMouse ? "#FFFFFF" : root.colMuted
                                    font { family: root.fontFamily; pixelSize: 11; bold: true }
                                    anchors.horizontalCenter: parent.horizontalCenter
                                }
                            }

                            MouseArea {
                                id: lockMouse
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: {
                                    root.powerOpen = false;
                                    Quickshell.execDetached(["hyprlock"]);
                                }
                            }
                        }

                        // 2. Log Out
                        Rectangle {
                            width: 71
                            height: 71
                            radius: 8
                            color: logoutMouse.containsMouse ? root.colCardHover : root.colCard

                            Behavior on color {
                                ColorAnimation { duration: 150 }
                            }

                            Column {
                                anchors.centerIn: parent
                                spacing: 4

                                Text {
                                    text: "󰍃"
                                    color: logoutMouse.containsMouse ? "#FFFFFF" : root.colFg
                                    font { family: root.fontFamily; pixelSize: 20 }
                                    anchors.horizontalCenter: parent.horizontalCenter
                                }

                                Text {
                                    text: "Logout"
                                    color: logoutMouse.containsMouse ? "#FFFFFF" : root.colMuted
                                    font { family: root.fontFamily; pixelSize: 11; bold: true }
                                    anchors.horizontalCenter: parent.horizontalCenter
                                }
                            }

                            MouseArea {
                                id: logoutMouse
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: {
                                    root.powerOpen = false;
                                    Quickshell.execDetached(["hyprctl", "dispatch", "exit"]);
                                }
                            }
                        }

                        // 3. Restart
                        Rectangle {
                            width: 71
                            height: 71
                            radius: 8
                            color: rebootMouse.containsMouse ? root.colCardHover : root.colCard

                            Behavior on color {
                                ColorAnimation { duration: 150 }
                            }

                            Column {
                                anchors.centerIn: parent
                                spacing: 4

                                Text {
                                    text: "󰜉"
                                    color: rebootMouse.containsMouse ? "#FFFFFF" : root.colFg
                                    font { family: root.fontFamily; pixelSize: 20 }
                                    anchors.horizontalCenter: parent.horizontalCenter
                                }

                                Text {
                                    text: "Restart"
                                    color: rebootMouse.containsMouse ? "#FFFFFF" : root.colMuted
                                    font { family: root.fontFamily; pixelSize: 11; bold: true }
                                    anchors.horizontalCenter: parent.horizontalCenter
                                }
                            }

                            MouseArea {
                                id: rebootMouse
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: {
                                    root.powerOpen = false;
                                    Quickshell.execDetached(["systemctl", "reboot"]);
                                }
                            }
                        }

                        // 4. Shut Down
                        Rectangle {
                            width: 71
                            height: 71
                            radius: 8
                            color: shutdownMouse.containsMouse ? "#802207" : root.colCard

                            Behavior on color {
                                ColorAnimation { duration: 150 }
                            }

                            Column {
                                anchors.centerIn: parent
                                spacing: 4

                                Text {
                                    text: "󰐥"
                                    color: shutdownMouse.containsMouse ? "#FFFFFF" : "#c74028"
                                    font { family: root.fontFamily; pixelSize: 20 }
                                    anchors.horizontalCenter: parent.horizontalCenter
                                }

                                Text {
                                    text: "Power"
                                    color: shutdownMouse.containsMouse ? "#FFFFFF" : "#c74028"
                                    font { family: root.fontFamily; pixelSize: 11; bold: true }
                                    anchors.horizontalCenter: parent.horizontalCenter
                                }
                            }

                            MouseArea {
                                id: shutdownMouse
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: {
                                    root.powerOpen = false;
                                    Quickshell.execDetached(["systemctl", "poweroff"]);
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    PanelWindow {
        id: notificationWindow
        screen: Quickshell.screens.length > 0 ? Quickshell.screens[0] : null
        anchors.top: true
        anchors.right: true
        margins.top: 0
        margins.right: 10
        implicitWidth: 340
        // Keep the layer surface stable while delegates animate or disappear.
        // Resizing a translucent surface on every removal can leave stale
        // compositor damage behind the cards.
        implicitHeight: notificationWindow.screen ? notificationWindow.screen.height : 1
        exclusiveZone: 0
        color: "transparent"

        mask: Region { Region { item: notificationColumn } }

        Column {
            id: notificationColumn
            y: 10
            width: parent.width
            spacing: 8

            Repeater {
                model: notificationServer.trackedNotifications

                Rectangle {
                    id: notificationCard
                    required property var modelData
                    property bool closing: false
                    property bool expireAfterClose: false

                    function closeAnimated(expireNotification) {
                        if (closing) return;
                        expireAfterClose = expireNotification;
                        closing = true;
                        closeAnimationTimer.restart();
                    }

                    width: notificationColumn.width
                    height: 78
                    x: closing ? width + 24 : 0
                    opacity: closing ? 0 : 1
                    radius: 10
                    color: "#F01E1D1E"
                    border.width: 1
                    border.color: modelData.urgency === NotificationUrgency.Critical ? "#88C74028" : "#45FFFFFF"

                    Behavior on x {
                        NumberAnimation { duration: 260; easing.type: Easing.InCubic }
                    }
                    Behavior on opacity {
                        NumberAnimation { duration: 210; easing.type: Easing.InQuad }
                    }

                    Rectangle {
                        anchors.left: parent.left; anchors.leftMargin: 10
                        anchors.verticalCenter: parent.verticalCenter
                        width: 42; height: 42; radius: 10
                        color: "#22FFFFFF"
                        Image { anchors.fill: parent; anchors.margins: 7; source: modelData.appIcon !== "" ? Quickshell.iconPath(modelData.appIcon) : ""; fillMode: Image.PreserveAspectFit; visible: modelData.appIcon !== "" }
                        Text { anchors.centerIn: parent; visible: modelData.appIcon === ""; text: "󰂚"; color: "#CACCCA"; font { family: "JetBrainsMono Nerd Font"; pixelSize: 17 } }
                    }

                    Text {
                        anchors.left: parent.left; anchors.leftMargin: 62
                        anchors.right: closeNotification.left; anchors.rightMargin: 8
                        anchors.top: parent.top; anchors.topMargin: 12
                        text: modelData.summary || modelData.appName
                        elide: Text.ElideRight; color: "#FFFFFF"
                        font { family: "JetBrainsMono Nerd Font"; pixelSize: 11; bold: true }
                    }
                    Text {
                        anchors.left: parent.left; anchors.leftMargin: 62
                        anchors.right: parent.right; anchors.rightMargin: 12
                        anchors.top: parent.top; anchors.topMargin: 34
                        text: modelData.body
                        maximumLineCount: 2; elide: Text.ElideRight; wrapMode: Text.Wrap
                        color: "#9E9E9E"; font { family: "JetBrainsMono Nerd Font"; pixelSize: 9 }
                    }
                    Text {
                        id: closeNotification
                        anchors.right: parent.right; anchors.rightMargin: 10
                        anchors.top: parent.top; anchors.topMargin: 9
                        text: "󰅖"; color: closeNotificationMouse.containsMouse ? "#FFFFFF" : "#777777"
                        font { family: "JetBrainsMono Nerd Font"; pixelSize: 12 }
                        MouseArea { id: closeNotificationMouse; anchors.fill: parent; anchors.margins: -7; enabled: !notificationCard.closing; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: notificationCard.closeAnimated(false) }
                    }
                    MouseArea {
                        anchors.fill: parent
                        z: -1
                        cursorShape: Qt.PointingHandCursor
                        enabled: !notificationCard.closing
                        onClicked: { if (modelData.actions.length > 0) modelData.actions[0].invoke(); notificationCard.closeAnimated(false); }
                    }
                    Timer {
                        id: expiryTimer
                        interval: modelData.expireTimeout > 0 ? Math.max(1500, modelData.expireTimeout) : 5000
                        running: true
                        onTriggered: notificationCard.closeAnimated(true)
                    }
                    Timer {
                        id: closeAnimationTimer
                        interval: 270
                        repeat: false
                        onTriggered: {
                            if (notificationCard.expireAfterClose) modelData.expire();
                            else modelData.dismiss();
                        }
                    }
                }
            }
        }
    }
}
