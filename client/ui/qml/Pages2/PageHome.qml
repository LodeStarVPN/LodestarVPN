import QtQuick
import QtQuick.Window
import QtQuick.Controls
import QtQuick.Layouts

import SortFilterProxyModel 0.2

import PageEnum 1.0
import ProtocolEnum 1.0
import ContainerProps 1.0
import ContainersModelFilters 1.0
import Style 1.0
import UpdateEnum 1.0

import "./"
import "../Controls2"
import "../Controls2/TextTypes"
import "../Config"
import "../Components"

PageType {
    id: root

    // the land's dark at the bottom edge (shaders/homeland.frag)
    navigationBarColor: 0xFF02040B

    // the night over the hills, the telescope on the near one aiming at the circle
    HomeScene {
        id: homeScene

        anchors.fill: parent

        button: connectButton
        circle: Qt.point(homeColumn.x + connectButton.x + connectButton.width / 2,
                         homeColumn.y + connectButton.y + connectButton.height / 2)
        cardTop: homeColumn.y + serverCard.y
    }

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
        imageColor: "#8A93B2"

        onClicked: PageController.goToPage(PageEnum.PageSettings)
    }

    Item {
        objectName: "homeColumnItem"

        anchors.fill: parent

        ColumnLayout {
            id: homeColumn
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

                // its sky is the eye of the telescope on the hill
                eyeAngle: homeScene.angle
                eyeAim: homeScene.aim
                eyeRest: homeScene.rest
                eyeRate: homeScene.angleRate
                eyeReady: homeScene.ready

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

                // one height connected or not: the land of HomeScene stands on its top,
                // the circle above is centred in what is left; the figures fade in
                implicitHeight: 96
                radius: 16

                // glass over the land: a cool tint, a faint edge
                gradient: Gradient {
                    GradientStop { position: 0; color: serverCardMouse.containsPress ? "#297892FF" : "#177892FF" }
                    GradientStop { position: 1; color: serverCardMouse.containsPress ? "#1A7892FF" : "#0D7892FF" }
                }
                border.width: 1
                border.color: "#17A9C1FF"

                // the landed star's light from above, coming with its wave
                Image {
                    anchors.fill: parent

                    source: "qrc:/images/home/card_light.png"
                    smooth: true
                    opacity: homeScene.cardLight
                    visible: opacity > 0
                }

                Rectangle {
                    x: parent.width * 0.1
                    width: parent.width * 0.8
                    height: 1

                    gradient: Gradient {
                        orientation: Gradient.Horizontal
                        GradientStop { position: 0; color: "#00BED2FF" }
                        GradientStop { position: 0.5; color: "#E6CEDEFF" }
                        GradientStop { position: 1; color: "#00BED2FF" }
                    }
                    opacity: homeScene.cardEdge
                    visible: opacity > 0
                }

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
                            color: "#E9EDFB"

                            text: SettingsController.autoServerSelection && !ConnectionController.isConnected
                                  ? qsTr("Auto-select")
                                  : ServersModel.defaultServerName
                        }

                        CaptionTextType {
                            Layout.fillWidth: true

                            visible: text !== ""
                            color: "#8A93B2"
                            font.pixelSize: 14
                            maximumLineCount: 1
                            elide: Text.ElideRight
                            wrapMode: Text.NoWrap

                            text: ServersModel.defaultServerProtocolName
                        }

                        // the figures come in once the wave from the landed star reaches the
                        // card, and go as it leaves (HomeScene)
                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 6

                            opacity: homeScene.figures

                            CaptionTextType {
                                Layout.fillWidth: true
                                Layout.minimumWidth: 80

                                color: "#8A93B2"
                                font.pixelSize: 13
                                wrapMode: Text.NoWrap
                                elide: Text.ElideRight
                                maximumLineCount: 1

                                // each figure with its unit: "↓ 81 МБ/с  ↑ 1,9 МБ/с"
                                text: ConnectionController.speedLine
                            }

                            Rectangle {
                                Layout.alignment: Qt.AlignVCenter
                                width: 6
                                height: 6
                                radius: 3

                                visible: ConnectionController.ping !== ""

                                color: {
                                    const ms = Number(ConnectionController.ping)
                                    return ms < 120 ? "#5FD497" : (ms < 300 ? "#FF9F0A" : "#FF453A")
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
                                    return ms < 120 ? "#9FE0BC" : (ms < 300 ? "#FF9F0A" : "#FF453A")
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
                // the update card takes this room when it is shown: the ring above keeps its size
                Layout.bottomMargin: updateCard.visible ? 8 : 80
                leftPadding: 16
                rightPadding: 16

                implicitHeight: 36

                defaultColor: DopamineStyle.color.transparent
                hoveredColor: DopamineStyle.color.translucentWhite
                pressedColor: DopamineStyle.color.sheerWhite
                disabledColor: DopamineStyle.color.transparent
                // the night's grey, as on the card above
                textColor: "#8A93B2"
                borderWidth: 0

                buttonTextLabel.lineHeight: 20
                buttonTextLabel.font.pixelSize: 14
                buttonTextLabel.font.weight: 500

                property bool isSplitTunnelingEnabled: SitesModel.isTunnelingEnabled || AppSplitTunnelingModel.isTunnelingEnabled ||
                                                       ServersModel.isDefaultServerDefaultContainerHasSplitTunneling

                text: qsTr("Split tunneling")

                leftImageSource: isSplitTunnelingEnabled ? "qrc:/images/controls/split-tunneling.svg" : ""
                leftImageColor: ""
                // a page of its own, the settings entry's too (it was a sheet over the home screen)
                rightImageSource: "qrc:/images/controls/chevron-right.svg"

                Keys.onEnterPressed: this.clicked()
                Keys.onReturnPressed: this.clicked()

                onClicked: {
                    PageController.goToPage(PageEnum.PageSettingsSplit)
                }
            }

            // a published update: its sheet on a tap; the offer itself can be put away (×) for
            // this version. A strip of the update sheet's night sky (UpdateSky): what is going
            // on and how much has come, the route into the lodestar under the percent
            Item {
                id: updateCard
                objectName: "updateCard"

                property bool isFocusable: true

                readonly property int updateState: UpdateController.state
                readonly property int updateFailure: UpdateController.failure

                readonly property string title: {
                    switch (updateState) {
                    case UpdateEnum.Downloading:
                        return UpdateController.progress >= 1 ? qsTr("Checking the file") : qsTr("Downloading the update")
                    case UpdateEnum.ReadyToInstall:
                        return qsTr("The update is ready")
                    case UpdateEnum.WaitingPermission:
                        return qsTr("Allow updates")
                    case UpdateEnum.Installing:
                        return qsTr("Installing")
                    case UpdateEnum.Failed:
                        return updateFailure === UpdateEnum.Network || updateFailure === UpdateEnum.Corrupt
                                ? qsTr("Couldn't download") : qsTr("The update didn't go through")
                    }
                    return qsTr("Version %1 is available").arg("<font color=\"#A9C1FF\">" + UpdateController.availableVersion + "</font>")
                }

                // how much has come, or what the sheet will do
                readonly property string action: {
                    switch (updateState) {
                    case UpdateEnum.Downloading:
                        return Math.floor(UpdateController.progress * 100) + "%"
                    case UpdateEnum.ReadyToInstall:
                        return qsTr("Install")
                    case UpdateEnum.Failed:
                        return updateFailure === UpdateEnum.BlockedBySystem ? "" : qsTr("Retry")
                    }
                    return ""
                }

                Layout.fillWidth: true
                Layout.leftMargin: 16
                Layout.rightMargin: 16
                // edge to edge (Android 14+): clear of the system navigation bar
                Layout.bottomMargin: Math.max(12, SettingsController.safeAreaBottomMargin)

                implicitHeight: 64

                visible: UpdateController.homeCardVisible

                Keys.onTabPressed: FocusController.nextKeyTabItem()
                Keys.onBacktabPressed: FocusController.previousKeyTabItem()
                Keys.onUpPressed: FocusController.nextKeyUpItem()
                Keys.onDownPressed: FocusController.nextKeyDownItem()
                Keys.onLeftPressed: FocusController.nextKeyLeftItem()
                Keys.onRightPressed: FocusController.nextKeyRightItem()
                Keys.onEnterPressed: showUpdateDrawer()
                Keys.onReturnPressed: showUpdateDrawer()

                UpdateSky {
                    anchors.fill: parent

                    card: true
                    running: updateCard.visible && Qt.application.state === Qt.ApplicationActive
                }

                Rectangle {
                    anchors.fill: parent

                    visible: updateCard.activeFocus
                    radius: 13
                    color: "transparent"
                    border.width: 2
                    border.color: "#C9D1EA"
                }

                // under the texts: the × button takes its own taps
                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor

                    onClicked: showUpdateDrawer()
                }

                Text {
                    anchors.left: parent.left
                    anchors.right: updateCardAction.visible ? updateCardAction.left : updateCardCloseButton.left
                    anchors.top: parent.top
                    anchors.leftMargin: 16
                    anchors.rightMargin: 12
                    anchors.topMargin: 11

                    font.family: "IBM Plex Mono"
                    font.pixelSize: 14
                    font.weight: Font.Medium
                    lineHeight: 20
                    lineHeightMode: Text.FixedHeight
                    color: "#D5DBF0"
                    textFormat: Text.StyledText
                    elide: Text.ElideRight
                    maximumLineCount: 1

                    text: updateCard.title
                }

                Text {
                    id: updateCardAction

                    anchors.right: parent.right
                    anchors.top: parent.top
                    anchors.rightMargin: 16
                    anchors.topMargin: 11

                    visible: text !== ""

                    font.family: "IBM Plex Mono"
                    font.pixelSize: 15
                    font.weight: Font.Medium
                    font.features: { "tnum": 1 }
                    lineHeight: 20
                    lineHeightMode: Text.FixedHeight
                    color: updateCard.updateState === UpdateEnum.Failed ? "#8A93B2" : "#A9C1FF"

                    text: updateCard.action
                }

                // only the offer can be put away: a download on its way is cancelled in its sheet
                ImageButtonType {
                    id: updateCardCloseButton
                    objectName: "updateCardCloseButton"

                    anchors.right: parent.right
                    anchors.top: parent.top
                    anchors.rightMargin: 4
                    anchors.topMargin: 1

                    implicitWidth: 40
                    implicitHeight: 40

                    visible: updateCard.updateState === UpdateEnum.Available

                    image: "qrc:/images/controls/close.svg"
                    imageColor: "#8A93B2"

                    onClicked: UpdateController.dismissHomeCard()
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
