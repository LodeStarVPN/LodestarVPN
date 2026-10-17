import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtQuick.Dialogs

import PageEnum 1.0
import Style 1.0

import "./"
import "../Controls2"
import "../Controls2/TextTypes"
import "../Config"

PageType {
    id: root

    ListViewType {
        id: listView

        anchors.fill: parent

        header: ColumnLayout {
            width: listView.width

            RowLayout {
                Layout.fillWidth: true
                Layout.topMargin: 20 + SettingsController.safeAreaTopMargin
                // the gap goes under the whole row, so the back arrow stays
                // level with the title (as on the Connections page)
                Layout.bottomMargin: 16

                spacing: 0

                BackButtonType {
                    id: backButton
                }

                BaseHeaderType {
                    id: header
                    Layout.fillWidth: true
                    Layout.rightMargin: 16
                    Layout.leftMargin: 16

                    headerText: qsTr("Settings")
                }
            }
        }

        model: settingsEntries

        // the entries in glass cards: the settings in one, about and the dev console in another
        delegate: ColumnLayout {
            width: listView.width

            spacing: 0

            LabelWithButtonType {
                Layout.fillWidth: true
                Layout.topMargin: isVisible && index === root.firstVisible(card) && card > 0 ? 16 : 0

                visible: isVisible

                text: title
                rightImageSource: "qrc:/images/controls/chevron-right.svg"
                leftImageSource: leftImagePath

                glass: {
                    const first = root.firstVisible(card)
                    const last = root.lastVisible(card)
                    return index === first && index === last ? "single" : index === first ? "first"
                         : index === last ? "last" : "middle"
                }

                clickedFunction: clickedHandler
            }
        }

        footer: ColumnLayout {
            width: listView.width

            LabelWithButtonType {
                id: close

                visible: GC.isDesktop()
                Layout.fillWidth: true
                Layout.topMargin: 16

                text: qsTr("Close application")
                leftImageSource: "qrc:/images/controls/x-circle.svg"
                isLeftImageHoverEnabled: false
                glass: "single"

                clickedFunction: function() {
                    PageController.closeApplication()
                }
            }

            Text {
                Layout.alignment: Qt.AlignHCenter
                Layout.topMargin: 12
                Layout.bottomMargin: 16

                text: "v" + SettingsController.getAppVersion().split(" ")[0]
                color: DopamineStyle.color.mutedGray
                font.pixelSize: 13
                font.family: "IBM Plex Mono"
            }
        }
    }

    property list<QtObject> settingsEntries: [
        subscription,
        servers,
        splitTunneling,
        connection,
        application,
        about,
        devConsole
    ]

    // the first and the last entry shown in a card (an entry's card property)
    function firstVisible(card) {
        for (let i = 0; i < settingsEntries.length; i++) {
            if (settingsEntries[i].card === card && settingsEntries[i].isVisible) {
                return i
            }
        }
        return -1
    }

    function lastVisible(card) {
        for (let i = settingsEntries.length - 1; i >= 0; i--) {
            if (settingsEntries[i].card === card && settingsEntries[i].isVisible) {
                return i
            }
        }
        return -1
    }

    QtObject {
        id: subscription

        readonly property int card: 0

        // our subscription: its status and end date, devices, support - the
        // page the info button of the home screen's card opens too
        property string title: qsTr("Subscription")
        readonly property string leftImagePath: "qrc:/images/controls/tag.svg"
        property bool isVisible: ServersModel.hasServersFromGatewayApi
        readonly property var clickedHandler: function() {
            // the selected server if it is the subscription's, else its first one
            var rows = [ServersModel.defaultIndex]
            for (var i = 0; i < ServersModel.getServersCount(); ++i) {
                rows.push(i)
            }
            for (var j = 0; j < rows.length; ++j) {
                if (rows[j] < 0) {
                    continue
                }
                ServersModel.processedIndex = rows[j]
                if (ServersModel.getProcessedServerData("isServerFromGatewayApi")) {
                    PageController.showBusyIndicator(true)
                    var result = ApiSettingsController.getAccountInfo(false)
                    PageController.showBusyIndicator(false)
                    if (result) {
                        PageController.goToPage(PageEnum.PageSettingsApiServerInfo)
                    }
                    return
                }
            }
        }
    }

    QtObject {
        id: servers

        readonly property int card: 0

        property string title: qsTr("Connections")
        readonly property string leftImagePath: "qrc:/images/controls/server.svg"
        property bool isVisible: true
        readonly property var clickedHandler: function() {
            PageController.goToPage(PageEnum.PageSettingsServersList)
        }
    }

    QtObject {
        id: splitTunneling

        readonly property int card: 0

        // the very page of the button under the home card, under its name (the owner, 2026-10-17:
        // the Connection page held only the apps' part of it, named its own way; then «должна быть
        // отдельной вкладкой а не выплывающей менюшкой» - it was a sheet over the settings)
        property string title: qsTr("Split tunneling")
        readonly property string leftImagePath: "qrc:/images/controls/split.svg"
        property bool isVisible: true
        readonly property var clickedHandler: function() {
            PageController.goToPage(PageEnum.PageSettingsSplit)
        }
    }

    QtObject {
        id: connection

        readonly property int card: 0

        property string title: qsTr("Connection")
        readonly property string leftImagePath: "qrc:/images/controls/radio.svg"
        // LAN routing and KillSwitch: both desktop-only, the page is empty elsewhere
        property bool isVisible: GC.isDesktop()
        readonly property var clickedHandler: function() {
            PageController.goToPage(PageEnum.PageSettingsConnection)
        }
    }

    QtObject {
        id: application

        readonly property int card: 0

        property string title: qsTr("Application")
        readonly property string leftImagePath: "qrc:/images/controls/app.svg"
        property bool isVisible: true
        readonly property var clickedHandler: function() {
            PageController.goToPage(PageEnum.PageSettingsApplication)
        }
    }

    QtObject {
        id: about

        readonly property int card: 1

        property string title: qsTr("About LodestarVPN")
        readonly property string leftImagePath: "qrc:/images/controls/info.svg"
        property bool isVisible: true
        readonly property var clickedHandler: function() {
            PageController.goToPage(PageEnum.PageSettingsAbout)
        }
    }

    QtObject {
        id: devConsole

        readonly property int card: 1

        property string title: qsTr("Dev console")
        readonly property string leftImagePath: "qrc:/images/controls/bug.svg"
        property bool isVisible: SettingsController.isDevModeEnabled
        readonly property var clickedHandler: function() {
            PageController.goToPage(PageEnum.PageDevMenu)
        }
    }
}
