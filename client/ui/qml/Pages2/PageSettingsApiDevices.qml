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

        delegate: ColumnLayout {
            width: listView.width

            LabelWithButtonType {
                Layout.fillWidth: true
                Layout.topMargin: 6

                // the OS the device reported and when it was last active; its id
                // (supportTag) is only used to unlink it, never shown. "This
                // device" goes under the name: glued to it, it read as part of
                // the name and made the row taller
                text: osVersion !== "" ? osVersion : qsTr("Device")
                descriptionText: isCurrentDevice ? qsTr("This device")
                                                 : (lastUpdate !== "" ? qsTr("Last active: %1").arg(lastUpdate) : "")
                rightImageSource: "qrc:/images/controls/trash.svg"

                clickedFunction: function() {
                    if (isCurrentDevice && ServersModel.isDefaultServerCurrentlyProcessed() && ConnectionController.isConnected) {
                        PageController.showNotificationMessage(qsTr("Cannot unlink device during active connection"))
                        return
                    }

                    var headerText = qsTr("Unlink this device?")
                    // the gateway lets an unlinked device back only after 24 h
                    var descriptionText = qsTr("The device will be unlinked from your subscription. It can be added again in 24 hours by entering the subscription ID on it.")
                    var yesButtonText = qsTr("Unlink")
                    var noButtonText = qsTr("Cancel")

                    var yesButtonFunction = function() {
                        Qt.callLater(unlinkDevice, supportTag, countryCode, isCurrentDevice)
                    }
                    var noButtonFunction = function() {
                    }

                    showQuestionDrawer(headerText, descriptionText, yesButtonText, noButtonText, yesButtonFunction, noButtonFunction)
                }
            }

            DividerType {}
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
