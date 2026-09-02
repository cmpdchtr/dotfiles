import Quickshell
import Quickshell.Wayland
import Quickshell.Io
import Quickshell.Hyprland
import Quickshell.Networking
import Quickshell.Bluetooth
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
            WlrLayershell.keyboardFocus: root.subPanel === "wifiPassword"
                ? WlrKeyboardFocus.Exclusive
                : WlrKeyboardFocus.None

            onSubPanelChanged: {
                if (root.subPanel === "wifiPassword") {
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

            // Network state comes straight off NetworkManager through
            // Quickshell.Networking instead of a polled `nmcli` pipeline. The
            // device list, signal strengths and connection states are all live
            // properties, which is the thing the old panel was missing: nothing
            // ever asked for a rescan, so the list it showed was whatever
            // NetworkManager happened to have cached.
            readonly property var wifiDevice: {
                for (let d of Networking.devices.values) if (d.type === DeviceType.Wifi) return d;
                return null;
            }
            readonly property var wiredDevice: {
                for (let d of Networking.devices.values) if (d.type === DeviceType.Wired) return d;
                return null;
            }
            readonly property var wiredNetwork: root.wiredDevice ? root.wiredDevice.network : null
            readonly property bool ethernetAvailable: root.wiredDevice !== null
            readonly property bool ethernetConnected: root.wiredDevice ? root.wiredDevice.connected : false
            readonly property bool wifiOn: Networking.wifiEnabled
            readonly property bool wifiConnected: root.wifiDevice ? root.wifiDevice.connected : false

            // Quickshell already folds the access points of one SSID into a
            // single Network, so this only has to order them: live first, then
            // saved, then by signal strength.
            readonly property var wifiNetworks: {
                if (!root.wifiDevice) return [];
                let list = root.wifiDevice.networks.values.filter(n => n.name !== "");
                list.sort((a, b) => {
                    if (a.connected !== b.connected) return a.connected ? -1 : 1;
                    if (a.known !== b.known) return a.known ? -1 : 1;
                    return b.signalStrength - a.signalStrength;
                });
                return list;
            }
            readonly property var activeWifiNetwork: {
                for (let n of root.wifiNetworks) if (n.connected) return n;
                return null;
            }

            readonly property string netIcon: root.ethernetConnected
                ? "󰈀"
                : (!root.wifiOn
                    ? "󰤭"
                    : (root.wifiConnected ? root.signalGlyph(root.activeWifiNetwork) : "󰤯"))
            readonly property string netType: root.ethernetConnected
                ? "Ethernet"
                : (!root.wifiOn
                    ? "Off"
                    : (root.activeWifiNetwork ? root.activeWifiNetwork.name : "Disconnected"))

            // signalStrength is a 0..1 double, not a percentage.
            function signalGlyph(net) {
                if (!net) return "󰤯";
                let s = net.signalStrength;
                if (s > 0.75) return "󰤨";
                if (s > 0.5) return "󰤥";
                if (s > 0.25) return "󰤢";
                return "󰤟";
            }

            function signalPercent(net) {
                return net ? Math.round(net.signalStrength * 100) : 0;
            }

            // Rows are a fixed height, so a scrolling list can size itself to
            // however many it is allowed to show at once.
            function listHeight(count, rowHeight, gap, maxRows) {
                let rows = Math.max(1, Math.min(maxRows, count));
                return rows * rowHeight + (rows - 1) * gap;
            }

            // Bluetooth is native too, so pairing state, battery level and
            // connection progress are per-device properties rather than
            // something scraped out of `bluetoothctl`.
            readonly property var btAdapter: Bluetooth.defaultAdapter
            readonly property bool btAvailable: root.btAdapter !== null
            readonly property bool btOn: root.btAdapter ? root.btAdapter.enabled : false
            readonly property bool btScanning: root.btAdapter ? root.btAdapter.discovering : false
            readonly property var btDevices: {
                if (!root.btAdapter || !Bluetooth.devices) return [];
                let list = Bluetooth.devices.values.slice();
                list.sort((a, b) => {
                    if (a.connected !== b.connected) return a.connected ? -1 : 1;
                    if (a.paired !== b.paired) return a.paired ? -1 : 1;
                    return a.name.localeCompare(b.name);
                });
                return list;
            }
            readonly property int btConnectedCount: root.btDevices.filter(d => d.connected).length

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
            property bool mediaAvailable: false
            property int mediaMisses: 0
            property bool isRecording: false
            property bool micMuted: false
            property int micPercent: 0
            property int mediaPosition: 0
            property int mediaLength: 0
            property int gpuPercent: 0
            property int batteryPercent: -1
            property string recordMode: "screen"
            property bool recordAudio: false
            property int recordSeconds: 0

            // One slot instead of three mutually-exclusive booleans. The old
            // trio could reach states like "Wi-Fi list open behind a password
            // prompt for a network the list no longer contains".
            property string subPanel: ""
            readonly property bool subPanelOpen: root.subPanel !== ""
            property var pendingWifiNetwork: null
            property string wifiError: ""
            property string btError: ""

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

            function toggleWifiRadio() {
                root.wifiError = "";
                Networking.wifiEnabled = !Networking.wifiEnabled;
            }

            function toggleEthernet() {
                if (!root.wiredNetwork) return;
                if (root.wiredNetwork.connected) root.wiredNetwork.disconnect();
                else root.wiredNetwork.connect();
            }

            function openWifiManager() {
                root.subPanel = "";
                root.commandCenterOpen = false;
                Quickshell.execDetached(["nm-connection-editor"]);
            }

            function selectMediaPlayer(service) {
                root.preferredMediaService = service;
                root.subPanel = "";
                mediaPollProc.running = true;
            }

            // A saved or open network can be brought straight up; an unknown
            // secured one needs a passphrase first. Either way NetworkManager
            // reports back through Network.connectionFailed, so a wrong password
            // now surfaces in the panel instead of failing silently.
            function activateWifi(net) {
                if (!net) return;
                root.wifiError = "";
                if (net.connected) {
                    net.disconnect();
                    return;
                }
                if (net.known || net.security === WifiSecurityType.Open) {
                    net.connect();
                    return;
                }
                root.pendingWifiNetwork = net;
                wifiPasswordInput.text = "";
                root.subPanel = "wifiPassword";
            }

            function submitWifiPassword() {
                if (!root.pendingWifiNetwork || !wifiPasswordInput.text) return;
                root.wifiError = "";
                root.pendingWifiNetwork.connectWithPsk(wifiPasswordInput.text);
                wifiPasswordInput.text = "";
                root.subPanel = "wifi";
            }

            function forgetWifi(net) {
                if (!net || !net.known) return;
                root.wifiError = "";
                net.forget();
            }

            function wifiStatusText(net) {
                if (!net) return "";
                if (net.stateChanging) return ConnectionState.toString(net.state) + "\u2026";
                if (net.connected) return "Connected \u00b7 click to disconnect";
                let sec = WifiSecurityType.toString(net.security);
                return net.known ? "Saved \u00b7 " + sec : sec;
            }

            function cycleMediaPlayer() {
                mediaCycleProc.running = true;
            }

            function toggleBluetooth() {
                if (!root.btAdapter) return;
                root.btError = "";
                root.btAdapter.enabled = !root.btAdapter.enabled;
            }

            // One click does the next sensible thing, so the row never needs a
            // separate pair/connect/disconnect control.
            function btDeviceAction(dev) {
                if (!dev) return;
                root.btError = "";
                if (dev.pairing) dev.cancelPair();
                else if (dev.connected) dev.disconnect();
                else if (dev.paired || dev.bonded) dev.connect();
                else dev.pair();
            }

            function btForget(dev) {
                if (!dev) return;
                root.btError = "";
                dev.forget();
            }

            // BlueZ reports battery as a percentage on some devices and a 0..1
            // fraction on others; normalise before showing it.
            function btBatteryPercent(dev) {
                if (!dev || !dev.batteryAvailable) return -1;
                let b = dev.battery;
                return Math.round(b <= 1 ? b * 100 : b);
            }

            function btGlyph(dev) {
                let icon = (dev && dev.icon) ? dev.icon.toLowerCase() : "";
                if (icon.includes("headset")) return "󰋎";
                if (icon.includes("headphone")) return "󰋋";
                if (icon.includes("speaker") || icon.includes("audio")) return "󰓃";
                if (icon.includes("phone")) return "󰄜";
                if (icon.includes("mouse") || icon.includes("pointing")) return "󰍽";
                if (icon.includes("keyboard")) return "󰌌";
                if (icon.includes("computer") || icon.includes("laptop")) return "󰌢";
                if (icon.includes("watch")) return "󰔠";
                if (icon.includes("printer")) return "󰐪";
                if (icon.includes("gaming") || icon.includes("joystick")) return "󰺵";
                if (icon.includes("display") || icon.includes("video")) return "󰍹";
                return "󰂯";
            }

            function btStatusText(dev) {
                if (!dev) return "";
                if (dev.pairing) return "Pairing\u2026 \u00b7 click to cancel";
                if (dev.state === BluetoothDeviceState.Connecting) return "Connecting\u2026";
                if (dev.state === BluetoothDeviceState.Disconnecting) return "Disconnecting\u2026";
                if (dev.connected) {
                    let battery = root.btBatteryPercent(dev);
                    return battery >= 0 ? "Connected \u00b7 " + battery + "%" : "Connected";
                }
                if (dev.paired || dev.bonded) return "Paired \u00b7 click to connect";
                return "Click to pair";
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

                        // Height follows the body's implicit height rather than a
                        // hand-summed constant, so adding a row to any panel can
                        // no longer leave the card the wrong size. Kept separate
                        // from `height` so the Command Centre card can animate
                        // towards the same target on the same curve.
                        readonly property real naturalHeight: 43 + panelBody.implicitHeight + 12

                        height: naturalHeight
                        Behavior on height {
                            NumberAnimation { duration: 340; easing.type: Easing.OutQuint }
                        }

                        anchors.horizontalCenter: parent.horizontalCenter
                        y: commandCenterCard.y + 10
                        radius: 9
                        color: "#FC1E1D1E"
                        border.width: 1
                        border.color: "#45FFFFFF"
                        clip: true
                        transformOrigin: Item.Top
                        scale: 0.95 + 0.05 * root.selProgress
                        // Gated on the card's progress as well, so a sub-panel is
                        // never caught painting over the bar while the card behind
                        // it is still smaller than the island.
                        opacity: root.selProgress * root.clamp01((root.ccProgress - 0.12) / 0.5)
                        visible: opacity > 0.01

                        Text {
                            anchors.left: parent.left; anchors.leftMargin: 14
                            anchors.top: parent.top; anchors.topMargin: 13
                            text: root.subPanel === "wifiPassword"
                                ? "CONNECT TO WI-FI"
                                : (root.subPanel === "media"
                                    ? "MEDIA PLAYERS"
                                    : (root.subPanel === "bluetooth" ? "BLUETOOTH" : "WI-FI NETWORKS"))
                            color: root.colActive
                            font { family: root.fontFamily; pixelSize: 10; bold: true; letterSpacing: 1.2 }
                        }

                        // Live scan indicator. Both lists only scan while they are
                        // on screen, so this doubles as a reason the list is short.
                        Text {
                            anchors.left: parent.left; anchors.leftMargin: 150
                            anchors.top: parent.top; anchors.topMargin: 13
                            visible: (root.subPanel === "wifi" && root.wifiOn)
                                || (root.subPanel === "bluetooth" && root.btScanning)
                            text: "󰍉 SCANNING"
                            color: root.colMuted
                            font { family: root.fontFamily; pixelSize: 8; bold: true; letterSpacing: 1.1 }
                            SequentialAnimation on opacity {
                                running: true; loops: Animation.Infinite
                                NumberAnimation { to: 0.35; duration: 900; easing.type: Easing.InOutQuad }
                                NumberAnimation { to: 1.0; duration: 900; easing.type: Easing.InOutQuad }
                            }
                        }

                        Rectangle {
                            id: selectorCloseButton
                            z: 100
                            anchors.right: parent.right; anchors.rightMargin: 14
                            anchors.top: parent.top; anchors.topMargin: 8
                            width: 28; height: 28; radius: 8
                            color: selectorCloseMouse.containsMouse ? "#28FFFFFF" : "transparent"
                            scale: selectorCloseMouse.pressed ? 0.86 : 1
                            Behavior on scale { NumberAnimation { duration: 200; easing.type: Easing.OutBack; easing.overshoot: 3 } }
                            Text {
                                anchors.centerIn: parent
                                text: root.subPanel === "wifiPassword" ? "󰅁" : "󰅖"
                                color: selectorCloseMouse.containsMouse ? root.colActive : root.colMuted
                                font { family: root.fontFamily; pixelSize: 13 }
                            }
                            MouseArea {
                                id: selectorCloseMouse
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                // The password prompt is a step inside the Wi-Fi
                                // panel, so its close button steps back rather
                                // than dismissing the whole thing.
                                onPressed: mouse => {
                                    mouse.accepted = true;
                                    root.subPanel = root.subPanel === "wifiPassword" ? "wifi" : "";
                                }
                            }
                        }

                        Column {
                            id: panelBody
                            anchors.left: parent.left; anchors.right: parent.right
                            anchors.top: parent.top; anchors.topMargin: 43
                            anchors.leftMargin: 10; anchors.rightMargin: 10
                            spacing: 6

                            // ── Media players ───────────────────────────────
                            Column {
                                width: parent.width
                                spacing: 6
                                visible: root.subPanel === "media"

                                Repeater {
                                    model: root.mediaPlayers
                                    Rectangle {
                                        required property var modelData
                                        width: parent.width; height: 54; radius: 9
                                        color: modelData.service === root.mediaService ? "#30FFFFFF" : (playerChoiceMouse.containsMouse ? "#24FFFFFF" : "#10FFFFFF")
                                        border.width: 1; border.color: modelData.service === root.mediaService ? "#55FFFFFF" : "#18FFFFFF"
                                        Behavior on color { ColorAnimation { duration: 140 } }
                                        Text { anchors.left: parent.left; anchors.leftMargin: 12; anchors.verticalCenter: parent.verticalCenter; text: modelData.status === "Playing" ? "󰐊" : "󰏤"; color: modelData.status === "Playing" ? root.colActive : root.colMuted; font { family: root.fontFamily; pixelSize: 15 } }
                                        Column { anchors.left: parent.left; anchors.leftMargin: 42; anchors.verticalCenter: parent.verticalCenter; spacing: 2; Text { text: modelData.name; color: root.colFg; font { family: root.fontFamily; pixelSize: 10; bold: true } } Text { text: modelData.status; color: root.colMuted; font { family: root.fontFamily; pixelSize: 8 } } }
                                        Text { anchors.right: parent.right; anchors.rightMargin: 12; anchors.verticalCenter: parent.verticalCenter; text: modelData.service === root.mediaService ? "󰄬" : "󰅂"; color: root.colMuted; font { family: root.fontFamily; pixelSize: 12 } }
                                        MouseArea { id: playerChoiceMouse; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: root.selectMediaPlayer(modelData.service) }
                                    }
                                }

                                Text {
                                    width: parent.width; height: 54
                                    visible: root.mediaPlayers.length === 0
                                    verticalAlignment: Text.AlignVCenter
                                    horizontalAlignment: Text.AlignHCenter
                                    text: "No MPRIS players running"
                                    color: root.colMuted
                                    font { family: root.fontFamily; pixelSize: 9 }
                                }
                            }

                            // ── Wi-Fi ───────────────────────────────────────
                            Column {
                                width: parent.width
                                spacing: 6
                                visible: root.subPanel === "wifi"

                                // The radio switch the old panel never had: the
                                // tile could report "Disabled" with no way to
                                // turn the adapter back on.
                                Rectangle {
                                    width: parent.width; height: 48; radius: 9
                                    color: wifiRadioMouse.containsMouse ? "#2CFFFFFF" : (root.wifiOn ? "#20FFFFFF" : "#10FFFFFF")
                                    border.width: 1; border.color: root.wifiOn ? "#40FFFFFF" : "#18FFFFFF"
                                    Behavior on color { ColorAnimation { duration: 140 } }
                                    Text { anchors.left: parent.left; anchors.leftMargin: 12; anchors.verticalCenter: parent.verticalCenter; text: root.wifiOn ? "󰖩" : "󰤭"; color: root.wifiOn ? root.colActive : root.colMuted; font { family: root.fontFamily; pixelSize: 15 } }
                                    Column {
                                        anchors.left: parent.left; anchors.leftMargin: 42; anchors.verticalCenter: parent.verticalCenter; spacing: 2
                                        Text { text: "Wi-Fi"; color: root.colFg; font { family: root.fontFamily; pixelSize: 10; bold: true } }
                                        Text { text: root.wifiOn ? (root.activeWifiNetwork ? root.activeWifiNetwork.name : "On · not connected") : "Off"; color: root.colMuted; font { family: root.fontFamily; pixelSize: 8 } }
                                    }
                                    // Pill switch, so on/off reads at a glance.
                                    Rectangle {
                                        anchors.right: parent.right; anchors.rightMargin: 12; anchors.verticalCenter: parent.verticalCenter
                                        width: 34; height: 18; radius: 9
                                        color: root.wifiOn ? "#66FFFFFF" : "#28FFFFFF"
                                        Behavior on color { ColorAnimation { duration: 180 } }
                                        Rectangle {
                                            y: 3; width: 12; height: 12; radius: 6
                                            x: root.wifiOn ? 19 : 3
                                            color: root.wifiOn ? "#1E1D1E" : root.colMuted
                                            Behavior on x { NumberAnimation { duration: 260; easing.type: Easing.OutBack; easing.overshoot: 2.2 } }
                                            Behavior on color { ColorAnimation { duration: 180 } }
                                        }
                                    }
                                    MouseArea { id: wifiRadioMouse; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: root.toggleWifiRadio() }
                                }

                                Rectangle {
                                    width: parent.width; height: 48; radius: 9
                                    visible: root.ethernetAvailable
                                    color: ethernetMouse.containsMouse ? "#2CFFFFFF" : (root.ethernetConnected ? "#20FFFFFF" : "#10FFFFFF")
                                    border.width: 1; border.color: root.ethernetConnected ? "#40FFFFFF" : "#18FFFFFF"
                                    Behavior on color { ColorAnimation { duration: 140 } }
                                    Text { anchors.left: parent.left; anchors.leftMargin: 12; anchors.verticalCenter: parent.verticalCenter; text: "󰈀"; color: root.ethernetConnected ? root.colActive : root.colMuted; font { family: root.fontFamily; pixelSize: 15 } }
                                    Column {
                                        anchors.left: parent.left; anchors.leftMargin: 42; anchors.verticalCenter: parent.verticalCenter; spacing: 2
                                        Text { text: "Ethernet"; color: root.colFg; font { family: root.fontFamily; pixelSize: 10; bold: true } }
                                        Text { text: root.ethernetConnected ? "Connected · click to disconnect" : "Disconnected · click to connect"; color: root.colMuted; font { family: root.fontFamily; pixelSize: 8 } }
                                    }
                                    Text { anchors.right: parent.right; anchors.rightMargin: 12; anchors.verticalCenter: parent.verticalCenter; text: root.ethernetConnected ? "󰄬" : "󰅂"; color: root.ethernetConnected ? root.colActive : root.colMuted; font { family: root.fontFamily; pixelSize: 12 } }
                                    MouseArea { id: ethernetMouse; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: root.toggleEthernet() }
                                }

                                Flickable {
                                    width: parent.width
                                    height: root.listHeight(root.wifiNetworks.length, 54, 6, 5)
                                    contentWidth: width
                                    contentHeight: wifiNetworkColumn.implicitHeight
                                    clip: true
                                    boundsBehavior: Flickable.StopAtBounds
                                    flickableDirection: Flickable.VerticalFlick

                                    Behavior on height {
                                        NumberAnimation { duration: 260; easing.type: Easing.OutQuint }
                                    }

                                    Column {
                                        id: wifiNetworkColumn
                                        width: parent.width
                                        spacing: 6

                                        Text {
                                            width: parent.width; height: 54
                                            visible: root.wifiNetworks.length === 0
                                            verticalAlignment: Text.AlignVCenter
                                            horizontalAlignment: Text.AlignHCenter
                                            text: root.wifiOn ? "Scanning for networks…" : "Wi-Fi is off"
                                            color: root.colMuted
                                            font { family: root.fontFamily; pixelSize: 9 }
                                        }

                                        Repeater {
                                            model: root.wifiNetworks
                                            Rectangle {
                                                id: wifiRow
                                                required property var modelData
                                                width: wifiNetworkColumn.width; height: 54; radius: 9
                                                color: modelData.connected ? "#30FFFFFF" : (wifiChoiceMouse.containsMouse ? "#24FFFFFF" : "#10FFFFFF")
                                                border.width: 1; border.color: modelData.connected ? "#55FFFFFF" : "#18FFFFFF"
                                                Behavior on color { ColorAnimation { duration: 140 } }

                                                // NetworkManager answers asynchronously,
                                                // so a rejected passphrase arrives here
                                                // rather than at the call site.
                                                Connections {
                                                    target: wifiRow.modelData
                                                    function onConnectionFailed(reason) {
                                                        root.wifiError = wifiRow.modelData.name + ": "
                                                            + ConnectionFailReason.toString(reason);
                                                    }
                                                }

                                                Text {
                                                    anchors.left: parent.left; anchors.leftMargin: 12
                                                    anchors.verticalCenter: parent.verticalCenter
                                                    text: root.signalGlyph(wifiRow.modelData)
                                                    color: wifiRow.modelData.connected ? root.colActive : root.colMuted
                                                    font { family: root.fontFamily; pixelSize: 15 }
                                                }
                                                Column {
                                                    anchors.left: parent.left; anchors.leftMargin: 42
                                                    anchors.right: wifiRowRight.left; anchors.rightMargin: 8
                                                    anchors.verticalCenter: parent.verticalCenter
                                                    spacing: 2
                                                    Text {
                                                        width: parent.width
                                                        text: wifiRow.modelData.name
                                                        elide: Text.ElideRight
                                                        color: root.colFg
                                                        font { family: root.fontFamily; pixelSize: 10; bold: true }
                                                    }
                                                    Text {
                                                        width: parent.width
                                                        text: root.wifiStatusText(wifiRow.modelData)
                                                        elide: Text.ElideRight
                                                        color: root.colMuted
                                                        font { family: root.fontFamily; pixelSize: 8 }
                                                    }
                                                }
                                                Row {
                                                    id: wifiRowRight
                                                    anchors.right: parent.right; anchors.rightMargin: 10
                                                    anchors.verticalCenter: parent.verticalCenter
                                                    spacing: 8
                                                    Text {
                                                        anchors.verticalCenter: parent.verticalCenter
                                                        visible: wifiRow.modelData.security !== WifiSecurityType.Open
                                                        text: "󰌾"
                                                        color: root.colMuted
                                                        font { family: root.fontFamily; pixelSize: 10 }
                                                    }
                                                    Text {
                                                        anchors.verticalCenter: parent.verticalCenter
                                                        text: root.signalPercent(wifiRow.modelData) + "%"
                                                        color: root.colMuted
                                                        font { family: root.fontFamily; pixelSize: 8; bold: true }
                                                    }
                                                    // Forget only appears for saved
                                                    // networks, where it is the only way
                                                    // to clear a bad stored passphrase.
                                                    Rectangle {
                                                        anchors.verticalCenter: parent.verticalCenter
                                                        visible: wifiRow.modelData.known
                                                        width: 24; height: 24; radius: 7
                                                        color: wifiForgetMouse.containsMouse ? "#30FF6B6B" : "transparent"
                                                        Behavior on color { ColorAnimation { duration: 140 } }
                                                        Text {
                                                            anchors.centerIn: parent
                                                            text: "󰆴"
                                                            color: wifiForgetMouse.containsMouse ? root.colDanger : root.colMuted
                                                            font { family: root.fontFamily; pixelSize: 11 }
                                                        }
                                                        MouseArea {
                                                            id: wifiForgetMouse
                                                            anchors.fill: parent
                                                            hoverEnabled: true
                                                            cursorShape: Qt.PointingHandCursor
                                                            onClicked: mouse => { mouse.accepted = true; root.forgetWifi(wifiRow.modelData); }
                                                        }
                                                    }
                                                }
                                                MouseArea {
                                                    id: wifiChoiceMouse
                                                    anchors.fill: parent
                                                    z: -1
                                                    hoverEnabled: true
                                                    cursorShape: Qt.PointingHandCursor
                                                    onClicked: root.activateWifi(wifiRow.modelData)
                                                }
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

                                Text {
                                    width: parent.width
                                    visible: root.wifiError !== ""
                                    text: "󰀦  " + root.wifiError
                                    elide: Text.ElideRight
                                    color: root.colDanger
                                    font { family: root.fontFamily; pixelSize: 8; bold: true }
                                }

                                Rectangle {
                                    width: parent.width; height: 38; radius: 9
                                    color: wifiSettingsMouse.containsMouse ? "#24FFFFFF" : "#10FFFFFF"; border.width: 1; border.color: "#18FFFFFF"
                                    Behavior on color { ColorAnimation { duration: 140 } }
                                    Text { anchors.centerIn: parent; text: "󰒓  Advanced network settings"; color: root.colMuted; font { family: root.fontFamily; pixelSize: 9; bold: true } }
                                    MouseArea { id: wifiSettingsMouse; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: root.openWifiManager() }
                                }
                            }

                            // ── Wi-Fi passphrase ────────────────────────────
                            Column {
                                width: parent.width
                                spacing: 9
                                visible: root.subPanel === "wifiPassword"

                                Text {
                                    width: parent.width
                                    text: "Password for "
                                        + (root.pendingWifiNetwork ? root.pendingWifiNetwork.name : "")
                                    elide: Text.ElideRight
                                    color: root.colFg
                                    font { family: root.fontFamily; pixelSize: 10; bold: true }
                                }
                                Rectangle {
                                    width: parent.width; height: 38; radius: 9
                                    color: "#18FFFFFF"; border.width: 1
                                    border.color: wifiPasswordInput.activeFocus ? "#66FFFFFF" : "#25FFFFFF"
                                    Behavior on border.color { ColorAnimation { duration: 180 } }
                                    TextInput {
                                        id: wifiPasswordInput
                                        anchors.fill: parent; anchors.leftMargin: 11; anchors.rightMargin: 40
                                        verticalAlignment: TextInput.AlignVCenter
                                        echoMode: wifiPasswordReveal.showing ? TextInput.Normal : TextInput.Password
                                        passwordCharacter: "•"
                                        color: root.colActive
                                        selectionColor: "#55FFFFFF"
                                        clip: true
                                        font { family: root.fontFamily; pixelSize: 10 }
                                        Keys.onReturnPressed: root.submitWifiPassword()
                                        Keys.onEnterPressed: root.submitWifiPassword()
                                        Keys.onEscapePressed: root.subPanel = "wifi"
                                    }
                                    Text {
                                        anchors.left: parent.left; anchors.leftMargin: 11; anchors.verticalCenter: parent.verticalCenter
                                        visible: wifiPasswordInput.text === "" && !wifiPasswordInput.activeFocus
                                        text: "Enter network password"
                                        color: root.colMuted
                                        font { family: root.fontFamily; pixelSize: 9 }
                                    }
                                    // Typing a long passphrase blind is how wrong
                                    // passwords happen in the first place.
                                    Rectangle {
                                        id: wifiPasswordReveal
                                        property bool showing: false
                                        anchors.right: parent.right; anchors.rightMargin: 6
                                        anchors.verticalCenter: parent.verticalCenter
                                        width: 26; height: 26; radius: 7
                                        color: wifiRevealMouse.containsMouse ? "#28FFFFFF" : "transparent"
                                        Behavior on color { ColorAnimation { duration: 140 } }
                                        Text {
                                            anchors.centerIn: parent
                                            text: wifiPasswordReveal.showing ? "󰈉" : "󰈈"
                                            color: wifiRevealMouse.containsMouse ? root.colActive : root.colMuted
                                            font { family: root.fontFamily; pixelSize: 12 }
                                        }
                                        MouseArea {
                                            id: wifiRevealMouse
                                            anchors.fill: parent
                                            hoverEnabled: true
                                            cursorShape: Qt.PointingHandCursor
                                            onClicked: wifiPasswordReveal.showing = !wifiPasswordReveal.showing
                                        }
                                    }
                                    MouseArea { anchors.fill: parent; z: -1; onClicked: wifiPasswordInput.forceActiveFocus() }
                                }
                                Text {
                                    width: parent.width
                                    visible: root.wifiError !== ""
                                    text: "󰀦  " + root.wifiError
                                    wrapMode: Text.Wrap
                                    color: root.colDanger
                                    font { family: root.fontFamily; pixelSize: 8; bold: true }
                                }
                                Row {
                                    width: parent.width
                                    spacing: 6
                                    Rectangle {
                                        width: (parent.width - 6) / 2; height: 36; radius: 9
                                        color: wifiCancelMouse.containsMouse ? "#24FFFFFF" : "#12FFFFFF"
                                        border.width: 1; border.color: "#25FFFFFF"
                                        Behavior on color { ColorAnimation { duration: 140 } }
                                        Text { anchors.centerIn: parent; text: "Cancel"; color: root.colMuted; font { family: root.fontFamily; pixelSize: 9; bold: true } }
                                        MouseArea { id: wifiCancelMouse; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: root.subPanel = "wifi" }
                                    }
                                    Rectangle {
                                        width: (parent.width - 6) / 2; height: 36; radius: 9
                                        opacity: wifiPasswordInput.text === "" ? 0.45 : 1
                                        color: wifiConnectMouse.containsMouse ? "#35FFFFFF" : "#24FFFFFF"
                                        border.width: 1; border.color: "#45FFFFFF"
                                        Behavior on color { ColorAnimation { duration: 140 } }
                                        Behavior on opacity { NumberAnimation { duration: 160 } }
                                        Text { anchors.centerIn: parent; text: "Connect"; color: root.colActive; font { family: root.fontFamily; pixelSize: 9; bold: true } }
                                        MouseArea { id: wifiConnectMouse; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: root.submitWifiPassword() }
                                    }
                                }
                            }

                            // ── Bluetooth ───────────────────────────────────
                            Column {
                                width: parent.width
                                spacing: 6
                                visible: root.subPanel === "bluetooth"

                                Rectangle {
                                    width: parent.width; height: 48; radius: 9
                                    color: btRadioMouse.containsMouse ? "#2CFFFFFF" : (root.btOn ? "#20FFFFFF" : "#10FFFFFF")
                                    border.width: 1; border.color: root.btOn ? "#40FFFFFF" : "#18FFFFFF"
                                    opacity: root.btAvailable ? 1 : 0.5
                                    Behavior on color { ColorAnimation { duration: 140 } }
                                    Text { anchors.left: parent.left; anchors.leftMargin: 12; anchors.verticalCenter: parent.verticalCenter; text: root.btOn ? "󰂯" : "󰂲"; color: root.btOn ? root.colActive : root.colMuted; font { family: root.fontFamily; pixelSize: 15 } }
                                    Column {
                                        anchors.left: parent.left; anchors.leftMargin: 42; anchors.verticalCenter: parent.verticalCenter; spacing: 2
                                        Text { text: "Bluetooth"; color: root.colFg; font { family: root.fontFamily; pixelSize: 10; bold: true } }
                                        Text {
                                            text: !root.btAvailable
                                                ? "No adapter found"
                                                : (root.btOn
                                                    ? (root.btConnectedCount > 0 ? root.btConnectedCount + " connected" : "On · no devices connected")
                                                    : "Off")
                                            color: root.colMuted
                                            font { family: root.fontFamily; pixelSize: 8 }
                                        }
                                    }
                                    Rectangle {
                                        anchors.right: parent.right; anchors.rightMargin: 12; anchors.verticalCenter: parent.verticalCenter
                                        width: 34; height: 18; radius: 9
                                        color: root.btOn ? "#66FFFFFF" : "#28FFFFFF"
                                        Behavior on color { ColorAnimation { duration: 180 } }
                                        Rectangle {
                                            y: 3; width: 12; height: 12; radius: 6
                                            x: root.btOn ? 19 : 3
                                            color: root.btOn ? "#1E1D1E" : root.colMuted
                                            Behavior on x { NumberAnimation { duration: 260; easing.type: Easing.OutBack; easing.overshoot: 2.2 } }
                                            Behavior on color { ColorAnimation { duration: 180 } }
                                        }
                                    }
                                    MouseArea { id: btRadioMouse; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; enabled: root.btAvailable; onClicked: root.toggleBluetooth() }
                                }

                                Flickable {
                                    width: parent.width
                                    height: root.listHeight(root.btDevices.length, 54, 6, 5)
                                    contentWidth: width
                                    contentHeight: btDeviceColumn.implicitHeight
                                    clip: true
                                    boundsBehavior: Flickable.StopAtBounds
                                    flickableDirection: Flickable.VerticalFlick

                                    Behavior on height {
                                        NumberAnimation { duration: 260; easing.type: Easing.OutQuint }
                                    }

                                    Column {
                                        id: btDeviceColumn
                                        width: parent.width
                                        spacing: 6

                                        Text {
                                            width: parent.width; height: 54
                                            visible: root.btDevices.length === 0
                                            verticalAlignment: Text.AlignVCenter
                                            horizontalAlignment: Text.AlignHCenter
                                            text: root.btOn ? "Searching for devices…" : "Bluetooth is off"
                                            color: root.colMuted
                                            font { family: root.fontFamily; pixelSize: 9 }
                                        }

                                        Repeater {
                                            model: root.btDevices
                                            Rectangle {
                                                id: btRow
                                                required property var modelData
                                                width: btDeviceColumn.width; height: 54; radius: 9
                                                color: modelData.connected ? "#30FFFFFF" : (btChoiceMouse.containsMouse ? "#24FFFFFF" : "#10FFFFFF")
                                                border.width: 1; border.color: modelData.connected ? "#55FFFFFF" : "#18FFFFFF"
                                                Behavior on color { ColorAnimation { duration: 140 } }

                                                Text {
                                                    anchors.left: parent.left; anchors.leftMargin: 12
                                                    anchors.verticalCenter: parent.verticalCenter
                                                    text: root.btGlyph(btRow.modelData)
                                                    color: btRow.modelData.connected ? root.colActive : root.colMuted
                                                    font { family: root.fontFamily; pixelSize: 15 }
                                                    // A slow spin while the stack is
                                                    // mid-handshake; BlueZ pairing can
                                                    // take several seconds.
                                                    RotationAnimation on rotation {
                                                        running: btRow.modelData.pairing
                                                        from: 0; to: 360; duration: 1400
                                                        loops: Animation.Infinite
                                                        alwaysRunToEnd: true
                                                    }
                                                }
                                                Column {
                                                    anchors.left: parent.left; anchors.leftMargin: 42
                                                    anchors.right: btRowRight.left; anchors.rightMargin: 8
                                                    anchors.verticalCenter: parent.verticalCenter
                                                    spacing: 2
                                                    Text {
                                                        width: parent.width
                                                        text: btRow.modelData.name
                                                        elide: Text.ElideRight
                                                        color: root.colFg
                                                        font { family: root.fontFamily; pixelSize: 10; bold: true }
                                                    }
                                                    Text {
                                                        width: parent.width
                                                        text: root.btStatusText(btRow.modelData)
                                                        elide: Text.ElideRight
                                                        color: root.colMuted
                                                        font { family: root.fontFamily; pixelSize: 8 }
                                                    }
                                                }
                                                Row {
                                                    id: btRowRight
                                                    anchors.right: parent.right; anchors.rightMargin: 10
                                                    anchors.verticalCenter: parent.verticalCenter
                                                    spacing: 6
                                                    Text {
                                                        anchors.verticalCenter: parent.verticalCenter
                                                        text: btRow.modelData.connected ? "󰄬" : "󰅂"
                                                        color: btRow.modelData.connected ? root.colActive : root.colMuted
                                                        font { family: root.fontFamily; pixelSize: 12 }
                                                    }
                                                    Rectangle {
                                                        anchors.verticalCenter: parent.verticalCenter
                                                        visible: btRow.modelData.paired || btRow.modelData.bonded
                                                        width: 24; height: 24; radius: 7
                                                        color: btForgetMouse.containsMouse ? "#30FF6B6B" : "transparent"
                                                        Behavior on color { ColorAnimation { duration: 140 } }
                                                        Text {
                                                            anchors.centerIn: parent
                                                            text: "󰆴"
                                                            color: btForgetMouse.containsMouse ? root.colDanger : root.colMuted
                                                            font { family: root.fontFamily; pixelSize: 11 }
                                                        }
                                                        MouseArea {
                                                            id: btForgetMouse
                                                            anchors.fill: parent
                                                            hoverEnabled: true
                                                            cursorShape: Qt.PointingHandCursor
                                                            onClicked: mouse => { mouse.accepted = true; root.btForget(btRow.modelData); }
                                                        }
                                                    }
                                                }
                                                MouseArea {
                                                    id: btChoiceMouse
                                                    anchors.fill: parent
                                                    z: -1
                                                    hoverEnabled: true
                                                    cursorShape: Qt.PointingHandCursor
                                                    onClicked: root.btDeviceAction(btRow.modelData)
                                                }
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

                                Text {
                                    width: parent.width
                                    visible: root.btError !== ""
                                    text: "󰀦  " + root.btError
                                    elide: Text.ElideRight
                                    color: root.colDanger
                                    font { family: root.fontFamily; pixelSize: 8; bold: true }
                                }

                                Text {
                                    width: parent.width
                                    visible: root.btOn
                                    horizontalAlignment: Text.AlignHCenter
                                    text: "Put a device in pairing mode for it to appear here"
                                    color: root.colMuted
                                    font { family: root.fontFamily; pixelSize: 8 }
                                }
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

            Timer { interval: 1500; running: true; repeat: true; onTriggered: { mediaPollProc.running = true; mediaPositionProc.running = root.mediaService !== ""; mediaLengthProc.running = root.mediaService !== ""; recordingPollProc.running = true; micPollProc.running = true; } }
            Timer { interval: 5000; running: true; repeat: true; onTriggered: { gpuPollProc.running = true; batteryPollProc.running = true; mediaListProc.running = true; } }
            Timer { interval: 1000; running: root.isRecording; repeat: true; onTriggered: root.recordSeconds++ }
            Timer { id: recordRefreshTimer; interval: 500; repeat: false; onTriggered: recordingPollProc.running = true }
            Timer { id: mediaPositionRefresh; interval: 500; repeat: false; onTriggered: mediaPositionProc.running = true }

            // Scanning is expensive and NetworkManager rate-limits it, so the
            // Wi-Fi scanner only runs while its panel is actually on screen —
            // which is also what keeps the list fresh, the thing the old
            // `--rescan no` pipeline never did.
            Binding {
                target: root.wifiDevice
                property: "scannerEnabled"
                value: root.commandCenterOpen
                    && (root.subPanel === "wifi" || root.subPanel === "wifiPassword")
                when: root.wifiDevice !== null
                restoreMode: Binding.RestoreBindingOrValue
            }

            // Likewise discovery: leaving it on drains batteries on both ends.
            Binding {
                target: root.btAdapter
                property: "discovering"
                value: root.commandCenterOpen && root.subPanel === "bluetooth"
                when: root.btAdapter !== null && root.btOn
                restoreMode: Binding.RestoreBindingOrValue
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

            // Animation drivers.
            //
            // Each popup is driven by a single 0..1 progress value instead of a
            // Behavior per property, so its geometry can never desync halfway
            // through a morph. `*Progress` carries the springy curve and is
            // allowed to overshoot past 1; `*Content` is a plain linear ramp
            // used only to stagger the reveal of the rows inside, because the
            // springy curve is far too front-loaded to stagger against (it is
            // already at 65% after a fifth of its duration).
            property real ccProgress: 0
            property real ccContent: 0
            property real powerProgress: 0
            property real powerContent: 0

            function clamp01(v) { return v < 0 ? 0 : (v > 1 ? 1 : v); }
            function outCubic(v) { let t = root.clamp01(v); return 1 - Math.pow(1 - t, 3); }

            // Row `order` starts moving a beat after the row before it. The
            // leading offset holds the whole cascade back until the card has
            // actually reached full width — OutBack crosses 1.0 at 43% of its
            // duration — so no row is ever revealed while the clip rectangle is
            // still narrow enough to cut it off at the sides.
            function ccReveal(order) { return root.outCubic((root.ccContent - 0.34 - order * 0.05) / 0.33); }
            function powerReveal(order) { return root.outCubic((root.powerContent - 0.34 - order * 0.075) / 0.4); }

            // Restarting from the changed handler (rather than binding the
            // progress and leaning on a Behavior) guarantees `to`, `duration`
            // and `easing` are re-read after the open flag has already flipped.
            onCommandCenterOpenChanged: ccAnim.restart()
            onPowerOpenChanged: powerAnim.restart()

            ParallelAnimation {
                id: ccAnim
                NumberAnimation {
                    target: root
                    property: "ccProgress"
                    to: root.commandCenterOpen ? 1 : 0
                    duration: root.commandCenterOpen ? 470 : 250
                    easing.type: root.commandCenterOpen ? Easing.OutBack : Easing.InCubic
                    easing.overshoot: 1.35
                }
                NumberAnimation {
                    target: root
                    property: "ccContent"
                    to: root.commandCenterOpen ? 1 : 0
                    duration: root.commandCenterOpen ? 560 : 140
                    easing.type: Easing.Linear
                }
            }

            ParallelAnimation {
                id: powerAnim
                NumberAnimation {
                    target: root
                    property: "powerProgress"
                    to: root.powerOpen ? 1 : 0
                    duration: root.powerOpen ? 430 : 220
                    easing.type: root.powerOpen ? Easing.OutBack : Easing.InCubic
                    easing.overshoot: 1.8
                }
                NumberAnimation {
                    target: root
                    property: "powerContent"
                    to: root.powerOpen ? 1 : 0
                    duration: root.powerOpen ? 480 : 130
                    easing.type: Easing.Linear
                }
            }

            // Cross-fade between the Command Centre body and a sub-panel
            // (media picker / Wi-Fi list) without either one being clickable
            // while it is faded out.
            property real selProgress: root.subPanelOpen ? 1 : 0
            Behavior on selProgress {
                NumberAnimation { duration: 230; easing.type: Easing.OutCubic }
            }

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
                    root.subPanel = "";
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
                                    height: wsItem.isActive ? 9 : 8
                                    radius: height / 2
                                    width: wsItem.isActive ? 28 : (wsItem.isOccupied ? 12 : 8)

                                    color: wsItem.isActive
                                        ? root.colActive
                                        : (wsItem.isHovered
                                            ? "#FFFFFF"
                                            : (wsItem.isOccupied ? root.colOccupied : root.colInactive))

                                    // Hover scale has to be state-dependent. A flat
                                    // multiplier reads fine on an 8px dot but
                                    // compounds with the active pill's own 28px
                                    // width, so clicking a workspace with the mouse
                                    // left you hovering a pill that had ballooned in
                                    // both directions at once.
                                    scale: mouseArea.pressed
                                        ? 0.82
                                        : (wsItem.isHovered ? (wsItem.isActive ? 1.06 : 1.25) : 1)

                                    // The pill's own width drives `wsItem.width`, so
                                    // overshooting here rubber-bands the whole row.
                                    Behavior on width {
                                        NumberAnimation {
                                            duration: 420
                                            easing.type: Easing.OutBack
                                            easing.overshoot: 2.0
                                        }
                                    }

                                    Behavior on height {
                                        NumberAnimation {
                                            duration: 320
                                            easing.type: Easing.OutBack
                                            easing.overshoot: 2.4
                                        }
                                    }

                                    Behavior on scale {
                                        NumberAnimation {
                                            duration: 280
                                            easing.type: Easing.OutBack
                                            easing.overshoot: 2.4
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

                    // Physical press feedback. The Command Centre grows from this
                    // island's `width`/`height`, which `scale` does not touch, so
                    // the two never fight over the morph's starting geometry.
                    scale: timeMouse.pressed ? 0.955 : 1

                    Behavior on scale {
                        NumberAnimation { duration: 260; easing.type: Easing.OutBack; easing.overshoot: 2.6 }
                    }

                    Behavior on width {
                        NumberAnimation { duration: 300; easing.type: Easing.OutQuint }
                    }

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
                                root.subPanel = "";
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
                            scale: volMouse.pressed ? 0.84 : (volMouse.containsMouse ? 1.18 : 1)

                            Behavior on scale {
                                NumberAnimation { duration: 240; easing.type: Easing.OutBack; easing.overshoot: 2.8 }
                            }
                            Behavior on color {
                                ColorAnimation { duration: 150 }
                            }

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
                            scale: kbMouse.pressed ? 0.84 : (kbMouse.containsMouse ? 1.18 : 1)

                            Behavior on scale {
                                NumberAnimation { duration: 240; easing.type: Easing.OutBack; easing.overshoot: 2.8 }
                            }
                            Behavior on color {
                                ColorAnimation { duration: 150 }
                            }

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
                            scale: netMouse.pressed ? 0.84 : (netMouse.containsMouse ? 1.18 : 1)

                            Behavior on scale {
                                NumberAnimation { duration: 240; easing.type: Easing.OutBack; easing.overshoot: 2.8 }
                            }
                            Behavior on color {
                                ColorAnimation { duration: 150 }
                            }

                            MouseArea {
                                id: netMouse
                                anchors.fill: parent
                                anchors.margins: -6
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: {
                                    // Straight to the network list rather than the
                                    // Command Centre's front page — it is the only
                                    // reason to click a network icon.
                                    root.commandCenterOpen = true;
                                    root.subPanel = "wifi";
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
                            scale: powerMouse.pressed ? 0.84 : (powerMouse.containsMouse ? 1.18 : 1)
                            rotation: root.powerOpen ? 180 : 0

                            Behavior on scale {
                                NumberAnimation { duration: 240; easing.type: Easing.OutBack; easing.overshoot: 2.8 }
                            }

                            Behavior on rotation {
                                NumberAnimation { duration: 420; easing.type: Easing.OutBack; easing.overshoot: 2.2 }
                            }

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

                // Soft lift under the Command Centre. Drawn as a sibling rather
                // than a layer effect so the blur is free to bleed outside the
                // card's own bounds.
                RectangularShadow {
                    z: 4
                    anchors.fill: commandCenterCard
                    radius: commandCenterCard.radius
                    blur: 40
                    spread: 3
                    offset.y: 12
                    color: "#96000000"
                    opacity: commandCenterCard.pc
                    visible: commandCenterCard.visible
                }

                // Command Centre — monochrome glass, matching Hyprland itself.
                //
                // It grows out of the clock island rather than fading in on top
                // of it: at progress 0 the card has exactly the island's size,
                // position and corner radius, so it is completely hidden behind
                // it (the island is opaque and painted at a higher z). Every
                // frame after that is the same rectangle stretching downward.
                Rectangle {
                    id: commandCenterCard
                    z: 6

                    readonly property real openWidth: 410
                    // The natural open height, kept on its own timeline so that
                    // opening a sub-panel resizes the card without fighting the
                    // open/close morph for control of `height`.
                    property real openHeight: root.subPanelOpen
                        ? selectorOverlay.naturalHeight + 20
                        : 524
                    Behavior on openHeight {
                        NumberAnimation { duration: 340; easing.type: Easing.OutQuint }
                    }

                    readonly property real p: root.ccProgress
                    readonly property real pc: root.clamp01(root.ccProgress)

                    anchors.horizontalCenter: parent.horizontalCenter
                    y: 46 * Math.max(0, p)
                    width: timeIsland.width + (openWidth - timeIsland.width) * p
                    height: Math.max(0, timeIsland.height + (openHeight - timeIsland.height) * p)
                    radius: root.panelRadius + 4 * pc
                    color: "#E61E1D1E"
                    border.width: 1
                    border.color: "#55FFFFFF"
                    visible: p > 0.001
                    clip: true

                    Rectangle {
                        anchors.fill: parent
                        anchors.margins: 1
                        radius: commandCenterCard.radius - 1
                        color: "transparent"
                        border.width: 1
                        border.color: "#12FFFFFF"
                    }

                    Column {
                        // Laid out at the card's final width so the rows do not
                        // reflow while the card is still growing, and centred
                        // rather than pinned to the left inset: the card is
                        // itself centred, so this keeps the content at a fixed
                        // position on screen instead of dragging sideways as the
                        // card's left edge sweeps outwards.
                        anchors.horizontalCenter: parent.horizontalCenter
                        y: 12
                        width: commandCenterCard.openWidth - 24
                        spacing: 8
                        opacity: 1 - root.selProgress
                        scale: 1 - 0.05 * root.selProgress
                        transformOrigin: Item.Top
                        visible: opacity > 0.01

                        Item {
                            width: parent.width
                            height: 42
                            opacity: root.ccReveal(0)
                            transform: Translate { y: (1 - root.ccReveal(0)) * 26 }

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
                            opacity: root.ccReveal(1)
                            transform: Translate { y: (1 - root.ccReveal(1)) * 26 }

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
                                MouseArea { id: mediaSourceMouse; anchors.fill: parent; anchors.margins: -6; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: { root.subPanel = root.subPanel === "media" ? "" : "media"; mediaListProc.running = true; } }
                            }
                            Text { z: 2; anchors.left: parent.left; anchors.leftMargin: 13; anchors.right: mediaControls.left; anchors.rightMargin: 10; anchors.top: parent.top; anchors.topMargin: 31; text: root.mediaTitle; elide: Text.ElideRight; color: root.colActive; font { family: root.fontFamily; pixelSize: 12; bold: true } }
                            Text { z: 2; anchors.left: parent.left; anchors.leftMargin: 13; anchors.right: mediaControls.left; anchors.rightMargin: 10; anchors.top: parent.top; anchors.topMargin: 51; text: root.mediaArtist; elide: Text.ElideRight; color: root.colFg; font { family: root.fontFamily; pixelSize: 9 } }
                            Row {
                                id: mediaControls; z: 2; anchors.right: parent.right; anchors.rightMargin: 12; anchors.verticalCenter: parent.verticalCenter; spacing: 5
                                Repeater { model: [{ icon: "󰒮", action: "previous" }, { icon: root.mediaStatus === "Playing" ? "󰏤" : "󰐊", action: "play-pause" }, { icon: "󰒭", action: "next" }]; Rectangle { required property var modelData; width: modelData.action === "play-pause" ? 38 : 30; height: 34; radius: 9; color: mediaButton.containsMouse ? "#30FFFFFF" : "#12FFFFFF"; scale: mediaButton.pressed ? 0.86 : (mediaButton.containsMouse ? 1.13 : 1); Behavior on scale { NumberAnimation { duration: 220; easing.type: Easing.OutBack; easing.overshoot: 3.2 } } Behavior on color { ColorAnimation { duration: 140 } } Text { anchors.centerIn: parent; text: modelData.icon; color: root.colFg; font { family: root.fontFamily; pixelSize: modelData.action === "play-pause" ? 17 : 13 } } MouseArea { id: mediaButton; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: root.mediaAction(modelData.action) } } }
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
                            opacity: root.ccReveal(2)
                            transform: Translate { y: (1 - root.ccReveal(2)) * 26 }
                            Repeater { model: [
                                { icon: root.wifiOn ? root.netIcon : "󰤭", title: "Wi-Fi", value: root.wifiOn ? root.netType : "Off", type: "wifi", active: root.wifiOn },
                                { icon: root.micMuted ? "󰍭" : "󰍬", title: "Microphone", value: root.micMuted ? "Muted" : root.micPercent + "%", type: "mic", active: !root.micMuted },
                                { icon: root.btOn ? "󰂯" : "󰂲", title: "Bluetooth", value: !root.btAvailable ? "No adapter" : (root.btOn ? (root.btConnectedCount > 0 ? root.btConnectedCount + " connected" : "On") : "Off"), type: "bluetooth", active: root.btOn },
                                { icon: "󰌌", title: "Layout", value: root.kbLayout, type: "lang", active: true }
                            ]; Rectangle { required property var modelData; width: (parent.width - 6) / 2; height: 54; radius: 10; color: toggleMouse.containsMouse ? "#30FFFFFF" : (modelData.active ? "#20FFFFFF" : "#10FFFFFF"); border.width: 1; border.color: modelData.active ? "#30FFFFFF" : "#18FFFFFF"; scale: toggleMouse.pressed ? 0.94 : (toggleMouse.containsMouse ? 1.035 : 1); Behavior on scale { NumberAnimation { duration: 230; easing.type: Easing.OutBack; easing.overshoot: 2.8 } } Behavior on color { ColorAnimation { duration: 150 } } Text { anchors.left: parent.left; anchors.leftMargin: 11; anchors.verticalCenter: parent.verticalCenter; text: modelData.icon; color: modelData.active ? root.colActive : root.colMuted; font { family: root.fontFamily; pixelSize: 16 } } Column { anchors.left: parent.left; anchors.leftMargin: 42; anchors.verticalCenter: parent.verticalCenter; spacing: 2; Text { text: modelData.title; color: root.colFg; font { family: root.fontFamily; pixelSize: 10; bold: true } } Text { text: modelData.value; color: root.colMuted; font { family: root.fontFamily; pixelSize: 8 } } } MouseArea { id: toggleMouse; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: { if (modelData.type === "lang") root.switchLayout(); else if (modelData.type === "mic") root.toggleMic(); else if (modelData.type === "wifi") root.subPanel = root.subPanel === "wifi" ? "" : "wifi"; else root.subPanel = root.subPanel === "bluetooth" ? "" : "bluetooth"; } } } }
                        }

                        Rectangle {
                            width: parent.width; height: 48; radius: 10; color: "#18FFFFFF"; border.width: 1; border.color: "#20FFFFFF"
                            opacity: root.ccReveal(3)
                            transform: Translate { y: (1 - root.ccReveal(3)) * 26 }
                            Text { anchors.left: parent.left; anchors.leftMargin: 12; anchors.verticalCenter: parent.verticalCenter; text: root.volIcon; color: root.isMuted ? root.colMuted : root.colActive; font { family: root.fontFamily; pixelSize: 15 } }
                            Rectangle { id: monoVolumeTrack; anchors.left: parent.left; anchors.leftMargin: 42; anchors.right: parent.right; anchors.rightMargin: 52; anchors.verticalCenter: parent.verticalCenter; height: 6; radius: 3; color: "#30FFFFFF"; Rectangle { height: parent.height; radius: 3; width: parent.width * root.volPercent / 100; color: root.isMuted ? root.colMuted : root.colActive; Behavior on width { NumberAnimation { duration: 80 } } } }
                            Text { anchors.right: parent.right; anchors.rightMargin: 12; anchors.verticalCenter: parent.verticalCenter; text: root.volPercent + "%"; color: root.colMuted; font { family: root.fontFamily; pixelSize: 9; bold: true } }
                            MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: mouse => root.setVolume(Math.round(Math.max(0, Math.min(1, (mouse.x - 42) / (width - 94))) * 100)); onPositionChanged: mouse => { if (pressed) root.setVolume(Math.round(Math.max(0, Math.min(1, (mouse.x - 42) / (width - 94))) * 100)); } onWheel: wheel => root.setVolume(root.volPercent + (wheel.angleDelta.y > 0 ? 5 : -5)) }
                        }

                        Row {
                            width: parent.width; height: 44; spacing: 5
                            opacity: root.ccReveal(4)
                            transform: Translate { y: (1 - root.ccReveal(4)) * 26 }
                            Repeater { model: [{ label: "CPU", value: root.cpuPercent + "%" }, { label: "RAM", value: root.ramPercent + "%" }, { label: "GPU", value: root.gpuPercent + "%" }, { label: root.batteryPercent >= 0 ? "BAT" : "TEMP", value: root.batteryPercent >= 0 ? root.batteryPercent + "%" : root.cpuTemp + "°C" }]; Rectangle { required property var modelData; width: (parent.width - 15) / 4; height: parent.height; radius: 10; color: metricMouse.containsMouse ? "#25FFFFFF" : "#12FFFFFF"; border.width: 1; border.color: "#18FFFFFF"; scale: metricMouse.pressed ? 0.92 : (metricMouse.containsMouse ? 1.05 : 1); Behavior on scale { NumberAnimation { duration: 230; easing.type: Easing.OutBack; easing.overshoot: 2.8 } } Behavior on color { ColorAnimation { duration: 150 } } Column { anchors.centerIn: parent; spacing: 3; Text { anchors.horizontalCenter: parent.horizontalCenter; text: modelData.value; color: root.colFg; font { family: root.fontFamily; pixelSize: 10; bold: true } } Text { anchors.horizontalCenter: parent.horizontalCenter; text: modelData.label; color: root.colMuted; font { family: root.fontFamily; pixelSize: 7; bold: true } } } MouseArea { id: metricMouse; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: root.openBtop() } } }
                        }

                        Row {
                            width: parent.width; height: 32; spacing: 5
                            opacity: root.ccReveal(5)
                            transform: Translate { y: (1 - root.ccReveal(5)) * 26 }
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
                            opacity: root.ccReveal(6)
                            transform: Translate { y: (1 - root.ccReveal(6)) * 26 }

                            Repeater { model: [{ label: "Snip", icon: "󰄀", command: "snip" }, { label: root.isRecording ? root.formatMediaTime(root.recordSeconds) : "Record", icon: root.isRecording ? "󰻃" : "󰑊", command: "record" }, { label: root.isMuted ? "Unmute" : "Mute", icon: root.volIcon, command: "mute" }, { label: "Lock", icon: "󰌾", command: "lock" }]; Rectangle { required property var modelData; width: (parent.width - 15) / 4; height: parent.height; radius: 10; color: modelData.command === "record" && root.isRecording ? "#38C74028" : (quickActionMouse.containsMouse ? "#30FFFFFF" : "#18FFFFFF"); border.width: 1; border.color: modelData.command === "record" && root.isRecording ? "#88C74028" : "#20FFFFFF"; scale: quickActionMouse.pressed ? 0.92 : (quickActionMouse.containsMouse ? 1.05 : 1); Behavior on scale { NumberAnimation { duration: 230; easing.type: Easing.OutBack; easing.overshoot: 2.8 } } Behavior on color { ColorAnimation { duration: 150 } } Column { anchors.centerIn: parent; spacing: 3; Text { anchors.horizontalCenter: parent.horizontalCenter; text: modelData.icon; color: modelData.command === "record" && root.isRecording ? "#FF8A78" : root.colFg; font { family: root.fontFamily; pixelSize: 14 } } Text { anchors.horizontalCenter: parent.horizontalCenter; text: modelData.label; color: root.colMuted; font { family: root.fontFamily; pixelSize: 8; bold: true } } } MouseArea { id: quickActionMouse; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: { if (modelData.command === "record") root.toggleRecording(); else if (modelData.command === "mute") root.toggleMute(); else if (modelData.command === "lock") { root.commandCenterOpen = false; Quickshell.execDetached(["hyprlock"]); } else { root.commandCenterOpen = false; Quickshell.execDetached(["sh", "-c", "mkdir -p ~/Pictures/Screenshots && file=~/Pictures/Screenshots/screenshot_$(date +%Y%m%d_%H%M%S).png; grim -g \"$(slurp)\" \"$file\" && wl-copy < \"$file\""]); } } } } }
                        }
                    }
                }

                RectangularShadow {
                    z: 4
                    anchors.fill: controlCenterCard
                    radius: controlCenterCard.radius
                    blur: 30
                    spread: 2
                    offset.y: 9
                    color: "#8C000000"
                    opacity: controlCenterCard.pc
                    visible: controlCenterCard.visible
                }

                // 5. Випливаючий Power Control Center справа.
                // Same trick as the Command Centre, anchored to the power button
                // instead: at progress 0 it is a 30x30 square sitting exactly on
                // the 󰐥 glyph, hidden behind the opaque right-hand island.
                Rectangle {
                    id: controlCenterCard
                    z: 5

                    readonly property real p: root.powerProgress
                    readonly property real pc: root.clamp01(root.powerProgress)

                    anchors.right: parent.right
                    anchors.rightMargin: 14 * (1 - pc)
                    y: 2 + 42 * Math.max(0, p)
                    width: 30 + 134 * p
                    height: 30 + 134 * p
                    color: root.colBg
                    radius: 8 + 4 * pc
                    border.width: 1
                    border.color: root.colBorder
                    visible: p > 0.001
                    clip: true

                    Grid {
                        id: grid
                        // Pinned to the right inset, the edge the card grows out
                        // of: that edge barely moves, so the tiles stay put while
                        // the card expands leftwards instead of sliding with it.
                        anchors.right: parent.right
                        anchors.rightMargin: 8
                        y: 8
                        width: 148
                        columns: 2
                        spacing: 6

                        // 1. Lock Screen
                        Rectangle {
                            width: 71
                            height: 71
                            radius: 8
                            color: lockMouse.containsMouse ? root.colCardHover : root.colCard
                            opacity: root.powerReveal(0)
                            scale: 0.72 + 0.28 * root.powerReveal(0)

                            Behavior on color {
                                ColorAnimation { duration: 150 }
                            }

                            Column {
                                anchors.centerIn: parent
                                spacing: 4
                                scale: lockMouse.containsMouse ? 1.1 : 1
                                Behavior on scale {
                                    NumberAnimation { duration: 240; easing.type: Easing.OutBack; easing.overshoot: 2.6 }
                                }

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
                            opacity: root.powerReveal(1)
                            scale: 0.72 + 0.28 * root.powerReveal(1)

                            Behavior on color {
                                ColorAnimation { duration: 150 }
                            }

                            Column {
                                anchors.centerIn: parent
                                spacing: 4
                                scale: logoutMouse.containsMouse ? 1.1 : 1
                                Behavior on scale {
                                    NumberAnimation { duration: 240; easing.type: Easing.OutBack; easing.overshoot: 2.6 }
                                }

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
                            opacity: root.powerReveal(1)
                            scale: 0.72 + 0.28 * root.powerReveal(1)

                            Behavior on color {
                                ColorAnimation { duration: 150 }
                            }

                            Column {
                                anchors.centerIn: parent
                                spacing: 4
                                scale: rebootMouse.containsMouse ? 1.1 : 1
                                Behavior on scale {
                                    NumberAnimation { duration: 240; easing.type: Easing.OutBack; easing.overshoot: 2.6 }
                                }

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
                            opacity: root.powerReveal(2)
                            scale: 0.72 + 0.28 * root.powerReveal(2)

                            Behavior on color {
                                ColorAnimation { duration: 150 }
                            }

                            Column {
                                anchors.centerIn: parent
                                spacing: 4
                                scale: shutdownMouse.containsMouse ? 1.1 : 1
                                Behavior on scale {
                                    NumberAnimation { duration: 240; easing.type: Easing.OutBack; easing.overshoot: 2.6 }
                                }

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

            // Only `y` is animated here: each card drives its own x/opacity/scale
            // entrance and exit, so listing "x" would have the positioner and the
            // card fighting over the same property.
            move: Transition {
                NumberAnimation { properties: "y"; duration: 340; easing.type: Easing.OutQuint }
            }

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
                        enterAnim.stop();
                        lifeAnim.stop();
                        exitAnim.start();
                    }

                    width: notificationColumn.width
                    height: 78
                    radius: 10
                    color: "#F01E1D1E"
                    border.width: 1
                    border.color: modelData.urgency === NotificationUrgency.Critical ? "#88C74028" : "#45FFFFFF"

                    // Starting values only — every one of these is handed over to
                    // an animation, so none of them may be a live binding.
                    x: notificationColumn.width + 30
                    opacity: 0
                    scale: 0.9

                    Component.onCompleted: enterAnim.start()

                    // A negative z puts the shadow behind the card's own fill.
                    RectangularShadow {
                        anchors.fill: parent
                        z: -1
                        radius: parent.radius
                        blur: 24
                        spread: 1
                        offset.y: 7
                        color: "#7A000000"
                    }

                    ParallelAnimation {
                        id: enterAnim
                        NumberAnimation {
                            target: notificationCard; property: "x"; to: 0
                            duration: 520; easing.type: Easing.OutBack; easing.overshoot: 1.5
                        }
                        NumberAnimation {
                            target: notificationCard; property: "scale"; to: 1
                            duration: 520; easing.type: Easing.OutBack; easing.overshoot: 2.4
                        }
                        NumberAnimation {
                            target: notificationCard; property: "opacity"; to: 1
                            duration: 220; easing.type: Easing.OutQuad
                        }
                    }

                    SequentialAnimation {
                        id: exitAnim
                        ParallelAnimation {
                            NumberAnimation {
                                target: notificationCard; property: "x"
                                to: notificationColumn.width + 34
                                duration: 300; easing.type: Easing.InBack; easing.overshoot: 1.1
                            }
                            NumberAnimation {
                                target: notificationCard; property: "scale"; to: 0.88
                                duration: 300; easing.type: Easing.InQuad
                            }
                            NumberAnimation {
                                target: notificationCard; property: "opacity"; to: 0
                                duration: 260; easing.type: Easing.InQuad
                            }
                        }
                        // Handing the notification back only once the card has
                        // left the screen keeps the stack from snapping shut
                        // underneath the animation.
                        ScriptAction {
                            script: {
                                if (notificationCard.expireAfterClose) notificationCard.modelData.expire();
                                else notificationCard.modelData.dismiss();
                            }
                        }
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
                        scale: closeNotificationMouse.pressed ? 0.8 : (closeNotificationMouse.containsMouse ? 1.25 : 1)
                        Behavior on scale { NumberAnimation { duration: 220; easing.type: Easing.OutBack; easing.overshoot: 3.0 } }
                        Behavior on color { ColorAnimation { duration: 140 } }
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

                    // Time-left hairline along the bottom edge, draining on the
                    // same clock as expiryTimer.
                    Rectangle {
                        id: lifeBar
                        anchors.left: parent.left
                        anchors.bottom: parent.bottom
                        anchors.leftMargin: 2
                        anchors.bottomMargin: 2
                        height: 2
                        radius: 1
                        width: notificationCard.width - 4
                        color: notificationCard.modelData.urgency === NotificationUrgency.Critical
                            ? "#C74028"
                            : "#40FFFFFF"

                        Component.onCompleted: lifeAnim.start()

                        NumberAnimation {
                            id: lifeAnim
                            target: lifeBar
                            property: "width"
                            to: 0
                            duration: expiryTimer.interval
                            easing.type: Easing.Linear
                        }
                    }
                }
            }
        }
    }
}



