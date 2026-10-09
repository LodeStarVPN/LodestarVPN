import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

import PageEnum 1.0
import Style 1.0
import UpdateEnum 1.0

import "./"
import "../Controls2"
import "../Config"
import "../Controls2/TextTypes"
import "../Components"

PageType {
    id: root

    // the answer to a check from this page: a toast, or the update's sheet
    property bool userUpdateCheck: false

    Connections {
        target: UpdateController

        function onStateChanged() {
            if (!root.userUpdateCheck) {
                return
            }
            switch (UpdateController.state) {
            case UpdateEnum.UpToDate:
                root.userUpdateCheck = false
                PageController.showNotificationMessage(qsTr("You have the latest version"))
                break
            case UpdateEnum.Available:
            case UpdateEnum.ReadyToInstall:
                root.userUpdateCheck = false
                showUpdateDrawer()
                break
            case UpdateEnum.Failed:
                root.userUpdateCheck = false
                PageController.showNotificationMessage(qsTr("Couldn't check for updates. Check your internet connection and try again."))
                break
            }
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
        anchors.bottom: parent.bottom
        anchors.right: parent.right
        anchors.left: parent.left

        header: ColumnLayout {
            width: listView.width

            Image {
                id: image
                source: "qrc:/images/dopamineBigLogo.png"

                Layout.alignment: Qt.AlignCenter
                Layout.topMargin: 16
                Layout.leftMargin: 16
                Layout.rightMargin: 16
                Layout.preferredWidth: 291
                Layout.preferredHeight: 224
            }

            ParagraphTextType {
                Layout.fillWidth: true
                Layout.topMargin: 16
                Layout.leftMargin: 16
                Layout.rightMargin: 16

                horizontalAlignment: Text.AlignHCenter

                height: 20
                font.pixelSize: 14

                text: qsTr("LodestarVPN is built on the open-source Dopamine by FRKN and AmneziaVPN, licensed under GPL-3.0.")
                color: DopamineStyle.color.paleGray
            }

            ParagraphTextType {
                Layout.fillWidth: true
                Layout.topMargin: 32
                Layout.leftMargin: 16
                Layout.rightMargin: 16

                text: qsTr("Contacts")
            }
        }

        model: contacts

        delegate: ColumnLayout {
            width: listView.width

            LabelWithButtonType {
                Layout.fillWidth: true
                Layout.topMargin: 6

                text: title
                descriptionText: description
                leftImageSource: imageSource

                clickedFunction: handler
            }

            DividerType {}

        }

        footer: ColumnLayout {
            width: listView.width

            CaptionTextType {
                Layout.fillWidth: true
                Layout.topMargin: 40

                horizontalAlignment: Text.AlignHCenter

                // just the version: build date and commit stay in the logs
                text: qsTr("Software version: %1").arg(SettingsController.getAppVersion().split(" ")[0])
                color: DopamineStyle.color.mutedGray

                MouseArea {
                    property int clickCount: 0
                    anchors.fill: parent
                    onClicked: {
                        if (clickCount > 10) {
                            SettingsController.enableDevMode()
                        } else {
                            clickCount++
                        }
                    }
                }
            }

            BasicButtonType {
                id: checkUpdatesButton

                Layout.alignment: Qt.AlignHCenter
                Layout.topMargin: 8
                implicitHeight: 32

                defaultColor: DopamineStyle.color.transparent
                hoveredColor: DopamineStyle.color.translucentWhite
                pressedColor: DopamineStyle.color.sheerWhite
                disabledColor: DopamineStyle.color.mutedGray
                textColor: DopamineStyle.color.goldenApricot

                // dim while the gateway is being asked
                opacity: UpdateController.supported && UpdateController.state === UpdateEnum.Checking ? 0.5 : 1

                text: UpdateController.supported && UpdateController.updateAvailable
                      ? qsTr("Update to %1").arg(UpdateController.availableVersion)
                      : qsTr("Check for updates")

                clickedFunc: function() {
                    // Android updates itself; elsewhere the releases page
                    if (!UpdateController.supported) {
                        Qt.openUrlExternally("https://github.com/LodeStarVPN/LodestarVPN/releases/latest")
                        return
                    }
                    if (UpdateController.updateAvailable) {
                        showUpdateDrawer()
                        return
                    }
                    root.userUpdateCheck = true
                    UpdateController.checkForUpdate(true)
                }
            }

            BasicButtonType {
                id: privacyPolicyButton

                // the same height as the link above, so their hover pills match
                Layout.alignment: Qt.AlignHCenter
                Layout.bottomMargin: 16
                implicitHeight: 32

                defaultColor: DopamineStyle.color.transparent
                hoveredColor: DopamineStyle.color.translucentWhite
                pressedColor: DopamineStyle.color.sheerWhite
                disabledColor: DopamineStyle.color.mutedGray
                textColor: DopamineStyle.color.goldenApricot

                text: qsTr("Privacy Policy")

                clickedFunc: function() {
                    Qt.openUrlExternally(LanguageModel.getCurrentSiteUrl("privacy-policy"))
                }
            }
        }
    }
    
    property list<QtObject> contacts: [
        mail,
        github,
        website
    ]

    QtObject {
        id: mail

        readonly property string title: "support@lodestarvpn.com"
        readonly property string description: qsTr("For reviews and bug reports")
        readonly property string imageSource: "qrc:/images/controls/mail.svg"
        readonly property var handler: function() {
            Qt.openUrlExternally("mailto:support@lodestarvpn.com")
        }
    }

    QtObject {
        id: github

        readonly property string title: qsTr("GitHub")
        readonly property string description: qsTr("Discover the source code")
        readonly property string imageSource: "qrc:/images/controls/github.svg"
        readonly property var handler: function() {
            Qt.openUrlExternally("https://github.com/LodeStarVPN/LodestarVPN")
        }
    }

    QtObject {
        id: website

        readonly property string title: qsTr("Website")
        readonly property string description: qsTr("Visit official website")
        readonly property string imageSource: "qrc:/images/controls/external-link.svg"
        readonly property var handler: function() {
            Qt.openUrlExternally(LanguageModel.getCurrentSiteUrl())
        }
    }
}
