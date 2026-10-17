import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtQuick.Dialogs

import QtCore

import SortFilterProxyModel 0.2

import PageEnum 1.0
import Style 1.0

import "./"
import "../Controls2"
import "../Controls2/TextTypes"
import "../Config"
import "../Components"

PageType {
    id: root

    // "2 out of 5", re-read whenever the account info comes
    property string devicesInUse: ApiAccountInfoModel.data("connectedDevices")
    // "" when a device may be unlinked now (one a day)
    property string unlinkAt: ApiAccountInfoModel.data("unlinkAvailableAt")

    Connections {
        target: ApiAccountInfoModel

        function onModelReset() {
            root.devicesInUse = ApiAccountInfoModel.data("connectedDevices")
            root.unlinkAt = ApiAccountInfoModel.data("unlinkAvailableAt")
        }
    }

    ListViewType {
        id: listView

        anchors.fill: parent
        anchors.topMargin: 20 + SettingsController.safeAreaTopMargin
        anchors.bottomMargin: 24

        model: ApiDevicesModel

        header: ColumnLayout {
            width: listView.width

            BackButtonType {
                id: backButton
            }

            BaseHeaderType {
                id: header

                Layout.fillWidth: true
                Layout.rightMargin: 16
                Layout.leftMargin: 16

                Layout.bottomMargin: 8

                headerText: qsTr("Active Devices")
                // one limit for the whole subscription, whatever the protocol
                descriptionText: {
                    var text = qsTr("Devices using your subscription. Unlink one you no longer use to free its place. One device can be unlinked a day.")
                    if (root.unlinkAt !== "") {
                        text += "\n" + qsTr("The next one can be unlinked after %1.").arg(root.unlinkAt)
                    }
                    return root.devicesInUse !== "" ? qsTr("In use: %1").arg(root.devicesInUse) + "\n" + text : text
                }
            }
        }

        // the devices in one glass card; this one lit by the lodestar, which takes its trash's place
        // (unlinking itself is still a tap on it away)
        delegate: ColumnLayout {
            width: listView.width

            spacing: 0

            LabelWithButtonType {
                Layout.fillWidth: true

                glass: listView.count === 1 ? "single" : index === 0 ? "first"
                     : index === listView.count - 1 ? "last" : "middle"
                glassLit: isCurrentDevice

                // the OS the device reported and when it was last active; its id
                // (supportTag) is only used to unlink it, never shown. "This
                // device" goes under the name: glued to it, it read as part of
                // the name and made the row taller. A device without our app
                // (an iPhone) says by its name what it connects through
                text: (osVersion !== "" ? osVersion : qsTr("Device")) + (otherApp === "amneziawg" ? " · AmneziaWG" : "")
                // (its key gone from the servers: a copy of it was caught, only a new file helps)
                descriptionText: isCurrentDevice ? qsTr("This device")
                                                 : needsNewFile ? qsTr("Needs a new file: tap it")
                                                                : (lastUpdate !== "" ? qsTr("Last active: %1").arg(lastUpdate) : "")
                rightImageSource: isCurrentDevice ? "" : otherApp === "amneziawg" ? "qrc:/images/controls/chevron-right.svg"
                                                                                    : "qrc:/images/controls/trash.svg"

                clickedFunction: function() {
                    if (isCurrentDevice && ServersModel.isDefaultServerCurrentlyProcessed() && ConnectionController.isConnected) {
                        PageController.showNotificationMessage(qsTr("Cannot unlink device during active connection"))
                        return
                    }

                    // its files are had again here, or it is unlinked like any other
                    if (otherApp === "amneziawg") {
                        otherDeviceDrawer.deviceId = supportTag
                        otherDeviceDrawer.needsNewFile = needsNewFile
                        otherDeviceDrawer.headerText = osVersion !== "" ? osVersion : qsTr("Device")
                        otherDeviceDrawer.openTriggered()
                        return
                    }

                    root.askUnlink(supportTag, countryCode, isCurrentDevice, false)
                }
            }
        }
    }

    function askUnlink(supportTag, countryCode, isCurrentDevice, isOther) {
        var yesButtonFunction = function() {
            Qt.callLater(unlinkDevice, supportTag, countryCode, isCurrentDevice)
        }
        // the gateway lets an unlinked device back only after 24 h; one without our app has no
        // key to enter: its files just stop working
        showQuestionDrawer(qsTr("Unlink this device?"),
                           isOther ? qsTr("The device will be unlinked from your subscription, and its files will stop working.")
                                   : qsTr("The device will be unlinked from your subscription. It can be added again in 24 hours by entering the subscription ID on it."),
                           qsTr("Unlink"), qsTr("Cancel"), yesButtonFunction, function() {})
    }

    // a new key for a device without our app: its old files stop working, the new ones are shown
    function newFiles(deviceId) {
        PageController.showBusyIndicator(true)
        var done = ApiConfigsController.newOtherDeviceFiles(deviceId)
        PageController.showBusyIndicator(false)
        if (done) {
            PageController.goToPage(PageEnum.PageSettingsApiOtherDevice)
        }
    }

    // its files again, the key it has: what is on the device goes on working
    function sameFiles(deviceId) {
        PageController.showBusyIndicator(true)
        var done = ApiConfigsController.otherDeviceFilesAgain(deviceId)
        PageController.showBusyIndicator(false)
        if (done) {
            PageController.goToPage(PageEnum.PageSettingsApiOtherDevice)
        }
    }

    Connections {
        target: ApiConfigsController
        // only while this page is on top: the device's own page says it itself
        enabled: root.StackView.status === StackView.Active

        function onOtherDeviceFailed(message) {
            PageController.showErrorMessage(message)
        }
    }

    // a device without our app: its files again (the owner, 2026-10-17: a second iPhone went in to
    // see the first one's code again), a new file, or unlinking it. A key burned on a copy has no
    // files to show again: a new file then
    QuestionDrawer {
        id: otherDeviceDrawer

        property string deviceId
        property bool needsNewFile: false

        anchors.fill: parent

        descriptionText: needsNewFile
                         ? qsTr("It connects through AmneziaWG. Its key does not work any more: it needs a new file.")
                         : qsTr("It connects through AmneziaWG. «Show file» gives the file and the code it already has. A new file replaces the old one: the old files and codes stop working.")
        yesButtonText: needsNewFile ? qsTr("New file") : qsTr("Show file")
        middleButtonText: needsNewFile ? "" : qsTr("New file")
        noButtonText: qsTr("Unlink")

        yesButtonFunction: function() {
            otherDeviceDrawer.closeTriggered()
            Qt.callLater(otherDeviceDrawer.needsNewFile ? root.newFiles : root.sameFiles, otherDeviceDrawer.deviceId)
        }
        middleButtonFunction: function() {
            otherDeviceDrawer.closeTriggered()
            Qt.callLater(root.newFiles, otherDeviceDrawer.deviceId)
        }
        noButtonFunction: function() {
            otherDeviceDrawer.closeTriggered()
            root.askUnlink(otherDeviceDrawer.deviceId, "", false, true)
        }
    }

    function unlinkDevice(supportTag, countryCode, isCurrentDevice) {
        PageController.showBusyIndicator(true)
        // this device unlinks itself by its own id (the list has only a hash of it)
        var done = isCurrentDevice ? ApiConfigsController.deactivateDevice(false)
                                   : ApiConfigsController.deactivateExternalDevice(supportTag, countryCode)
        if (done) {
            // past the cache: the list must show the change
            ApiSettingsController.getAccountInfo(true, true)
        }
        PageController.showBusyIndicator(false)
    }
}
