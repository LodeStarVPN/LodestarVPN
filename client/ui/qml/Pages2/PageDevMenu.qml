import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

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

    BackButtonType {
        id: backButton

        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.topMargin: 20 + SettingsController.safeAreaTopMargin
    }

    ListViewType {
        id: listView
        anchors.top: backButton.bottom
        anchors.bottom: parent.bottom
        anchors.right: parent.right
        anchors.left: parent.left

        header: ColumnLayout {
            width: listView.width

            BaseHeaderType {
                Layout.fillWidth: true
                Layout.rightMargin: 16
                Layout.leftMargin: 16

                headerText: "Dev menu"
            }
        }
        
        model: 1 // fake model to force the ListView to be created without a model

        spacing: 16

        delegate: ColumnLayout {
            width: listView.width

            TextFieldWithHeaderType {
                Layout.fillWidth: true
                Layout.topMargin: 16
                Layout.rightMargin: 16
                Layout.leftMargin: 16

                headerText: qsTr("Gateway endpoint")
                textField.text: SettingsController.gatewayEndpoint

                buttonImageSource: textField.text !== "" ? "qrc:/images/controls/refresh-cw.svg" : ""

                clickedFunc: function() {
                    SettingsController.resetGatewayEndpoint()
                }

                textField.onEditingFinished: {
                    textField.text = textField.text.replace(/^\s+|\s+$/g, '')
                    if (textField.text !== SettingsController.gatewayEndpoint) {
                        SettingsController.gatewayEndpoint = textField.text
                    }
                }
            }
        }

        footer: ColumnLayout {
            width: listView.width

            SwitcherType {
                Layout.fillWidth: true
                Layout.topMargin: 24
                Layout.rightMargin: 16
                Layout.leftMargin: 16

                text: qsTr("Dev gateway environment")
                checked: SettingsController.isDevGatewayEnv
                onToggled: function() {
                    SettingsController.isDevGatewayEnv = checked
                }
            }

            // the update's sheet and home card through a whole made-up update (nothing is
            // fetched or installed, the VPN is left alone): to look at them without a release
            BasicButtonType {
                Layout.fillWidth: true
                Layout.topMargin: 24
                Layout.rightMargin: 16
                Layout.leftMargin: 16

                text: "Update demo"

                clickedFunc: function() {
                    UpdateController.startDemo(false)
                    PageController.goToPageHome()
                    showUpdateDrawer()
                }
            }

            BasicButtonType {
                Layout.fillWidth: true
                Layout.topMargin: 12
                Layout.rightMargin: 16
                Layout.leftMargin: 16

                text: "Update demo: the download breaks off"

                clickedFunc: function() {
                    UpdateController.startDemo(true)
                    PageController.goToPageHome()
                    showUpdateDrawer()
                }
            }
        }
    }
}
