import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtQuick.Dialogs

import QtCore

import SortFilterProxyModel 0.2

import PageEnum 1.0
import ProtocolEnum 1.0
import ContainerProps 1.0
import Style 1.0

import "./"
import "../Controls2"
import "../Controls2/TextTypes"
import "../Config"
import "../Components"

// open while connected as the site list is: the apps go to the tunnel on the next connect (the
// sheet's switch over this list never waited for a disconnect either)
PageType {
    id: root

    QtObject {
        id: routeMode
        property int allApps: 0
        property int onlyForwardApps: 1
        property int allExceptApps: 2
    }

    property list<QtObject> routeModesModel: [
        onlyForwardApps,
        allExceptApps
    ]

    QtObject {
        id: onlyForwardApps

        readonly property string name: qsTr("Only the apps from the list should have access via VPN")
        readonly property int type: routeMode.onlyForwardApps
    }

    QtObject {
        id: allExceptApps
        
        readonly property string name: qsTr("Apps from the list should not have access via VPN")
        readonly property int type: routeMode.allExceptApps
    }

    function getRouteModesModelIndex() {
        var currentRouteMode = AppSplitTunnelingModel.routeMode
        if ((routeMode.onlyForwardApps === currentRouteMode) || (routeMode.allApps === currentRouteMode)) {
            return 0
        } else if (routeMode.allExceptApps === currentRouteMode) {
            return 1
        }
    }

    ColumnLayout {
        id: header

        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right

        anchors.topMargin: 20 + SettingsController.safeAreaTopMargin

        BackButtonType {
            id: backButton
        }

        HeaderTypeWithSwitcher {
            Layout.fillWidth: true
            Layout.leftMargin: 16
            Layout.rightMargin: 16

            headerText: qsTr("App split tunneling")

            showSwitcher: true
            switcher {
                checked: AppSplitTunnelingModel.isTunnelingEnabled
            }
            switcherFunction: function(checked) {
                AppSplitTunnelingModel.toggleSplitTunneling(checked)
                selector.text = root.routeModesModel[getRouteModesModelIndex()].name
            }
        }

        CaptionTextType {
            Layout.fillWidth: true
            Layout.topMargin: 8
            Layout.leftMargin: 16
            Layout.rightMargin: 16

            visible: ConnectionController.isConnected
            color: DopamineStyle.color.mutedGray
            text: qsTr("VPN is connected — changes will apply on the next connection")
        }

        DropDownType {
            id: selector

            Layout.fillWidth: true
            Layout.topMargin: 32
            Layout.leftMargin: 16
            Layout.rightMargin: 16

            drawerHeight: 0.4375
            drawerParent: root

            headerText: qsTr("Mode")

            // only Android can switch modes: elsewhere the warning below says
            // which one works, and a locked drop-down only took list space
            visible: Qt.platform.os === "android"
            enabled: Qt.platform.os === "android"

            listView: ListViewWithRadioButtonType {
                rootWidth: root.width

                model: root.routeModesModel

                selectedIndex: getRouteModesModelIndex()

                clickedFunction: function() {
                    selector.text = selectedText
                    selector.closeTriggered()
                    if (AppSplitTunnelingModel.routeMode !== root.routeModesModel[selectedIndex].type) {
                        AppSplitTunnelingModel.routeMode = root.routeModesModel[selectedIndex].type
                    }
                }

                Component.onCompleted: {
                    if (root.routeModesModel[selectedIndex].type === AppSplitTunnelingModel.routeMode) {
                        selector.text = selectedText
                    } else {
                        selector.text = root.routeModesModel[0].name
                    }
                }

                Connections {
                    target: AppSplitTunnelingModel
                    function onRouteModeChanged() {
                        selectedIndex = getRouteModesModelIndex()
                    }
                }
            }
        }

        WarningType {
            Layout.fillWidth: true
            Layout.topMargin: selector.visible ? 8 : 32
            Layout.leftMargin: 16
            Layout.rightMargin: 16

            textString: qsTr("Only \"Apps from the list should not have access via VPN\" mode is available on Windows")
            iconPath: "qrc:/images/controls/alert-circle.svg"

            visible: Qt.platform.os === "windows"
        }
    }

    ListViewType {
        id: listView

        ScrollBar.vertical: ScrollBarType {}

        anchors.top: header.bottom
        anchors.bottom: parent.bottom
        anchors.bottomMargin: addAppButton.implicitHeight + 48 + SettingsController.safeAreaBottomMargin + (searchField.textField.activeFocus ? 0 : SettingsController.imeHeight)
        anchors.left: parent.left
        anchors.right: parent.right
        clip: true

        model: SortFilterProxyModel {
            id: proxyAppSplitTunnelingModel
            sourceModel: AppSplitTunnelingModel
            filters: RegExpFilter {
                roleName: "appPath"
                pattern: ".*" + searchField.textField.text + ".*"
                caseSensitivity: Qt.CaseInsensitive
            }
            sorters: [
                RoleSorter { roleName: "appPath"; sortOrder: Qt.AscendingOrder }
            ]
        }

        delegate: ColumnLayout {
            width: listView.width

            // the apps: one glass card down the list
            LabelWithButtonType {
                Layout.fillWidth: true
                glass: listView.count === 1 ? "single" : index === 0 ? "first" : index === listView.count - 1 ? "last" : "middle"

                text: appPath
                rightImageSource: "qrc:/images/controls/trash.svg"
                rightImageColor: DopamineStyle.color.paleGray

                clickedFunction: function() {
                    var headerText = qsTr("Remove ") + appPath + "?"
                    var yesButtonText = qsTr("Continue")
                    var noButtonText = qsTr("Cancel")

                    var yesButtonFunction = function() {
                        AppSplitTunnelingController.removeApp(proxyAppSplitTunnelingModel.mapToSource(index))
                    }
                    var noButtonFunction = function() {
                    }

                    showQuestionDrawer(headerText, "", yesButtonText, noButtonText, yesButtonFunction, noButtonFunction)
                }
            }
        }
    }

    Rectangle {
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        
        height: addAppButton.implicitHeight + 48 + SettingsController.safeAreaBottomMargin
        
        // the night at the page's bottom edge, fading in over the list's last rows: a flat band stood
        // out of the sky's gradient as a step
        gradient: Gradient {
            GradientStop { position: 0.0; color: "#0010173A" }
            GradientStop { position: 0.45; color: DopamineStyle.color.nightBottom }
            GradientStop { position: 1.0; color: DopamineStyle.color.nightBottom }
        }
        
        RowLayout {
            id: addAppButton

            anchors.bottom: parent.bottom
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.topMargin: 24
            anchors.rightMargin: 16
            anchors.leftMargin: 16
            anchors.bottomMargin: 24 + SettingsController.safeAreaBottomMargin

            TextFieldWithHeaderType {
                id: searchField

                Layout.fillWidth: true

                textField.placeholderText: qsTr("application name")
                buttonImageSource: "qrc:/images/controls/plus.svg"

                rightButtonClickedOnEnter: true

                clickedFunc: function() {
                    searchField.focus = false
                    PageController.showBusyIndicator(true)

                    if (Qt.platform.os === "windows") {
                        var fileName = SystemController.getFileName(qsTr("Select the application's .exe file"),
                                                                    qsTr("Programs (*.exe)"))
                        if (fileName !== "") {
                            AppSplitTunnelingController.addApp(fileName)
                        }
                    } else if (Qt.platform.os === "android"){
                        installedAppDrawer.openTriggered()
                    }

                    PageController.showBusyIndicator(false)
                }
            }
        }
    }

    InstalledAppsDrawer {
        id: installedAppDrawer

        anchors.fill: parent
    }
}
