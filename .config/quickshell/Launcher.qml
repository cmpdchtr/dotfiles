import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import QtQuick

Scope {
    id: launcher

    property bool open: false
    property int selectedIndex: 0
    property var filteredApps: {
        let query = searchInput.text.trim().toLowerCase();
        let apps = DesktopEntries.applications.values.filter(app => {
            if (app.noDisplay) return false;
            if (!query) return true;
            let haystack = [app.name, app.genericName, app.comment, app.id]
                .concat(app.keywords || [])
                .join(" ").toLowerCase();
            return haystack.includes(query);
        });

        apps.sort((a, b) => {
            if (query) {
                let an = a.name.toLowerCase();
                let bn = b.name.toLowerCase();
                let aStarts = an.startsWith(query) ? 0 : 1;
                let bStarts = bn.startsWith(query) ? 0 : 1;
                if (aStarts !== bStarts) return aStarts - bStarts;
            }
            return a.name.localeCompare(b.name);
        });
        return apps;
    }

    function show() {
        launcher.open = true;
        launcher.selectedIndex = 0;
        searchInput.text = "";
        Qt.callLater(() => searchInput.forceActiveFocus());
    }

    function hide() {
        launcher.open = false;
        searchInput.text = "";
    }

    function toggle() {
        if (launcher.open) launcher.hide();
        else launcher.show();
    }

    function launchSelected() {
        let app = launcher.filteredApps[launcher.selectedIndex];
        if (!app) return;
        launcher.hide();
        app.execute();
    }

    IpcHandler {
        target: "launcher"
        function toggle(): void { launcher.toggle(); }
        function show(): void { launcher.show(); }
        function hide(): void { launcher.hide(); }
    }

    PanelWindow {
        id: launcherWindow
        screen: Quickshell.screens.length > 0 ? Quickshell.screens[0] : null
        visible: launcher.open
        anchors { top: true; bottom: true; left: true; right: true }
        exclusiveZone: 0
        color: "#52000000"
        WlrLayershell.keyboardFocus: launcher.open ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

        mask: Region { Region { item: dismissArea } }

        MouseArea {
            id: dismissArea
            anchors.fill: parent
            onClicked: launcher.hide()
        }

        Rectangle {
            id: card
            anchors.horizontalCenter: parent.horizontalCenter
            y: Math.max(70, parent.height * 0.18)
            width: 620
            height: 76 + Math.max(1, Math.min(8, launcher.filteredApps.length)) * 62 + 18
            radius: 14
            color: "#F21E1D1E"
            border.width: 1
            border.color: "#55FFFFFF"
            opacity: launcher.open ? 1 : 0
            scale: launcher.open ? 1 : 0.94

            Behavior on opacity { NumberAnimation { duration: 130; easing.type: Easing.OutQuad } }
            Behavior on scale { NumberAnimation { duration: 180; easing.type: Easing.OutBack; easing.overshoot: 1.03 } }

            MouseArea { anchors.fill: parent; onClicked: mouse => mouse.accepted = true }

            Rectangle {
                id: searchBox
                anchors.left: parent.left; anchors.right: parent.right
                anchors.top: parent.top
                anchors.margins: 14
                height: 48
                radius: 10
                color: "#20FFFFFF"
                border.width: 1
                border.color: searchInput.activeFocus ? "#65FFFFFF" : "#25FFFFFF"

                Text {
                    anchors.left: parent.left; anchors.leftMargin: 15
                    anchors.verticalCenter: parent.verticalCenter
                    text: "󰍉"
                    color: "#CACCCA"
                    font { family: "JetBrainsMono Nerd Font"; pixelSize: 17 }
                }

                TextInput {
                    id: searchInput
                    anchors.left: parent.left; anchors.leftMargin: 48
                    anchors.right: parent.right; anchors.rightMargin: 14
                    anchors.verticalCenter: parent.verticalCenter
                    color: "#FFFFFF"
                    selectionColor: "#55FFFFFF"
                    clip: true
                    font { family: "JetBrainsMono Nerd Font"; pixelSize: 14 }
                    onTextChanged: launcher.selectedIndex = 0

                    Keys.onEscapePressed: launcher.hide()
                    Keys.onDownPressed: {
                        if (launcher.filteredApps.length > 0)
                            launcher.selectedIndex = Math.min(launcher.filteredApps.length - 1, launcher.selectedIndex + 1);
                    }
                    Keys.onUpPressed: launcher.selectedIndex = Math.max(0, launcher.selectedIndex - 1)
                    Keys.onReturnPressed: launcher.launchSelected()
                    Keys.onEnterPressed: launcher.launchSelected()
                }

                Text {
                    anchors.left: searchInput.left
                    anchors.verticalCenter: parent.verticalCenter
                    visible: searchInput.text === ""
                    text: "Search applications…"
                    color: "#777777"
                    font { family: "JetBrainsMono Nerd Font"; pixelSize: 13 }
                }
            }

            ListView {
                id: appList
                anchors.left: parent.left; anchors.right: parent.right
                anchors.top: searchBox.bottom; anchors.topMargin: 8
                anchors.leftMargin: 14; anchors.rightMargin: 14
                height: Math.max(58, Math.min(8, launcher.filteredApps.length) * 62)
                spacing: 4
                clip: true
                boundsBehavior: Flickable.StopAtBounds
                model: launcher.filteredApps
                currentIndex: launcher.selectedIndex

                delegate: Rectangle {
                        required property var modelData
                        required property int index
                        width: appList.width
                        height: 58
                        radius: 10
                        color: index === launcher.selectedIndex ? "#2FFFFFFF" : (appMouse.containsMouse ? "#1FFFFFFF" : "transparent")
                        border.width: index === launcher.selectedIndex ? 1 : 0
                        border.color: "#35FFFFFF"

                        Image {
                            id: appIcon
                            anchors.left: parent.left; anchors.leftMargin: 10
                            anchors.verticalCenter: parent.verticalCenter
                            width: 36; height: 36
                            source: modelData.icon ? Quickshell.iconPath(modelData.icon, true) : ""
                            visible: source.toString() !== ""
                            fillMode: Image.PreserveAspectFit
                            asynchronous: true
                        }

                        Text {
                            anchors.centerIn: appIcon
                            visible: !appIcon.visible
                            text: "󰀻"
                            color: "#CACCCA"
                            font { family: "JetBrainsMono Nerd Font"; pixelSize: 20 }
                        }

                        Column {
                            anchors.left: parent.left; anchors.leftMargin: 58
                            anchors.right: parent.right; anchors.rightMargin: 12
                            anchors.verticalCenter: parent.verticalCenter
                            spacing: 3

                            Text {
                                width: parent.width
                                text: modelData.name
                                elide: Text.ElideRight
                                color: "#FFFFFF"
                                font { family: "JetBrainsMono Nerd Font"; pixelSize: 12; bold: true }
                            }
                            Text {
                                width: parent.width
                                text: modelData.comment || modelData.genericName || modelData.id
                                elide: Text.ElideRight
                                color: "#929292"
                                font { family: "JetBrainsMono Nerd Font"; pixelSize: 9 }
                            }
                        }

                        MouseArea {
                            id: appMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onEntered: launcher.selectedIndex = index
                            onClicked: {
                                launcher.selectedIndex = index;
                                launcher.launchSelected();
                            }
                        }
                }

                MouseArea {
                    z: 15
                    anchors.fill: parent
                    acceptedButtons: Qt.NoButton
                    onWheel: wheel => {
                        let delta = wheel.pixelDelta.y !== 0
                            ? wheel.pixelDelta.y
                            : (wheel.angleDelta.y / 120) * 62;
                        let maximum = Math.max(0, appList.contentHeight - appList.height);
                        appList.contentY = Math.max(0, Math.min(maximum, appList.contentY - delta));
                        wheel.accepted = true;
                    }
                }

                Rectangle {
                    z: 20
                    anchors.right: parent.right
                    anchors.rightMargin: 2
                    width: 3
                    height: Math.max(24, appList.height * appList.height / Math.max(1, appList.contentHeight))
                    y: appList.contentY * (appList.height - height)
                        / Math.max(1, appList.contentHeight - appList.height)
                    radius: 2
                    color: "#65FFFFFF"
                    visible: appList.contentHeight > appList.height
                }
            }

            Text {
                anchors.left: parent.left; anchors.right: parent.right
                anchors.top: searchBox.bottom; anchors.topMargin: 8
                height: 58
                visible: launcher.filteredApps.length === 0
                verticalAlignment: Text.AlignVCenter
                horizontalAlignment: Text.AlignHCenter
                text: "No applications found"
                color: "#8E8E8E"
                font { family: "JetBrainsMono Nerd Font"; pixelSize: 11 }
            }
        }
    }
}
