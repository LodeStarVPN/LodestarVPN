import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtQuick.Dialogs

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

    property list<QtObject> labelsModel: [
        statusObject,
        devicesObject
    ]

    QtObject {
        id: statusObject

        readonly property string title: qsTr("Subscription Status")
        readonly property string contentKey: "subscriptionStatus"
        readonly property string objectImageSource: "qrc:/images/controls/info.svg"
        readonly property bool isRichText: true
    }

    QtObject {
        id: devicesObject

        // "2 out of 5": one limit for the subscription over every protocol
        readonly property string title: qsTr("Devices")
        readonly property string contentKey: "connectedDevices"
        readonly property string objectImageSource: "qrc:/images/controls/monitor.svg"
        readonly property bool isRichText: false
    }

    property var processedServer

    Component.onCompleted: {
        // shared connections (lodestar://conn) have no subscription account behind
        // them - asking the API for account info errors out, so skip both the
        // refresh and the status row for them
        var apiConfig = ServersModel.getProcessedServerData("apiConfig")
        if (apiConfig && apiConfig.shared === true) {
            labelsModel = []
            return
        }
        // the card opens with cached data for instant display, but the local copy
        // has no subscription_end_date - refresh from the server so the status
        // row shows "Active · until <date>" (pattern copied from the devices page)
        PageController.showBusyIndicator(true)
        ApiSettingsController.getAccountInfo(true)
        PageController.showBusyIndicator(false)
    }

    Connections {
        target: ServersModel

        function onProcessedServerChanged() {
            root.processedServer = proxyServersModel.get(0)
        }
    }

    SortFilterProxyModel {
        id: proxyServersModel
        objectName: "proxyServersModel"

        sourceModel: ServersModel
        filters: [
            ValueFilter {
                roleName: "isCurrentlyProcessed"
                value: true
            }
        ]

        Component.onCompleted: {
            root.processedServer = proxyServersModel.get(0)
        }
    }

    ListViewType {
        id: listView

        anchors.fill: parent

        model: labelsModel

        header: ColumnLayout {
            width: listView.width

            spacing: 4

            BackButtonType {
                id: backButton
                objectName: "backButton"

                Layout.topMargin: 20 + SettingsController.safeAreaTopMargin
            }

            HeaderTypeWithButton {
                id: headerContent
                objectName: "headerContent"

                Layout.fillWidth: true
                Layout.leftMargin: 16
                Layout.rightMargin: 16
                Layout.bottomMargin: 10

                actionButtonImage: "qrc:/images/controls/edit-3.svg"

                headerText: root.processedServer.name
                descriptionText: root.processedServer.serverDescription !== "" ? root.processedServer.serverDescription : ApiAccountInfoModel.data("serviceDescription")

                actionButtonFunction: function() {
                    serverNameEditDrawer.openTriggered()
                }
            }
        }

        delegate: ColumnLayout {
            width: listView.width
            spacing: 0

            Connections {
                target: ApiAccountInfoModel

                function onModelReset() {
                    delegateItem.rightText = ApiAccountInfoModel.data(contentKey)
                }
            }

            LabelWithImageType {
                id: delegateItem

                Layout.fillWidth: true
                Layout.margins: 16

                imageSource: objectImageSource
                leftText: title
                rightText: ApiAccountInfoModel.data(contentKey)
                rightTextFormat: isRichText ? Text.RichText : Text.PlainText

                visible: rightText !== ""
            }
        }

        footer: ColumnLayout {
            id: footer

            width: listView.width
            spacing: 0

            readonly property bool isVisibleForAmneziaFree: ApiAccountInfoModel.data("isComponentVisible")

            WarningType {
                id: warning

                Layout.topMargin: 32
                Layout.rightMargin: 16
                Layout.leftMargin: 16
                Layout.fillWidth: true

                backGroundColor: DopamineStyle.color.translucentRichBrown

                textString: qsTr("Configurations have been updated for some countries. Download and install the updated configuration files")

                iconPath: "qrc:/images/controls/alert-circle.svg"

                visible: {
                    for (let i = 0; i < ApiCountryModel.count; ++i) {
                        if (ApiCountryModel.get(i).isWorkerExpired)
                            return true;
                    }
                    return false;
                }
            }

            // only what a customer needs: no addresses, DNS, MTU, tunnel IP or
            // config exports here (the logs carry the technical details)
            LabelWithImageType {
                Layout.fillWidth: true
                Layout.margins: 16

                imageSource: "qrc:/images/controls/map-pin.svg"
                leftText: qsTr("Country")
                rightText: {
                    var countryName = ServersModel.getProcessedServerData("countryName")
                    return countryName !== "" ? countryName : ServersModel.getProcessedServerData("countryCode")
                }
                visible: rightText !== ""
            }

            LabelWithImageType {
                Layout.fillWidth: true
                Layout.margins: 16

                imageSource: "qrc:/images/controls/settings.svg"
                leftText: qsTr("Protocol")
                rightText: {
                    var protocol = ("" + ServersModel.getProcessedServerData("serviceProtocol")).toLowerCase()
                    if (protocol === "awg" || protocol === "amneziawg") return "AmneziaWG"
                    if (protocol === "vless") return "VLESS Reality"
                    return protocol.toUpperCase()
                }
                visible: rightText !== ""
            }

            LabelWithImageType {
                Layout.fillWidth: true
                Layout.margins: 16

                imageSource: "qrc:/images/controls/gauge.svg"
                leftText: qsTr("Speed")
                rightText: "↓ " + ConnectionController.downloadSpeed + "   ↑ " + ConnectionController.uploadSpeed
                visible: ServersModel.processedIndex === ServersModel.defaultIndex
                         && ConnectionController.isConnected && ConnectionController.downloadSpeed !== ""
            }

            LabelWithImageType {
                Layout.fillWidth: true
                Layout.margins: 16

                imageSource: "qrc:/images/controls/gauge.svg"
                leftText: qsTr("Ping")
                rightText: ConnectionController.ping + " ms"
                visible: ServersModel.processedIndex === ServersModel.defaultIndex
                         && ConnectionController.isConnected
                         && ConnectionController.ping !== ""
                         && SettingsController.isServerPingTextVisible
            }

            DividerType {
                Layout.topMargin: 16
            }

            DividerType {
                visible: footer.isVisibleForAmneziaFree
            }

            LabelWithButtonType {
                Layout.fillWidth: true

                visible: footer.isVisibleForAmneziaFree

                text: qsTr("Active Devices")

                descriptionText: qsTr("Manage currently connected devices")
                rightImageSource: "qrc:/images/controls/chevron-right.svg"

                clickedFunction: function() {
                    ApiSettingsController.updateApiDevicesModel()
                    PageController.goToPage(PageEnum.PageSettingsApiDevices)
                }
            }

            DividerType {
                visible: footer.isVisibleForAmneziaFree
            }

            LabelWithButtonType {
                Layout.fillWidth: true
                Layout.topMargin: footer.isVisibleForAmneziaFree ? 0 : 32

                text: qsTr("Support")
                descriptionText: "lodestarvpn.com/support"
                rightImageSource: "qrc:/images/controls/chevron-right.svg"

                clickedFunction: function() {
                    Qt.openUrlExternally(LanguageModel.getCurrentSiteUrl("support"))
                }
            }

            DividerType {}

            LabelWithButtonType {
                Layout.fillWidth: true

                visible: footer.isVisibleForAmneziaFree

                text: qsTr("How to connect on another device")
                descriptionText: "lodestarvpn.com/setup"
                rightImageSource: "qrc:/images/controls/chevron-right.svg"

                clickedFunction: function() {
                    Qt.openUrlExternally(LanguageModel.getCurrentSiteUrl("setup"))
                }
            }

            DividerType {
                visible: footer.isVisibleForAmneziaFree
            }

            BasicButtonType {
                id: resetButton
                Layout.alignment: Qt.AlignHCenter
                Layout.topMargin: 24
                Layout.bottomMargin: 16
                implicitHeight: 32

                defaultColor: "transparent"
                hoveredColor: DopamineStyle.color.translucentWhite
                pressedColor: DopamineStyle.color.sheerWhite
                // not destructive: neutral, unlike unlink / remove below
                textColor: DopamineStyle.color.paleGray

                text: qsTr("Reload API config")

                clickedFunc: function() {
                    var headerText = qsTr("Reload API config?")
                    var yesButtonText = qsTr("Continue")
                    var noButtonText = qsTr("Cancel")

                    var yesButtonFunction = function() {
                        if (ServersModel.isDefaultServerCurrentlyProcessed() && ConnectionController.isConnected) {
                            PageController.showNotificationMessage(qsTr("Cannot reload API config during active connection"))
                        } else {
                            PageController.showBusyIndicator(true)
                            ApiConfigsController.updateServiceFromGateway(ServersModel.processedIndex, "", "", true)
                            PageController.showBusyIndicator(false)
                        }
                    }
                    var noButtonFunction = function() {
                    }

                    showQuestionDrawer(headerText, "", yesButtonText, noButtonText, yesButtonFunction, noButtonFunction)
                }
            }

            BasicButtonType {
                id: revokeButton
                Layout.alignment: Qt.AlignHCenter
                Layout.bottomMargin: 16
                implicitHeight: 32

                visible: footer.isVisibleForAmneziaFree

                defaultColor: "transparent"
                hoveredColor: DopamineStyle.color.translucentWhite
                pressedColor: DopamineStyle.color.sheerWhite
                textColor: DopamineStyle.color.vibrantRed

                text: qsTr("Unlink this device")

                clickedFunc: function() {
                    var headerText = qsTr("Are you sure you want to unlink this device?")
                    var descriptionText = qsTr("This will unlink the device from your subscription. You can reconnect it anytime by pressing \"Reload API config\" in subscription settings on device.")
                    var yesButtonText = qsTr("Continue")
                    var noButtonText = qsTr("Cancel")

                    var yesButtonFunction = function() {
                        if (ServersModel.isDefaultServerCurrentlyProcessed() && ConnectionController.isConnected) {
                            PageController.showNotificationMessage(qsTr("Cannot unlink device during active connection"))
                        } else {
                            PageController.showBusyIndicator(true)
                            if (ApiConfigsController.deactivateDevice(false)) {
                                ApiSettingsController.getAccountInfo(true, true)
                            }
                            PageController.showBusyIndicator(false)
                        }
                    }
                    var noButtonFunction = function() {
                    }

                    showQuestionDrawer(headerText, descriptionText, yesButtonText, noButtonText, yesButtonFunction, noButtonFunction)
                }
            }

            BasicButtonType {
                id: removeButton
                Layout.alignment: Qt.AlignHCenter
                Layout.bottomMargin: 16
                implicitHeight: 32

                defaultColor: "transparent"
                hoveredColor: DopamineStyle.color.translucentWhite
                pressedColor: DopamineStyle.color.sheerWhite
                textColor: DopamineStyle.color.vibrantRed

                text: qsTr("Remove from application")

                clickedFunc: function() {
                    var headerText = qsTr("Remove from application?")
                    var yesButtonText = qsTr("Continue")
                    var noButtonText = qsTr("Cancel")

                    var yesButtonFunction = function() {
                        if (ServersModel.isDefaultServerCurrentlyProcessed() && ConnectionController.isConnected) {
                            PageController.showNotificationMessage(qsTr("Cannot remove server during active connection"))
                        } else {
                            PageController.showBusyIndicator(true)
                            InstallController.removeProcessedServer()
                            PageController.showBusyIndicator(false)
                        }
                    }
                    var noButtonFunction = function() {
                    }

                    showQuestionDrawer(headerText, "", yesButtonText, noButtonText, yesButtonFunction, noButtonFunction)
                }
            }
        }
    }

    RenameServerDrawer {
        id: serverNameEditDrawer

        anchors.fill: parent
        expandedHeight: parent.height * 0.35

        serverNameText: root.processedServer.name
    }
}
