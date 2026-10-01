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

PageType {
    id: root

    SortFilterProxyModel {
        id: proxyApiServicesModel

        sourceModel: ApiServicesModel
        sorters: RoleSorter {
            roleName: "order"
            sortOrder: Qt.AscendingOrder
        }
    }

    BackButtonType {
        id: backButton

        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.topMargin: 20 + SettingsController.safeAreaTopMargin

        onActiveFocusChanged: {
            if(backButton.enabled && backButton.activeFocus) {
                listView.positionViewAtBeginning()
            }
        }
    }

    ListViewType {
        id: listView

        anchors.top: backButton.bottom
        anchors.right: parent.right
        anchors.left: parent.left
        anchors.bottom: parent.bottom
        anchors.topMargin: 16

        header: ColumnLayout {
            width: listView.width
            spacing: 16

            BaseHeaderType {
                Layout.fillWidth: true
                Layout.rightMargin: 16
                Layout.leftMargin: 16
                Layout.bottomMargin: 8

                headerText: qsTr("LodestarVPN")
                descriptionText: qsTr("Enter your subscription ID: the app will get your servers.")
            }

            TextFieldWithHeaderType {
                id: subscriptionIdField
                Layout.fillWidth: true
                Layout.rightMargin: 16
                Layout.leftMargin: 16
                Layout.bottomMargin: 16
                headerText: qsTr("Subscription ID")
                textField.placeholderText: qsTr("Paste or type it")
                buttonText: qsTr("Insert")

                clickedFunc: function() {
                    subscriptionIdField.insertFromClipboard()
                }

                textField.onTextChanged: {
                    ApiConfigsController.setSubscriptionId(textField.text.trim())
                    refreshTimer.restart()
                }

                Component.onCompleted: textField.text = ApiConfigsController.subscriptionId
            }
        }

        // the list shows what the gateway has for the entered ID: refresh it
        // once typing pauses
        Timer {
            id: refreshTimer

            interval: 600
            onTriggered: {
                if (ApiConfigsController.subscriptionId === "") {
                    return
                }
                PageController.showBusyIndicator(true)
                ApiConfigsController.fillAvailableServices()
                PageController.showBusyIndicator(false)
            }
        }

        spacing: 0

        // nothing to choose from until an ID is entered
        model: ApiConfigsController.subscriptionId === "" ? null : proxyApiServicesModel

        delegate: ColumnLayout {

            width: listView.width

            enabled: isServiceAvailable

            CardWithIconsType {
                id: card

                Layout.fillWidth: true
                Layout.rightMargin: 16
                Layout.leftMargin: 16
                Layout.bottomMargin: 16

                headerText: name
                bodyText: cardDescription
                footerText: price === qsTr("Free") || price === "0" ? "" : price

                rightImageSource: "qrc:/images/controls/chevron-right.svg"

                onClicked: {
                    if (isServiceAvailable) {
                        ApiServicesModel.setServiceIndex(proxyApiServicesModel.mapToSource(index))
                        ApiConfigsController.setSelectedServerCountryCode("")
                        ApiConfigsController.setImportAllCountries(false)
                        PageController.goToPage(PageEnum.PageSetupWizardApiServiceInfo)
                    }
                }
                
                Keys.onEnterPressed: clicked()
                Keys.onReturnPressed: clicked()
            }
        }
    }
}
