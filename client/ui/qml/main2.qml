import QtQuick
import QtQuick.Window
import QtQuick.Controls
import QtQuick.Layouts
import QtQuick.Dialogs

import PageEnum 1.0
import Style 1.0

import "Config"
import "Controls2"
import "Components"
import "Pages2"

Window  {
    id: root
    objectName: "mainWindow"

    Connections {
        target: Qt.application
        function onStateChanged() {
            if (Qt.platform.os === "android") {
                if (Qt.application.state === Qt.ApplicationActive) {
                    refreshTimer.restart()
                } else if (Qt.application.state === Qt.ApplicationSuspended || 
                          Qt.application.state === Qt.ApplicationInactive) {
                    console.log("QML: Application going to background, state:", Qt.application.state)
                }
            }
        }
    }

    Timer {
        id: refreshTimer
        interval: 150
        repeat: false
        onTriggered: {
            if (Qt.platform.os === "android" && SettingsController.isEdgeToEdgeEnabled()) {
                console.log("QML: Application resumed with edge-to-edge")
            }
        }
    }

    visible: true
    width: GC.screenWidth
    height: GC.screenHeight
    minimumWidth: GC.isDesktop() ? 360 : 0
    minimumHeight: GC.isDesktop() ? 640 : 0
    maximumWidth: 600
    maximumHeight: 800

    color: DopamineStyle.color.midnightBlack

    // palette is picked from settings in DopamineStyle itself (initial binding),
    // so no post-construction swap is needed - previously this reassigned the
    // `color` property on the singleton, invalidating every binding app-wide
    // and producing a white flash on the first frame.

    onClosing: function(close) {
        close.accepted = false
        PageController.closeWindow()
    }

    onSceneGraphError: function(error, message) {
        // Prevent qFatal crash on Android when EGL context is lost
        console.warn("Scene graph error:", error, message)
    }

    title: "LodestarVPN"

    Item { // This item is needed for focus handling
        id: defaultFocusItem
        objectName: "defaultFocusItem"

        focus: true

        Keys.onPressed: function(event) {
            switch (event.key) {
            case Qt.Key_Tab:
            case Qt.Key_Down:
            case Qt.Key_Right:
                FocusController.nextKeyTabItem()
                break
            case Qt.Key_Backtab:
            case Qt.Key_Up:
            case Qt.Key_Left:
                FocusController.previousKeyTabItem()
                break
            default:
                PageController.keyPressEvent(event.key)
                event.accepted = true
            }
        }
    }

    Loader {
        active: Qt.platform.os === "android"
        source: Qt.platform.os === "android" ? "Components/GamepadLoader.qml" : ""
    }

    Connections {
        objectName: "pageControllerConnections"

        target: PageController

        function onRaiseMainWindow() {
            root.show()
            root.raise()
            root.requestActivate()
        }

        function onHideMainWindow() {
            root.hide()
        }

        function onShowErrorMessage(errorMessage) {
            popupErrorMessage.text = errorMessage
            popupErrorMessage.open()
        }

        // a subscription link opened from outside the app: added only on a yes
        function onAskToAddSubscriptionLink(link) {
            root.show()
            root.raise()
            root.requestActivate()
            root.showQuestionDrawer(qsTr("Add the subscription from the link?"),
                                    qsTr("A link opened LodestarVPN to add a subscription. Add it only if you got the link from LodestarVPN or from someone you trust."),
                                    qsTr("Add"), qsTr("Cancel"),
                                    function() { PageController.subscriptionLinkConfirmed(link) },
                                    function() {})
        }

        // the key of another subscription than the one the app holds: the app keeps one
        // (the owner, 2026-10-22), so it asks before the gateway is (that takes a place on it).
        // First whether this device can be unlinked from the held one today: a subscription
        // unlinks one device a day, and the question must not promise what will not happen
        function onAskToReplaceSubscription(key) {
            root.replaceKey = key
            PageController.showBusyIndicator(true)
            replaceCheckTimer.restart()
            ApiConfigsController.checkHeldSubscriptionUnlink()
        }

        function onShowNotificationMessage(message) {
            popupNotificationMessage.text = message
            popupNotificationMessage.closeButtonVisible = false
            popupNotificationMessage.open()
            // 3 s for a short one, longer for a few lines of text
            popupNotificationTimer.interval = Math.max(3000, message.length * 60)
            popupNotificationTimer.restart()
        }

        function onGoToPageSettingsBackup() {
            PageController.goToPage(PageEnum.PageSettingsBackup)
        }

        function onShowBusyIndicator(visible) {
            busyIndicator.visible = visible
            PageController.disableControls(visible)
        }
    }

    Connections {
        objectName: "settingsControllerConnections"

        target: SettingsController

        function onChangeSettingsFinished(finishedMessage) {
            PageController.showNotificationMessage(finishedMessage)
        }
    }

    // the subscription key waiting for the question about replacing the held one
    property string replaceKey: ""

    Connections {
        target: ApiConfigsController

        function onHeldSubscriptionUnlinkChecked(unlinkAt) {
            root.askToReplace(unlinkAt)
        }
    }

    // the gateway not answering soon: the question as when the unlink can go
    Timer {
        id: replaceCheckTimer

        interval: 4000
        repeat: false
        onTriggered: root.askToReplace("")
    }

    function askToReplace(unlinkAt) {
        if (root.replaceKey === "") {
            return
        }
        const key = root.replaceKey
        root.replaceKey = ""
        replaceCheckTimer.stop()
        PageController.showBusyIndicator(false)
        root.showQuestionDrawer(qsTr("Replace the subscription?"),
                                unlinkAt === ""
                                ? qsTr("LodestarVPN keeps one subscription. The servers of the current one leave the app, and this device is unlinked from it: its place there is freed, and it can come back to it only after a day.")
                                : qsTr("LodestarVPN keeps one subscription. The servers of the current one leave the app, but this device cannot be unlinked from it today: a device was unlinked from it today already. The device stays in it and takes a place there until it is unlinked in Active devices on another device with that subscription, after %1.").arg(unlinkAt),
                                qsTr("Replace"), qsTr("Cancel"),
                                function() { PageController.subscriptionReplaceConfirmed(key) },
                                function() {})
    }

    // the night behind every page but the home one, which draws its own (HomeScene): the home's
    // sky without its land (shaders/pagesky.frag). Still, so drawn once
    ShaderEffect {
        anchors.fill: parent

        layer.enabled: true

        property size itemSize: Qt.size(width, height)
        property real pixel: 1 / Screen.devicePixelRatio
        property real sheet: 0
        property real corner: 0

        fragmentShader: "qrc:/shaders/pagesky.frag.qsb"
    }

    PageStart {
        objectName: "pageStart"
        width: root.width
        height: root.height
    }

    Item {
        objectName: "popupNotificationItem"

        anchors.right: parent.right
        anchors.left: parent.left
        anchors.bottom: parent.bottom

        implicitHeight: popupNotificationMessage.height

        PopupType {
            id: popupNotificationMessage
        }

        Timer {
            id: popupNotificationTimer

            interval: 3000
            repeat: false
            running: false
            onTriggered: {
                popupNotificationMessage.close()
            }
        }
    }

    Item {
        objectName: "popupErrorMessageItem"

        anchors.right: parent.right
        anchors.left: parent.left
        anchors.bottom: parent.bottom

        implicitHeight: popupErrorMessage.height

        PopupType {
            id: popupErrorMessage
        }
    }

    // one sheet for the in-app update: the home card and the About page open it
    // (showUpdateDrawer), and it reopens itself after the system's install windows
    Item {
        objectName: "updateDrawerItem"

        anchors.fill: parent

        // a sheet here is under no page: Back (Escape) pressed in it goes to PageController
        // as from a page, which closes the sheet. Unhandled, it reached the window, and on
        // Android that closed the app
        Keys.onPressed: function(event) {
            if (event.key === Qt.Key_Back || event.key === Qt.Key_Escape) {
                PageController.keyPressEvent(event.key)
                event.accepted = true
            }
        }

        UpdateDrawer {
            id: updateDrawer

            anchors.fill: parent
        }

        // Windows: the start after an install this app closed for says it came through
        Timer {
            interval: 1500
            running: UpdateController.updatedVersion !== ""
            repeat: false

            onTriggered: PageController.showNotificationMessage(qsTr("LodestarVPN is updated to %1").arg(UpdateController.updatedVersion))
        }
    }

    Item {
        objectName: "questionDrawerItem"

        anchors.fill: parent

        // as for the update sheet above
        Keys.onPressed: function(event) {
            if (event.key === Qt.Key_Back || event.key === Qt.Key_Escape) {
                PageController.keyPressEvent(event.key)
                event.accepted = true
            }
        }

        QuestionDrawer {
            id: questionDrawer

            anchors.fill: parent
        }
    }

    Item {
        objectName: "busyIndicatorItem"

        anchors.fill: parent

        BusyIndicatorType {
            id: busyIndicator
            anchors.centerIn: parent
            z: 1
        }
    }

    function showQuestionDrawer(headerText, descriptionText, yesButtonText, noButtonText, yesButtonFunction, noButtonFunction) {
        questionDrawer.headerText = headerText
        questionDrawer.descriptionText = descriptionText
        questionDrawer.yesButtonText = yesButtonText
        questionDrawer.noButtonText = noButtonText

        questionDrawer.yesButtonFunction = function() {
            questionDrawer.closeTriggered()
            if (yesButtonFunction && typeof yesButtonFunction === "function") {
                yesButtonFunction()
            }
        }
        questionDrawer.noButtonFunction = function() {
            questionDrawer.closeTriggered()
            if (noButtonFunction && typeof noButtonFunction === "function") {
                noButtonFunction()
            }
        }
        questionDrawer.openTriggered()
    }

    function showUpdateDrawer() {
        updateDrawer.openTriggered()
    }

    FileDialog {
        id: mainFileDialog
        objectName: "mainFileDialog"

        property bool isSaveMode: false

        fileMode: isSaveMode ? FileDialog.SaveFile : FileDialog.OpenFile

        onAccepted: SystemController.fileDialogClosed(true)
        onRejected: SystemController.fileDialogClosed(false)
    }
}
