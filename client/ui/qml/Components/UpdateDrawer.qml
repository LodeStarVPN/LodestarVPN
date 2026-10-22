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
// install that did not happen opens the sheet at that start.
// The whole sheet is the connect button's night sky (UpdateSky): the light runs
// along the route of the app icon into the lodestar at the end of the title as
// the update comes down. Its colours do not follow the theme, as the button's do not
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

    // the sky's own edge and the sky under the content's end
    defaultColor: "#04071A"
    borderColor: "#3896AFFF"
    handle: true
    handleColor: "#47C9D1EA"

    // decimal megabytes, as Android shows sizes
    function megabytes(bytes) {
        return Math.round(bytes / 1000000)
    }

    readonly property string titleText: qsTr("Update %1").arg("<font color=\"#A9C1FF\">" + UpdateController.availableVersion + "</font>")

    readonly property string statusText: {
        switch (updateState) {
        case UpdateEnum.Available:
            return qsTr("A new version is available")
        case UpdateEnum.Downloading:
            // the whole file is here: its size and hash are being checked
            return UpdateController.progress >= 1 ? qsTr("Checking the file") : qsTr("Downloading")
        case UpdateEnum.ReadyToInstall:
            return qsTr("Ready to install")
        case UpdateEnum.WaitingPermission:
            return qsTr("Allow updates")
        case UpdateEnum.Installing:
            return qsTr("Installing")
        case UpdateEnum.Failed:
            switch (updateFailure) {
            case UpdateEnum.Network:
                return qsTr("Couldn't download")
            case UpdateEnum.Corrupt:
                return qsTr("The file was damaged")
            case UpdateEnum.PlayProtect:
                return qsTr("Google Play Protect stopped the update")
            case UpdateEnum.Cancelled:
                return windows ? qsTr("The update was not installed") : qsTr("The update was cancelled")
            case UpdateEnum.BlockedBySystem:
                return qsTr("Android didn't allow the installation")
            }
            return qsTr("Couldn't install the update")
        }
        return ""
    }

    readonly property string subText: {
        switch (updateState) {
        case UpdateEnum.Available:
            return qsTr("The download is about %1 MB").arg(Math.max(1, megabytes(UpdateController.downloadSize)))
        case UpdateEnum.Downloading:
            return qsTr("%1 of %2 MB").arg(megabytes(UpdateController.downloadSize * UpdateController.progress))
                                     .arg(Math.max(1, megabytes(UpdateController.downloadSize)))
        case UpdateEnum.ReadyToInstall:
            // Android: the Play Protect hint below shows the rest
            if (windows) {
                return qsTr("The VPN turns off for the install, and the app closes and opens again by itself. Windows will ask to allow changes — choose «Yes».")
            }
            return ConnectionController.isConnected ? qsTr("The VPN turns off for the install and comes back by itself.") : ""
        case UpdateEnum.WaitingPermission:
            return qsTr("To install updates, allow LodestarVPN to install apps: turn on «Allow from this source» and come back.")
        case UpdateEnum.Installing:
            return windows ? qsTr("The app will close and open again.") : qsTr("Confirm the installation in the system window.")
        case UpdateEnum.Failed:
            switch (updateFailure) {
            case UpdateEnum.Network:
                return qsTr("Check your internet connection and try again.")
            case UpdateEnum.Corrupt:
                return qsTr("Download it again.")
            case UpdateEnum.Cancelled:
                return windows ? qsTr("When Windows asks to allow changes, choose «Yes».") : ""
            case UpdateEnum.BlockedBySystem:
                return qsTr("Try again later or contact support.")
            case UpdateEnum.Other:
                return qsTr("Try again.")
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
        contentHeight: content.implicitHeight + 22 + SettingsController.safeAreaBottomMargin
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

        UpdateSky {
            id: sky

            width: scroller.width
            height: Math.max(scroller.height, scroller.contentHeight)

            running: root.isOpened && Qt.application.state === Qt.ApplicationActive
        }

        ColumnLayout {
            id: content

            width: scroller.width
            spacing: 0

            // the handle's room (DrawerType2 draws it)
            Item {
                Layout.fillWidth: true
                Layout.preferredHeight: 12
            }

            // the lodestar stands at the end of this row (UpdateSky)
            Text {
                Layout.fillWidth: true
                Layout.topMargin: 18
                Layout.leftMargin: 16
                Layout.rightMargin: 84

                font.family: "IBM Plex Mono"
                font.pixelSize: 20
                font.weight: Font.Medium
                lineHeight: 28
                lineHeightMode: Text.FixedHeight
                color: "#E9EDFB"
                textFormat: Text.StyledText
                elide: Text.ElideRight

                text: root.titleText
            }

            // the route's room: the sky above the status is the route's to 212 px from the top
            Item {
                Layout.fillWidth: true
                Layout.preferredHeight: 154
            }

            RowLayout {
                Layout.fillWidth: true
                Layout.topMargin: 14
                Layout.leftMargin: 16
                Layout.rightMargin: 16

                spacing: 16

                ColumnLayout {
                    Layout.fillWidth: true
                    Layout.alignment: Qt.AlignVCenter

                    spacing: 3

                    Text {
                        Layout.fillWidth: true

                        font.family: "IBM Plex Mono"
                        font.pixelSize: 15
                        font.weight: Font.Medium
                        lineHeight: 20
                        lineHeightMode: Text.FixedHeight
                        color: "#D5DBF0"
                        wrapMode: Text.Wrap

                        text: root.statusText
                    }

                    Text {
                        Layout.fillWidth: true

                        visible: text !== ""

                        font.family: "IBM Plex Mono"
                        font.pixelSize: 13
                        lineHeight: 19
                        lineHeightMode: Text.FixedHeight
                        color: "#8A93B2"
                        wrapMode: Text.Wrap

                        text: root.subText
                    }
                }

                // how much has come; where it stopped, greyed, when the download broke off
                Text {
                    Layout.alignment: Qt.AlignVCenter

                    readonly property bool broken: root.failed && root.updateFailure === UpdateEnum.Network && sky.lastProgress > 0

                    visible: text !== ""

                    font.family: "IBM Plex Mono"
                    font.pixelSize: 28
                    font.weight: Font.Medium
                    font.features: { "tnum": 1 }
                    color: broken ? "#5F6888" : "#A9C1FF"

                    text: root.updateState === UpdateEnum.Downloading ? Math.floor(UpdateController.progress * 100) + "%"
                        : broken ? Math.floor(sky.lastProgress * 100) + "%" : ""
                }
            }

            PlayProtectHint {
                Layout.fillWidth: true
                Layout.topMargin: 16
                Layout.leftMargin: 16
                Layout.rightMargin: 16

                visible: root.playProtectHintVisible
                captionColor: "#8A93B2"
            }

            Text {
                Layout.fillWidth: true
                Layout.topMargin: 16
                Layout.leftMargin: 16
                Layout.rightMargin: 16

                visible: root.appLockHintVisible

                font.family: "IBM Plex Mono"
                font.pixelSize: 13
                lineHeight: 19
                lineHeightMode: Text.FixedHeight
                color: "#8A93B2"
                wrapMode: Text.Wrap

                text: qsTr("If Google Play is locked with App lock, open Google Play and unlock it first — otherwise the lock screen hides this window and the update is cancelled.")
            }

            // the main step: the app's main button, glass lit by the ring's blue
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

                defaultColor: DopamineStyle.color.glassButton
                hoveredColor: DopamineStyle.color.glassButtonHovered
                pressedColor: DopamineStyle.color.glassButtonPressed
                textColor: DopamineStyle.color.glassButtonText

                visible: root.updateState === UpdateEnum.Downloading

                text: qsTr("Cancel")

                clickedFunc: function() {
                    UpdateController.cancelDownload()
                }
            }
        }
    }
}
