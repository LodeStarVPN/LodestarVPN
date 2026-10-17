import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

import PageEnum 1.0
import Style 1.0

import "./"
import "../Controls2"
import "../Controls2/TextTypes"
import "../Config"
import "../Components"

// Split tunneling as a whole: Russian sites, sites and services, apps - a page of its own that the
// button under the home card and the entry in the settings both open (the owner, 2026-10-17: «должна
// быть отдельной вкладкой а не выплывающей менюшкой»; it was a sheet over either before)
PageType {
    id: root

    property bool isAppSplitTinnelingEnabled: Qt.platform.os === "windows" || Qt.platform.os === "android"

    // a switch row of a glass card (GlassColumn), lit by the ring's blue while on
    component ToggleCard: Item {
        id: card

        property alias checked: toggle.checked
        property alias text: toggle.text
        property alias descriptionText: toggle.descriptionText
        property string glass: ""
        signal toggled(bool checked)

        Layout.fillWidth: true

        implicitHeight: toggle.implicitHeight + 32

        GlassSegment {
            anchors.fill: parent

            position: card.glass !== "" ? card.glass : "single"
            pressed: toggle.tapPressed
            lit: toggle.checked
        }

        SwitcherType {
            id: toggle

            anchors.left: parent.left
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            anchors.leftMargin: 32
            anchors.rightMargin: 32

            onToggled: function() {
                card.toggled(checked)
            }
        }
    }

    // a route selector in a glass card, between its rows
    component DropDownCard: Item {
        id: dropCard

        property alias filterModel: dropDown.filterModel
        property alias currentValue: dropDown.currentValue
        property string glass: ""
        signal selected(string value)

        Layout.fillWidth: true

        implicitHeight: dropDown.implicitHeight + 8

        GlassSegment {
            anchors.fill: parent

            position: dropCard.glass !== "" ? dropCard.glass : "single"
        }

        FilterDropDown {
            id: dropDown

            anchors.left: parent.left
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            anchors.leftMargin: 32
            anchors.rightMargin: 32

            onSelected: function(value) {
                dropCard.selected(value)
            }
        }
    }

    FlickableType {
        id: fl

        anchors.fill: parent
        // the column starts under the status bar and ends over the navigation bar
        contentHeight: content.anchors.topMargin + content.implicitHeight + 24 + SettingsController.safeAreaBottomMargin

        ColumnLayout {
            id: content

            anchors.top: parent.top
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.topMargin: 20 + SettingsController.safeAreaTopMargin

            spacing: 0

            BackButtonType {
                id: backButton
            }

            BaseHeaderType {
                Layout.fillWidth: true
                Layout.leftMargin: 16
                Layout.rightMargin: 16
                Layout.bottomMargin: 16

                headerText: qsTr("Split tunneling")
                descriptionText: qsTr("Allows you to connect to some sites or applications through a VPN connection and bypass others")
            }

            LabelWithButtonType {
                id: splitTunnelingSwitch
                Layout.fillWidth: true
                Layout.bottomMargin: 16

                visible: ServersModel.isDefaultServerDefaultContainerHasSplitTunneling
                glass: "single"

                text: qsTr("Split tunneling on the server")
                descriptionText: qsTr("Enabled \nCan't be disabled for current server")
                rightImageSource: "qrc:/images/controls/chevron-right.svg"

                clickedFunction: function() {
                    PageController.goToPage(PageEnum.PageSettingsSplitTunneling)
                }
            }

            // --- Russian sites: past the VPN unless turned off (the head of
            // the gateway's order of Russian networks, DirectNetworks) ---

            ToggleCard {
                id: ruDirectToggle

                glass: "single"

                text: qsTr("Russian sites directly")
                descriptionText: qsTr("They open without the VPN: faster, and banks and public services work as usual")
                checked: SettingsController.isRuDirectEnabled

                onToggled: function(checked) {
                    SettingsController.isRuDirectEnabled = checked
                    // connected already: the change takes effect at once
                    if (ConnectionController.isConnected) {
                        ConnectionController.openConnection()
                    }
                }
            }

            // --- sites & services: one switch, one direction (presets are
            // exceptions to the sites mode), separate lists ---

            GlassColumn {
                Layout.fillWidth: true
                Layout.topMargin: 16

                ToggleCard {
                    id: sitesToggle

                    text: qsTr("Site and service split tunneling")
                    checked: SitesModel.isTunnelingEnabled

                    onToggled: function(checked) {
                        SitesModel.toggleSplitTunneling(checked)
                    }
                }

                DropDownCard {
                    visible: SitesModel.isTunnelingEnabled

                    filterModel: sitesRouteModeModel
                    currentValue: SitesModel.routeMode === 2 ? "bypass" : "via"

                    onSelected: function(value) {
                        SitesModel.routeMode = value === "bypass" ? 2 : 1
                    }
                }

                LabelWithButtonType {
                    Layout.fillWidth: true

                    text: qsTr("Manage the site list")
                    rightImageSource: "qrc:/images/controls/chevron-right.svg"

                    clickedFunction: function() {
                        PageController.goToPage(PageEnum.PageSettingsSplitTunneling)
                    }
                }

                LabelWithButtonType {
                    Layout.fillWidth: true

                    text: qsTr("Manage the service list")
                    descriptionText: SplitPresetsModel.enabledCount > 0 ? qsTr("Enabled") : qsTr("Disabled")
                    rightImageSource: "qrc:/images/controls/chevron-right.svg"

                    clickedFunction: function() {
                        PageController.goToPage(PageEnum.PageSettingsSplitPresets)
                    }
                }
            }

            // --- apps: own switch + own direction ---

            GlassColumn {
                Layout.fillWidth: true
                Layout.topMargin: 16

                visible: root.isAppSplitTinnelingEnabled

                ToggleCard {
                    id: appsToggle

                    visible: root.isAppSplitTinnelingEnabled

                    text: qsTr("App-based split tunneling")
                    checked: AppSplitTunnelingModel.isTunnelingEnabled

                    onToggled: function(checked) {
                        AppSplitTunnelingModel.toggleSplitTunneling(checked)
                    }
                }

                DropDownCard {
                    // Windows supports app exclusions only (WFP driver); both
                    // directions work on Android
                    visible: root.isAppSplitTinnelingEnabled && AppSplitTunnelingModel.isTunnelingEnabled
                             && Qt.platform.os === "android"

                    filterModel: appsRouteModeModel
                    currentValue: AppSplitTunnelingModel.routeMode === 2 ? "bypass" : "via"

                    onSelected: function(value) {
                        AppSplitTunnelingModel.routeMode = value === "bypass" ? 2 : 1
                    }
                }

                LabelWithButtonType {
                    id: appSplitTunnelingSwitch
                    visible: root.isAppSplitTinnelingEnabled

                    Layout.fillWidth: true

                    text: qsTr("Manage the app list")
                    rightImageSource: "qrc:/images/controls/chevron-right.svg"

                    clickedFunction: function() {
                        PageController.goToPage(PageEnum.PageSettingsAppSplitTunneling)
                    }
                }
            }
        }
    }

    ListModel {
        id: sitesRouteModeModel
    }

    ListModel {
        id: appsRouteModeModel
    }

    Component.onCompleted: {
        sitesRouteModeModel.append({ "name": qsTr("via VPN"), "value": "via" })
        sitesRouteModeModel.append({ "name": qsTr("bypass VPN"), "value": "bypass" })
        appsRouteModeModel.append({ "name": qsTr("via VPN"), "value": "via" })
        appsRouteModeModel.append({ "name": qsTr("bypass VPN"), "value": "bypass" })
    }
}
