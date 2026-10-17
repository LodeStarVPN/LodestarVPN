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

// How to bring another device onto the subscription, told here and not on a site (the owner's
// word, 2026-10-17): a Windows computer or an Android device gets our app and the subscription's
// key; an iPhone, iPad or Mac, which have no app of ours, the AmneziaWG app and a device of its
// own on the subscription (PageSettingsApiOtherDevice)
PageType {
    id: root

    readonly property string downloadUrl: "https://github.com/LodeStarVPN/LodestarVPN/releases/latest"
    property string subscriptionKey: ApiConfigsController.processedSubscriptionKey()
    // "2 out of 5"
    property string devicesInUse: ApiAccountInfoModel.data("connectedDevices")

    Connections {
        target: ApiAccountInfoModel

        function onModelReset() {
            root.devicesInUse = ApiAccountInfoModel.data("connectedDevices")
        }
    }

    // a section's name over its card, as in the night's design
    component SectionTitle: CaptionTextType {
        Layout.fillWidth: true
        Layout.topMargin: 22
        Layout.leftMargin: 20
        Layout.rightMargin: 20
        Layout.bottomMargin: 8

        color: DopamineStyle.color.charcoalGray
    }

    // text in one glass card, the home card's glass
    component GlassNote: Item {
        default property alias content: noteColumn.data

        Layout.fillWidth: true
        implicitHeight: noteColumn.implicitHeight + 32

        GlassSegment {
            anchors.fill: parent
            position: "single"
        }

        ColumnLayout {
            id: noteColumn

            anchors.top: parent.top
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.topMargin: 16
            anchors.leftMargin: 32
            anchors.rightMargin: 32

            spacing: 10
        }
    }

    component NoteText: ParagraphTextType {
        Layout.fillWidth: true

        font.pixelSize: 15
        lineHeight: 22 + LanguageModel.getLineHeightAppend()
    }

    FlickableType {
        id: fl

        anchors.fill: parent
        // the column starts under the status bar and must end over the navigation bar: without both
        // the last button stayed out of reach on a phone
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

                headerText: qsTr("How to connect on another device")
                descriptionText: root.devicesInUse !== ""
                                 ? qsTr("One subscription works on several devices, each takes a place on it. In use: %1").arg(root.devicesInUse)
                                 : qsTr("One subscription works on several devices, each takes a place on it.")
            }

            // ---- with our app
            SectionTitle {
                text: qsTr("Windows computer, Android phone or tablet")
            }

            GlassNote {
                NoteText {
                    text: qsTr("1. Download LodestarVPN on that device: the link is below. For Windows take the file ending in win64.msi, for Android the one ending in arm64-v8a.apk (it suits almost any phone).")
                }

                NoteText {
                    text: qsTr("2. Install it and open it, then enter the subscription key.")
                }

                CaptionTextType {
                    Layout.fillWidth: true

                    color: DopamineStyle.color.mutedGray
                    text: qsTr("If Android warns about an app not from Google Play, tap «More details» → «Install anyway».")
                }
            }

            GlassColumn {
                Layout.fillWidth: true
                Layout.topMargin: 12

                LabelWithButtonType {
                    Layout.fillWidth: true

                    text: qsTr("Link to LodestarVPN")
                    descriptionText: "github.com/LodeStarVPN/LodestarVPN"
                    rightImageSource: "qrc:/images/controls/copy.svg"

                    clickedFunction: function() {
                        GC.copyToClipBoard(root.downloadUrl)
                        PageController.showNotificationMessage(qsTr("Link copied: send it to the other device"))
                    }
                }

                // the whole access to the subscription: behind dots, as on its page
                LabelWithButtonType {
                    id: keyRow

                    Layout.fillWidth: true

                    visible: root.subscriptionKey !== ""

                    text: qsTr("Subscription key")
                    descriptionText: root.subscriptionKey

                    buttonImageSource: hideDescription ? "qrc:/images/controls/eye.svg" : "qrc:/images/controls/eye-off.svg"
                    rightImageSource: "qrc:/images/controls/copy.svg"

                    clickedFunction: function() {
                        GC.copyToClipBoard(root.subscriptionKey)
                        PageController.showNotificationMessage(qsTr("Subscription key copied"))
                    }
                }
            }

            // ---- without our app: AmneziaWG
            SectionTitle {
                text: qsTr("iPhone, iPad or Mac")
            }

            GlassNote {
                NoteText {
                    text: qsTr("There is no LodestarVPN app for them yet: they connect through the free AmneziaWG app from the App Store.")
                }

                NoteText {
                    text: qsTr("Such a device gets its own place on the subscription and its own key, which works on one device at a time.")
                }
            }

            BasicButtonType {
                Layout.fillWidth: true
                Layout.topMargin: 16
                Layout.leftMargin: 16
                Layout.rightMargin: 16

                text: qsTr("Add iPhone, iPad or Mac")

                clickedFunc: function() {
                    PageController.goToPage(PageEnum.PageSettingsApiOtherDevice)
                }
            }
        }
    }
}
