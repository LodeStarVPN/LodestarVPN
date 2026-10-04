import QtQuick
import QtQuick.Window
import QtQuick.Controls
import QtQuick.Layouts
import Qt5Compat.GraphicalEffects

import SortFilterProxyModel 0.2

import PageEnum 1.0
import ProtocolEnum 1.0
import ContainerProps 1.0
import ContainersModelFilters 1.0
import Style 1.0

import "./"
import "../Controls2"
import "../Controls2/TextTypes"
import "../Config"
import "../Components"

PageType {
    id: root

    ImageButtonType {
        id: settingsButton
        objectName: "settingsButton"

        anchors.top: parent.top
        anchors.right: parent.right
        anchors.topMargin: 12 + SettingsController.safeAreaTopMargin
        anchors.rightMargin: 12

        z: 10

        implicitWidth: 48
        implicitHeight: 48

        image: "qrc:/images/controls/settings.svg"
        imageColor: DopamineStyle.color.paleGray

        onClicked: PageController.goToPage(PageEnum.PageSettings)
    }

    Connections {
        target: Qt.application

        function onStateChanged() {
            if (Qt.application.state !== Qt.ApplicationActive) {
                if (homeSplitTunnelingDrawer.isOpened) {
                    homeSplitTunnelingDrawer.closeTriggered()
                }
            }
        }
    }

    Item {
        objectName: "homeColumnItem"

        anchors.fill: parent

        ColumnLayout {
            objectName: "homeColumnLayout"

            anchors.fill: parent
            anchors.topMargin: 12 + SettingsController.safeAreaTopMargin
            anchors.bottomMargin: 16

            BasicButtonType {
                id: loggingButton
                objectName: "loggingButton"

                property bool isLoggingEnabled: SettingsController.isLoggingEnabled

                Layout.alignment: Qt.AlignHCenter
                // centred on the settings gear beside it, styled like the
                // split tunneling button at the bottom
                Layout.topMargin: 6
                leftPadding: 12
                rightPadding: 12

                implicitHeight: 36

                defaultColor: DopamineStyle.color.transparent
                hoveredColor: DopamineStyle.color.translucentWhite
                pressedColor: DopamineStyle.color.sheerWhite
                // while the busy spinner disables the page it only dims, it
                // does not turn into a grey blob that hides its own text
                disabledColor: DopamineStyle.color.transparent
                textColor: DopamineStyle.color.mutedGray
                borderWidth: 0

                buttonTextLabel.lineHeight: 20
                buttonTextLabel.font.pixelSize: 14
                buttonTextLabel.font.weight: 500

                visible: isLoggingEnabled ? true : false
                text: qsTr("Diagnostic Mode Enabled")

                Keys.onEnterPressed: this.clicked()
                Keys.onReturnPressed: this.clicked()

                onClicked: {
                    PageController.goToPage(PageEnum.PageSettingsLogging)
                }
            }

            BasicButtonType {
                id: devGatewayButton
                objectName: "devGatewayButton"

                property bool isDevGatewayEnabled: SettingsController.isDevGatewayEnv

                Layout.alignment: Qt.AlignHCenter

                implicitHeight: 36

                defaultColor: DopamineStyle.color.transparent
                hoveredColor: DopamineStyle.color.translucentWhite
                pressedColor: DopamineStyle.color.sheerWhite
                disabledColor: DopamineStyle.color.mutedGray
                textColor: DopamineStyle.color.mutedGray
                borderWidth: 0

                visible: SettingsController.isDevModeEnabled && isDevGatewayEnabled
                text: qsTr("Dev gateway enabled")

                Keys.onEnterPressed: this.clicked()
                Keys.onReturnPressed: this.clicked()

                onClicked: {
                    PageController.goToPage(PageEnum.PageDevMenu)
                }
            }

            ConnectButton {
                id: connectButton
                objectName: "connectButton"

                Layout.fillHeight: true
                Layout.alignment: Qt.AlignCenter

                // desktop easter egg: right-click sends the star on a lap
                onRightClicked: connectButton.startTrip()
            }

            Rectangle {
                id: serverCard
                objectName: "serverCard"

                Layout.fillWidth: true
                Layout.leftMargin: 16
                Layout.rightMargin: 16
                Layout.bottomMargin: 8

                implicitHeight: ConnectionController.isConnected ? 112 : 96
                radius: 20

                // the ring above is centred in what is left: it glides with
                // the card instead of jumping 8 px when the state changes
                Behavior on implicitHeight {
                    NumberAnimation { duration: 300; easing.type: Easing.InOutSine }
                }

                color: serverCardMouse.containsPress ? DopamineStyle.color.sheerWhite
                                                     : DopamineStyle.color.translucentWhite

                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: 20
                    anchors.rightMargin: 12

                    ColumnLayout {
                        Layout.fillWidth: true
                        Layout.rightMargin: 56
                        spacing: 2

                        ListItemTitleType {
                            Layout.fillWidth: true

                            maximumLineCount: 1
                            elide: Text.ElideRight
                            wrapMode: Text.NoWrap
                            font.pixelSize: 24
                            font.weight: 600
                            // a 24 px line needs more than the type's 21.6
                            lineHeight: 30

                            text: SettingsController.autoServerSelection && !ConnectionController.isConnected
                                  ? qsTr("Auto-select")
                                  : ServersModel.defaultServerName
                        }

                        CaptionTextType {
                            Layout.fillWidth: true

                            visible: text !== ""
                            color: DopamineStyle.color.mutedGray
                            font.pixelSize: 14
                            maximumLineCount: 1
                            elide: Text.ElideRight
                            wrapMode: Text.NoWrap

                            text: ServersModel.defaultServerProtocolName
                        }

                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 6

                            visible: ConnectionController.isConnected

                            CaptionTextType {
                                Layout.fillWidth: true
                                Layout.minimumWidth: 80

                                color: DopamineStyle.color.mutedGray
                                font.pixelSize: 13
                                wrapMode: Text.NoWrap
                                elide: Text.ElideRight
                                maximumLineCount: 1

                                text: "↓ " + ConnectionController.downloadSpeed
                                      + "  ↑ " + ConnectionController.uploadSpeed
                            }

                            Rectangle {
                                Layout.alignment: Qt.AlignVCenter
                                width: 8
                                height: 8
                                radius: 4

                                visible: ConnectionController.ping !== ""

                                color: {
                                    const ms = Number(ConnectionController.ping)
                                    return ms < 120 ? "#34C759" : (ms < 300 ? "#FF9F0A" : "#FF453A")
                                }
                            }

                            CaptionTextType {
                                Layout.alignment: Qt.AlignVCenter

                                visible: SettingsController.isServerPingTextVisible
                                         && ConnectionController.ping !== ""
                                font.pixelSize: 13

                                text: qsTr("%1 ms").arg(ConnectionController.ping)
                                color: {
                                    const ms = Number(ConnectionController.ping)
                                    return ms < 120 ? "#34C759" : (ms < 300 ? "#FF9F0A" : "#FF453A")
                                }
                            }
                        }
                    }

                }

                MouseArea {
                    id: serverCardMouse

                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor

                    onClicked: PageController.goToPage(PageEnum.PageSettingsServersList)
                }

                ImageButtonType {
                    id: serverCardInfoButton
                    objectName: "serverCardInfoButton"

                    anchors.right: parent.right
                    anchors.rightMargin: 10
                    anchors.verticalCenter: parent.verticalCenter

                    implicitWidth: 56
                    implicitHeight: 56

                    image: "qrc:/images/controls/info.svg"
                    imageColor: DopamineStyle.color.mutedGray

                    onClicked: {
                        ServersModel.processedIndex = ServersModel.defaultIndex

                        if (ServersModel.getProcessedServerData("isServerFromGatewayApi")) {
                            PageController.showBusyIndicator(true)
                            let result = ApiSettingsController.getAccountInfo(false)
                            PageController.showBusyIndicator(false)
                            if (!result) {
                                return
                            }

                            PageController.goToPage(PageEnum.PageSettingsApiServerInfo)
                        } else {
                            PageController.goToPage(PageEnum.PageSettingsServerInfo)
                        }
                    }
                }
            }

            BasicButtonType {
                id: splitTunnelingButton
                objectName: "splitTunnelingButton"

                Layout.alignment: Qt.AlignHCenter | Qt.AlignBottom
                Layout.bottomMargin: 80
                leftPadding: 16
                rightPadding: 16

                implicitHeight: 36

                defaultColor: DopamineStyle.color.transparent
                hoveredColor: DopamineStyle.color.translucentWhite
                pressedColor: DopamineStyle.color.sheerWhite
                disabledColor: DopamineStyle.color.transparent
                textColor: DopamineStyle.color.mutedGray
                borderWidth: 0

                buttonTextLabel.lineHeight: 20
                buttonTextLabel.font.pixelSize: 14
                buttonTextLabel.font.weight: 500

                property bool isSplitTunnelingEnabled: SitesModel.isTunnelingEnabled || AppSplitTunnelingModel.isTunnelingEnabled ||
                                                       ServersModel.isDefaultServerDefaultContainerHasSplitTunneling

                text: qsTr("Split tunneling")

                leftImageSource: isSplitTunnelingEnabled ? "qrc:/images/controls/split-tunneling.svg" : ""
                leftImageColor: ""
                rightImageSource: "qrc:/images/controls/chevron-down.svg"

                Keys.onEnterPressed: this.clicked()
                Keys.onReturnPressed: this.clicked()

                onClicked: {
                    homeSplitTunnelingDrawer.openTriggered()
                }

                HomeSplitTunnelingDrawer {
                    id: homeSplitTunnelingDrawer
                    objectName: "homeSplitTunnelingDrawer"

                    parent: root
                }
            }

            AdLabel {
                id: adLabel

                Layout.fillWidth: true
                Layout.preferredHeight: adLabel.contentHeight
                Layout.leftMargin: 16
                Layout.rightMargin: 16
                Layout.topMargin: 22
            }

        }
    }

    Connections {
        target: PageController

        function onShakeDetected() {
            // defer out of the signal delivery path
            Qt.callLater(connectButton.startTrip)
        }
    }
}
