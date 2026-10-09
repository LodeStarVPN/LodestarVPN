import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

import Style 1.0
import UpdateEnum 1.0

import "../Controls2"
import "../Controls2/TextTypes"

// The in-app update, one sheet for every step of UpdateController.state. The
// system's install windows put the app in the background, and that closes any
// open sheet (DrawerType2): coming back from one of them with something to
// explain (Play Protect, a cancel, the permission), the sheet opens again. On
// Windows the app closes for the installer and opens again after it: an
// install that did not happen opens the sheet at that start
DrawerType2 {
    id: root
    objectName: "updateDrawer"

    readonly property int updateState: UpdateController.state
    readonly property int updateFailure: UpdateController.failure
    readonly property bool failed: updateState === UpdateEnum.Failed
    readonly property bool windows: Qt.platform.os === "windows"
    readonly property bool playProtectHintVisible: !windows && (updateState === UpdateEnum.ReadyToInstall
                                                                || (failed && updateFailure === UpdateEnum.PlayProtect))
    // MIUI/HyperOS App lock on Google Play covers the Play Protect window, which
    // then closes by itself: the install ends as cancelled
    readonly property bool appLockHintVisible: UpdateController.xiaomi
                                               && (playProtectHintVisible || (failed && updateFailure === UpdateEnum.Cancelled))

    // the user went from this sheet to a system window: what came of it reopens the sheet
    property bool awaitingOutcome: false

    property real sheetContentHeight: 0

    expandedHeight: Math.min(sheetContentHeight, height * 0.9)

    readonly property string headerText: {
        if (updateState === UpdateEnum.ReadyToInstall) {
            return qsTr("Before you install")
        }
        if (updateState === UpdateEnum.WaitingPermission) {
            return qsTr("Allow updates")
        }
        if (failed && updateFailure === UpdateEnum.PlayProtect) {
            return qsTr("Google Play Protect stopped the update")
        }
        return qsTr("Update available")
    }

    readonly property string bodyText: {
        switch (updateState) {
        case UpdateEnum.Available:
            // decimal megabytes, as Android shows sizes
            return qsTr("Version %1 is ready. The download is about %2 MB.")
                    .arg(UpdateController.availableVersion)
                    .arg(Math.max(1, Math.round(UpdateController.downloadSize / 1000000)))
        case UpdateEnum.Downloading:
            return qsTr("Downloading the update…")
        case UpdateEnum.ReadyToInstall:
            // Android: the Play Protect hint below says it all
            return windows ? qsTr("The VPN turns off for the install, and the app closes and opens again by itself. Windows will ask to allow changes — choose «Yes».")
                           : ""
        case UpdateEnum.WaitingPermission:
            return qsTr("To install updates, allow LodestarVPN to install apps: turn on «Allow from this source» and come back.")
        case UpdateEnum.Installing:
            return windows ? qsTr("Installing the update — the app will close and open again.")
                           : qsTr("Confirm the installation in the system window.")
        case UpdateEnum.Failed:
            switch (updateFailure) {
            case UpdateEnum.Cancelled:
                return windows ? qsTr("The update was not installed. When Windows asks to allow changes, choose «Yes».")
                               : qsTr("The update was cancelled.")
            case UpdateEnum.Network:
                return qsTr("Couldn't download the update. Check your internet connection and try again.")
            case UpdateEnum.Corrupt:
                return qsTr("The update file was damaged. Try again.")
            case UpdateEnum.BlockedBySystem:
                return qsTr("Android didn't allow the installation. Try again later or contact support.")
            case UpdateEnum.Other:
                return qsTr("Couldn't install the update. Try again.")
            }
            return ""
        }
        return ""
    }

    readonly property string buttonText: {
        switch (updateState) {
        case UpdateEnum.Available:
            return qsTr("Update")
        case UpdateEnum.ReadyToInstall:
            return qsTr("Install")
        case UpdateEnum.WaitingPermission:
            return qsTr("Open settings")
        case UpdateEnum.Failed:
            // a policy block: the same install now would only be blocked again
            return updateFailure === UpdateEnum.BlockedBySystem ? "" : qsTr("Try again")
        }
        return ""
    }

    function buttonClicked() {
        switch (updateState) {
        case UpdateEnum.Available:
            UpdateController.startUpdate()
            break
        case UpdateEnum.ReadyToInstall:
            root.awaitingOutcome = true
            UpdateController.install()
            break
        case UpdateEnum.WaitingPermission:
            root.awaitingOutcome = true
            UpdateController.openInstallPermission()
            break
        case UpdateEnum.Failed:
            if (updateFailure === UpdateEnum.Network || updateFailure === UpdateEnum.Corrupt) {
                if (UpdateController.updateAvailable) {
                    UpdateController.startUpdate()
                } else {
                    UpdateController.checkForUpdate(true)
                }
            } else {
                root.awaitingOutcome = true
                UpdateController.install()
            }
            break
        }
    }

    // read from the controller, not the bindings above: called from its own signal
    function outcomeToExplain() {
        const state = UpdateController.state
        const failure = UpdateController.failure
        return state === UpdateEnum.WaitingPermission
                || (state === UpdateEnum.Failed && (failure === UpdateEnum.PlayProtect || failure === UpdateEnum.Cancelled
                                                    || failure === UpdateEnum.BlockedBySystem || failure === UpdateEnum.Other))
    }

    function reopenIfAwaited() {
        if (root.awaitingOutcome && outcomeToExplain()) {
            reopenTimer.restart()
        }
    }

    Connections {
        target: UpdateController

        function onStateChanged() {
            const state = UpdateController.state
            // nothing to update to any more (withdrawn, or installed meanwhile)
            if (state === UpdateEnum.Idle || state === UpdateEnum.Checking || state === UpdateEnum.UpToDate) {
                root.awaitingOutcome = false
                if (root.isOpened) {
                    root.closeTriggered()
                }
                return
            }
            root.reopenIfAwaited()
        }

        // Windows: the install this app closed for did not happen
        function onInstallNotDone() {
            root.awaitingOutcome = true
            root.reopenIfAwaited()
        }
    }

    Connections {
        target: Qt.application

        function onStateChanged() {
            if (Qt.application.state === Qt.ApplicationActive) {
                root.reopenIfAwaited()
            }
        }
    }

    // a moment after the app is active again: a sheet opened while it was still
    // inactive would be closed by DrawerType2 right away
    Timer {
        id: reopenTimer

        interval: 300
        repeat: false

        onTriggered: {
            if (Qt.application.state !== Qt.ApplicationActive || !root.outcomeToExplain()) {
                return
            }
            root.awaitingOutcome = false
            if (!root.isOpened) {
                root.openTriggered()
            }
        }
    }

    expandedStateContent: Flickable {
        id: scroller

        implicitHeight: root.expandedHeight
        contentHeight: content.implicitHeight + 32 + SettingsController.safeAreaBottomMargin
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        interactive: contentHeight > height

        ScrollBar.vertical: ScrollBarType {}

        // the next step's text may be shorter than where the sheet was scrolled to
        onContentHeightChanged: {
            root.sheetContentHeight = contentHeight
            returnToBounds()
        }
        Component.onCompleted: root.sheetContentHeight = contentHeight

        ColumnLayout {
            id: content

            width: scroller.width
            spacing: 0

            Header2TextType {
                Layout.fillWidth: true
                Layout.topMargin: 24
                Layout.leftMargin: 16
                Layout.rightMargin: 16

                wrapMode: Text.Wrap

                text: root.headerText
            }

            ParagraphTextType {
                Layout.fillWidth: true
                Layout.topMargin: 12
                Layout.leftMargin: 16
                Layout.rightMargin: 16

                visible: text !== ""

                text: root.bodyText
            }

            RowLayout {
                Layout.fillWidth: true
                Layout.topMargin: 16
                Layout.leftMargin: 16
                Layout.rightMargin: 16

                spacing: 12

                visible: root.updateState === UpdateEnum.Downloading

                Rectangle {
                    Layout.fillWidth: true
                    Layout.alignment: Qt.AlignVCenter

                    implicitHeight: 6
                    radius: 3
                    color: DopamineStyle.color.sheerWhite

                    Rectangle {
                        width: parent.width * Math.min(1, Math.max(0, UpdateController.progress))
                        height: parent.height
                        radius: parent.radius
                        color: DopamineStyle.color.goldenApricot
                    }
                }

                CaptionTextType {
                    Layout.alignment: Qt.AlignVCenter
                    Layout.minimumWidth: 40

                    horizontalAlignment: Text.AlignRight
                    color: DopamineStyle.color.mutedGray
                    font.pixelSize: 14

                    text: Math.floor(UpdateController.progress * 100) + "%"
                }
            }

            PlayProtectHint {
                Layout.fillWidth: true
                Layout.topMargin: 12
                Layout.leftMargin: 16
                Layout.rightMargin: 16

                visible: root.playProtectHintVisible
            }

            SmallTextType {
                Layout.fillWidth: true
                Layout.topMargin: 16
                Layout.leftMargin: 16
                Layout.rightMargin: 16

                visible: root.appLockHintVisible

                text: qsTr("If Google Play is locked with App lock, open Google Play and unlock it first — otherwise the lock screen hides this window and the update is cancelled.")
            }

            SmallTextType {
                Layout.fillWidth: true
                Layout.topMargin: 16
                Layout.leftMargin: 16
                Layout.rightMargin: 16

                visible: root.updateState === UpdateEnum.ReadyToInstall && ConnectionController.isConnected
                color: DopamineStyle.color.mutedGray

                text: qsTr("The VPN will reconnect after the update.")
            }

            BasicButtonType {
                Layout.fillWidth: true
                Layout.topMargin: 24
                Layout.leftMargin: 16
                Layout.rightMargin: 16

                visible: root.buttonText !== ""

                text: root.buttonText

                clickedFunc: function() {
                    root.buttonClicked()
                }
            }

            BasicButtonType {
                Layout.fillWidth: true
                Layout.topMargin: 24
                Layout.leftMargin: 16
                Layout.rightMargin: 16

                defaultColor: DopamineStyle.color.transparent
                hoveredColor: DopamineStyle.color.translucentWhite
                pressedColor: DopamineStyle.color.sheerWhite
                disabledColor: DopamineStyle.color.mutedGray
                textColor: DopamineStyle.color.paleGray
                borderWidth: 1

                visible: root.updateState === UpdateEnum.Downloading

                text: qsTr("Cancel")

                clickedFunc: function() {
                    UpdateController.cancelDownload()
                }
            }
        }
    }
}
