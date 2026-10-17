import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

import QtCore

import PageEnum 1.0
import Style 1.0

import "./"
import "../Controls2"
import "../Controls2/TextTypes"
import "../Config"
import "../Components"

// A device without our app - an iPhone, an iPad, a Mac - on the subscription: first which one it
// is, then its files for the AmneziaWG app, one per country (the gateway's v1/other_device). The
// files hold the device's key: they live only while this page is open (a new file later is a
// new key, from «Активные устройства»), and the QR code carries the same key as the file.
PageType {
    id: root

    property var files: ApiConfigsController.otherDeviceFiles
    property string deviceName: ApiConfigsController.otherDeviceName
    property int selected: 0
    readonly property bool hasFiles: files.length > 0
    readonly property var file: hasFiles ? files[Math.min(selected, files.length - 1)] : null
    // a Mac's AmneziaWG takes a file, not a code
    readonly property bool showsCode: deviceName !== "Mac"

    Connections {
        target: ApiConfigsController

        function onOtherDeviceFilesChanged() {
            root.files = ApiConfigsController.otherDeviceFiles
            root.deviceName = ApiConfigsController.otherDeviceName
            root.selected = 0
        }

        function onOtherDeviceFailed(message) {
            PageController.showErrorMessage(message)
        }
    }

    // the key goes with the page
    Component.onDestruction: {
        ApiConfigsController.clearOtherDeviceFiles()
    }

    function addDevice(kind) {
        PageController.showBusyIndicator(true)
        const done = ApiConfigsController.addOtherDevice(kind)
        PageController.showBusyIndicator(false)
        if (done) {
            // past the cache: «Активные устройства» and «Устройства» count it now
            ApiSettingsController.getAccountInfo(true, true)
        }
    }

    function sendFile() {
        if (!root.file) {
            return
        }
        if (GC.isMobile()) {
            ApiConfigsController.sendOtherDeviceFile(root.selected)
            return
        }
        const fileName = SystemController.getFileName(qsTr("Save"),
                                                      qsTr("AmneziaWG files (*.conf)"),
                                                      StandardPaths.standardLocations(StandardPaths.DocumentsLocation) + "/" + root.file.fileName,
                                                      true,
                                                      ".conf")
        if (fileName !== "") {
            ApiConfigsController.sendOtherDeviceFile(root.selected, fileName)
            PageController.showNotificationMessage(qsTr("File saved: send it to the device"))
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
        // the last lines stayed out of reach on a phone
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

                headerText: root.hasFiles ? root.deviceName : qsTr("A device without our app")
                descriptionText: !root.hasFiles
                                 ? qsTr("An iPhone, iPad or Mac connects through the AmneziaWG app. It will take a place on the subscription.")
                                 : root.showsCode ? qsTr("Scan the code in AmneziaWG, or send the file to the device.")
                                                  : qsTr("Send the file to the Mac and open it in AmneziaWG.")
            }

            // ---- which device
            GlassColumn {
                Layout.fillWidth: true
                Layout.topMargin: 16

                visible: !root.hasFiles

                LabelWithButtonType {
                    Layout.fillWidth: true

                    text: "iPhone"
                    rightImageSource: "qrc:/images/controls/chevron-right.svg"

                    clickedFunction: function() {
                        root.addDevice("iphone")
                    }
                }

                LabelWithButtonType {
                    Layout.fillWidth: true

                    text: "iPad"
                    rightImageSource: "qrc:/images/controls/chevron-right.svg"

                    clickedFunction: function() {
                        root.addDevice("ipad")
                    }
                }

                LabelWithButtonType {
                    Layout.fillWidth: true

                    text: "Mac"
                    rightImageSource: "qrc:/images/controls/chevron-right.svg"

                    clickedFunction: function() {
                        root.addDevice("mac")
                    }
                }
            }

            // ---- its files: a country each, the chosen one lit by the lodestar
            GlassColumn {
                Layout.fillWidth: true
                Layout.topMargin: 16

                visible: root.hasFiles && root.files.length > 1

                Repeater {
                    model: root.files.length > 1 ? root.files : []

                    LabelWithButtonType {
                        Layout.fillWidth: true

                        text: modelData.countryName
                        glassLit: index === root.selected

                        clickedFunction: function() {
                            root.selected = index
                        }
                    }
                }
            }

            Rectangle {
                Layout.preferredWidth: Math.min(root.width - 64, 320)
                Layout.preferredHeight: Layout.preferredWidth
                Layout.alignment: Qt.AlignHCenter
                Layout.topMargin: 20

                visible: root.hasFiles && root.showsCode && root.file.qrImage !== ""
                color: "white"
                radius: 16

                Image {
                    anchors.fill: parent
                    anchors.margins: 8
                    smooth: false
                    fillMode: Image.PreserveAspectFit
                    sourceSize.width: width
                    sourceSize.height: height
                    source: root.file ? root.file.qrImage : ""
                }
            }

            BasicButtonType {
                Layout.fillWidth: true
                Layout.topMargin: 20
                Layout.leftMargin: 16
                Layout.rightMargin: 16

                visible: root.hasFiles

                text: GC.isMobile() ? qsTr("Send file") : qsTr("Save file")

                clickedFunc: function() {
                    root.sendFile()
                }
            }

            // ---- how, on the device
            Item {
                Layout.fillWidth: true
                Layout.topMargin: 20

                visible: root.hasFiles
                implicitHeight: steps.implicitHeight + 32

                GlassSegment {
                    anchors.fill: parent
                    position: "single"
                }

                ColumnLayout {
                    id: steps

                    anchors.top: parent.top
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.topMargin: 16
                    anchors.leftMargin: 32
                    anchors.rightMargin: 32

                    spacing: 10

                    NoteText {
                        text: qsTr("1. Install AmneziaWG from the App Store.")
                    }

                    NoteText {
                        text: root.showsCode
                              ? qsTr("2. In AmneziaWG tap «+», choose to create from a QR code and point the camera at the code. Or open the file you sent to the device and choose AmneziaWG.")
                              : qsTr("2. In AmneziaWG choose to import a tunnel from a file and pick the file you sent.")
                    }

                    NoteText {
                        text: qsTr("3. Allow it to add a VPN configuration and turn the tunnel on.")
                    }
                }
            }

            CaptionTextType {
                Layout.fillWidth: true
                Layout.topMargin: 12
                Layout.leftMargin: 20
                Layout.rightMargin: 20

                visible: root.hasFiles

                color: DopamineStyle.color.mutedGray
                text: qsTr("The code and the file are this device's key: do not send them to anyone else. It works on one device at a time. A new file is in Active devices: tap the device; the old files then stop working.")
            }

            CaptionTextType {
                Layout.fillWidth: true
                Layout.topMargin: 8
                Layout.leftMargin: 20
                Layout.rightMargin: 20

                visible: root.hasFiles

                color: DopamineStyle.color.mutedGray
                text: qsTr("On such a device Russian sites go through the VPN too: AmneziaWG does not send them directly as our app does.")
            }
        }
    }
}
