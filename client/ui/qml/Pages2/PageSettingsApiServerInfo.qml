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
    // what a new device is added by; shown as dots until asked for
    property string subscriptionKey: ""

    Component.onCompleted: {
        root.subscriptionKey = ApiConfigsController.processedSubscriptionKey()
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
            root.subscriptionKey = ApiConfigsController.processedSubscriptionKey()
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

    // A plain column that scrolls, not a list. An empty ListView with all of it in its footer went
    // back to its top at every change of the footer's height - with the VPN on the ping and speed
    // rows change it every few seconds, and the page jumped up while it was read (the owner,
    // 2026-10-17); a one-item ListView in its place lost the app's own objects in its item (the
    // country, the protocol, Active Devices and How to connect came out empty in 1.0.22). A
    // Flickable keeps its place when its content changes height
    FlickableType {
        id: fl

        anchors.fill: parent
        // the column starts under the status bar and ends over the navigation bar
        contentHeight: content.anchors.topMargin + content.implicitHeight + SettingsController.safeAreaBottomMargin

        ColumnLayout {
            id: content

            anchors.top: parent.top
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.topMargin: 20 + SettingsController.safeAreaTopMargin

            spacing: 0

            readonly property bool isVisibleForAmneziaFree: ApiAccountInfoModel.data("isComponentVisible")

            BackButtonType {
                id: backButton
                objectName: "backButton"
            }

            HeaderTypeWithButton {
                id: headerContent
                objectName: "headerContent"

                Layout.fillWidth: true
                Layout.topMargin: 4
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

            // what the subscription is and where this device goes, in one glass card.
            // Only what a customer needs: no addresses, DNS, MTU, tunnel IP or
            // config exports here (the logs carry the technical details)
            GlassColumn {
                Layout.fillWidth: true
                Layout.topMargin: 8

                Repeater {
                    model: root.labelsModel

                    LabelWithImageType {
                        id: accountRow

                        Layout.fillWidth: true

                        imageSource: modelData.objectImageSource
                        leftText: modelData.title
                        rightText: ApiAccountInfoModel.data(modelData.contentKey)
                        rightTextFormat: modelData.isRichText ? Text.RichText : Text.PlainText

                        visible: rightText !== ""

                        Connections {
                            target: ApiAccountInfoModel

                            function onModelReset() {
                                accountRow.rightText = ApiAccountInfoModel.data(modelData.contentKey)
                            }
                        }
                    }
                }

                LabelWithImageType {
                    Layout.fillWidth: true

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

                    imageSource: "qrc:/images/controls/gauge.svg"
                    leftText: qsTr("Speed")
                    // one direction per line: the two values never squeeze the title
                    rightText: "↓ " + ConnectionController.downloadSpeed + "
↑ " + ConnectionController.uploadSpeed
                    visible: ServersModel.processedIndex === ServersModel.defaultIndex
                             && ConnectionController.isConnected && ConnectionController.downloadSpeed !== ""
                }

                LabelWithImageType {
                    Layout.fillWidth: true

                    imageSource: "qrc:/images/controls/history.svg"
                    leftText: qsTr("Ping")
                    // the row stays while the VPN is on: a round of probes that got no answer clears
                    // the figure, and a row that came and went moved the page under the finger
                    rightText: ConnectionController.ping !== "" ? qsTr("%1 ms").arg(ConnectionController.ping) : "—"
                    visible: ServersModel.processedIndex === ServersModel.defaultIndex
                             && ConnectionController.isConnected
                             && SettingsController.isServerPingTextVisible
                }
            }

            GlassColumn {
                Layout.fillWidth: true
                Layout.topMargin: 16

                LabelWithButtonType {
                    Layout.fillWidth: true

                    visible: content.isVisibleForAmneziaFree

                    text: qsTr("Active Devices")

                    descriptionText: qsTr("Manage currently connected devices")
                    rightImageSource: "qrc:/images/controls/chevron-right.svg"

                    clickedFunction: function() {
                        ApiSettingsController.updateApiDevicesModel()
                        PageController.goToPage(PageEnum.PageSettingsApiDevices)
                    }
                }

                DividerType {
                    visible: content.isVisibleForAmneziaFree
                }

                LabelWithButtonType {
                    Layout.fillWidth: true

                    text: qsTr("Support")
                    descriptionText: "lodestarvpn.com/support"
                    rightImageSource: "qrc:/images/controls/chevron-right.svg"

                    clickedFunction: function() {
                        Qt.openUrlExternally(LanguageModel.getCurrentSiteUrl("support"))
                    }
                }
            }

            // The subscription's key: the only thing a new device needs. It is the
            // whole access to the subscription, so it stays behind dots until the
            // eye is pressed (screens get photographed and shown); a tap on the
            // row copies it either way.
            LabelWithButtonType {
                id: subscriptionKeyRow

                Layout.fillWidth: true
                Layout.topMargin: 16

                visible: root.subscriptionKey !== ""
                glass: "single"

                text: qsTr("Subscription key")
                descriptionText: root.subscriptionKey
                descriptionOnTop: true

                buttonImageSource: hideDescription ? "qrc:/images/controls/eye.svg" : "qrc:/images/controls/eye-off.svg"
                rightImageSource: "qrc:/images/controls/copy.svg"

                clickedFunction: function() {
                    GC.copyToClipBoard(root.subscriptionKey)
                    PageController.showNotificationMessage(qsTr("Subscription key copied"))
                }
            }

            CaptionTextType {
                Layout.fillWidth: true
                Layout.topMargin: 10
                Layout.leftMargin: 20
                Layout.rightMargin: 20
                Layout.bottomMargin: 16

                visible: subscriptionKeyRow.visible

                color: DopamineStyle.color.mutedGray
                text: qsTr("To add a new device, enter this key in the app on it")
            }

            LabelWithButtonType {
                Layout.fillWidth: true

                visible: content.isVisibleForAmneziaFree
                glass: "single"

                // told here, not on a site (the owner's word, 2026-10-17)
                text: qsTr("How to connect on another device")
                descriptionText: qsTr("Windows, Android, iPhone, iPad, Mac")
                rightImageSource: "qrc:/images/controls/chevron-right.svg"

                clickedFunction: function() {
                    PageController.goToPage(PageEnum.PageSettingsApiInstructions)
                }
            }

            // no buttons here: configs refresh by themselves (app start, every
            // few hours, after a failed connect) and devices are unlinked in
            // Active Devices (a computer handed on: uninstall the app, unlink
            // it there from another device; the app then drops the subscription)
            Item {
                Layout.preferredHeight: 24
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
