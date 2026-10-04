import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtQuick.Dialogs

import QtCore

import PageEnum 1.0
import Style 1.0

import "./"
import "../Controls2"
import "../Controls2/TextTypes"
import "../Config"

PageType {
    id: root

    Component.onCompleted: {
        if (ImportController.hasPendingSubscription) {
            subscriptionDrawer.configCount = ImportController.subscriptionConfigsCount()
            subscriptionDrawer.openTriggered()
        }
    }

    Connections {
        target: ImportController

        function onQrDecodingFinished() {
            ImportController.queueConfigForConfirmation()
        }

        function onSubscriptionConfigsReady(count) {
            PageController.showBusyIndicator(false)
            subscriptionDrawer.configCount = count
            subscriptionDrawer.openTriggered()
        }

        function onSubscriptionErrorOccurred(message) {
            PageController.showBusyIndicator(false)
            PageController.showErrorMessage(message)
        }

        function onSubscriptionAllDuplicates() {
            PageController.showBusyIndicator(false)
            PageController.showNotificationMessage(qsTr("All configurations have already been added"))
        }

        function onImportFinished() {
            PageController.showBusyIndicator(false)
            if (!ConnectionController.isConnected) {
                ServersModel.setDefaultServerIndex(ServersModel.getServersCount() - 1)
                ServersModel.processedIndex = ServersModel.defaultIndex
            }
            PageController.goToPageHome()
        }
    }

    Connections {
        // input text that doesn't match any known format (key, share/subscription
        // link, UUID, Xray subscription URL, Amnezia config) - hide the busy
        // indicator set by the Continue button and surface a clear message
        target: ImportController

        function onUnknownFormatDetected(rawInput) {
            PageController.showBusyIndicator(false)
            PageController.showErrorMessage(qsTr("Unrecognized input — paste a subscription ID, lodestar:// link, vless:// configuration, or a WireGuard/AmneziaWG config"))
        }
    }

    ListViewType {
        id: listView

        anchors.fill: parent

        header: ColumnLayout {
            width: listView.width

            ColumnLayout {
                Layout.fillWidth: true
                Layout.topMargin: 20 + SettingsController.safeAreaTopMargin

                spacing: 4

                // the arrow on its own row, the title below it at the page margin,
                // the same as on the other pages of this flow
                BackButtonType {
                    id: backButton

                    visible: !PageController.isStartPageVisible()
                }

                HeaderTypeWithButton {
                    id: moreButton

                    property bool isVisible: SettingsController.getInstallationUuid() !== "" || PageController.isStartPageVisible()

                    Layout.fillWidth: true
                    Layout.rightMargin: 16
                    Layout.leftMargin: 16

                    headerText: qsTr("Connection")

                    actionButtonImage: isVisible ? "qrc:/images/controls/more-vertical.svg" : ""
                    actionButtonFunction: function() {
                        moreActionsDrawer.openTriggered()
                    }

                    DrawerType2 {
                        id: moreActionsDrawer

                        parent: root

                        anchors.fill: parent

                        expandedStateContent: ColumnLayout {
                            id: moreActionsContent

                            anchors.top: parent.top
                            anchors.left: parent.left
                            anchors.right: parent.right
                            spacing: 0

                            onImplicitHeightChanged: {
                                moreActionsDrawer.expandedHeight = moreActionsContent.implicitHeight + 32
                                        + SettingsController.safeAreaBottomMargin
                            }

                            BaseHeaderType {
                                Layout.fillWidth: true
                                Layout.topMargin: 32
                                Layout.leftMargin: 16
                                Layout.rightMargin: 16

                                headerText: qsTr("Settings")
                            }

                            SwitcherType {
                                id: switcher
                                Layout.fillWidth: true
                                Layout.topMargin: 16
                                Layout.leftMargin: 16
                                Layout.rightMargin: 16

                                text: qsTr("Enable logs")

                                visible: PageController.isStartPageVisible()
                                checked: SettingsController.isLoggingEnabled
                                onToggled: function() {
                                    if (checked !== SettingsController.isLoggingEnabled) {
                                        SettingsController.isLoggingEnabled = checked
                                    }
                                }
                            }

                            LabelWithButtonType {
                                Layout.fillWidth: true

                                text: qsTr("Export client logs")
                                rightImageSource: "qrc:/images/controls/chevron-right.svg"

                                visible: PageController.isStartPageVisible()

                                clickedFunction: function() {
                                    var fileName = ""
                                    if (GC.isMobile()) {
                                        fileName = "LodestarVPN.log"
                                    } else {
                                        fileName = SystemController.getFileName(qsTr("Save"),
                                                                                qsTr("Logs files (*.log)"),
                                                                                StandardPaths.standardLocations(StandardPaths.DocumentsLocation) + "/LodestarVPN",
                                                                                true,
                                                                                ".log")
                                    }
                                    if (fileName !== "") {
                                        PageController.showBusyIndicator(true)
                                        SettingsController.exportLogsFile(fileName)
                                        PageController.showBusyIndicator(false)
                                        PageController.showNotificationMessage(qsTr("Logs file saved"))
                                    }
                                }
                            }

                            LabelWithButtonType {
                                id: supportUuid
                                Layout.fillWidth: true
                                Layout.topMargin: 16

                                text: qsTr("Support tag")
                                // the ID itself is not shown, only copied for support
                                descriptionText: qsTr("Copy it and send it to support")

                                descriptionOnTop: true

                                rightImageSource: "qrc:/images/controls/copy.svg"
                                rightImageColor: DopamineStyle.color.paleGray

                                visible: SettingsController.getInstallationUuid() !== ""
                                clickedFunction: function() {
                                    GC.copyToClipBoard(SettingsController.getInstallationUuid())
                                    PageController.showNotificationMessage(qsTr("Copied"))
                                    if (!GC.isMobile()) {
                                        this.rightButton.forceActiveFocus()
                                    }
                                }
                            }
                        }
                    }
                }
            }

            TextFieldWithHeaderType {
                id: textKey

                Layout.fillWidth: true
                Layout.topMargin: 32
                Layout.rightMargin: 16
                Layout.leftMargin: 16

                // everything the field accepts, see onUnknownFormatDetected
                hintText: qsTr("Paste your LodestarVPN subscription ID or link, a connection key or an AmneziaWG/WireGuard config")
                multiline: true
            }

            BasicButtonType {
                id: continueButton

                Layout.fillWidth: true
                Layout.topMargin: 16
                Layout.rightMargin: 16
                Layout.leftMargin: 16

                visible: textKey.inputText !== ""

                text: qsTr("Continue")

                clickedFunc: function() {
                    var inputText = textKey.inputText.trim()
                    if (ImportController.extractConfigFromData(inputText)) {
                        ImportController.queueConfigForConfirmation()
                    } else {
                        // If extractConfigFromData returned false, it might be an async
                        // subscription fetch in progress - show busy indicator.
                        // The indicator will be hidden by signal handlers above.
                        // Subscription ids and lodestar://sub/, lodestar://conn/ links manage
                        // the busy indicator in their coreController handlers and finish via
                        // ApiConfigsController signals; only direct URLs are fetched here.
                        var isHttp = inputText.startsWith("http://") || inputText.startsWith("https://")
                        if (isHttp) {
                            PageController.showBusyIndicator(true)
                        }
                    }
                }
            }

            ParagraphTextType {
                Layout.fillWidth: true
                Layout.topMargin: 32
                Layout.rightMargin: 16
                Layout.leftMargin: 16
                Layout.bottomMargin: 24

                color: DopamineStyle.color.charcoalGray
                text: qsTr("Other connection options")
            }
        }

        model: variants

        delegate: ColumnLayout {
            width: listView.width

            CardWithIconsType {
                Layout.fillWidth: true
                Layout.rightMargin: 16
                Layout.leftMargin: 16
                Layout.bottomMargin: 16

                visible: isVisible

                headerText: title
                bodyText: description

                rightImageSource: "qrc:/images/controls/chevron-right.svg"
                leftImageSource: imageSource

                onClicked: { handler() }

                Keys.onEnterPressed: this.clicked()
                Keys.onReturnPressed: this.clicked()
            }
        }

        footer: ColumnLayout {
            width: listView.width

            visible: false

            BasicButtonType {
                id: siteLink2
                Layout.topMargin: 24
                Layout.bottomMargin: 16
                Layout.alignment: Qt.AlignHCenter
                implicitHeight: 32

                visible: Qt.platform.os !== "ios" && !IsMacOsNeBuild

                defaultColor: DopamineStyle.color.transparent
                hoveredColor: DopamineStyle.color.translucentWhite
                pressedColor: DopamineStyle.color.sheerWhite
                disabledColor: DopamineStyle.color.mutedGray
                textColor: DopamineStyle.color.goldenApricot

                text: qsTr("LodestarVPN website")

                rightImageSource: "qrc:/images/controls/external-link.svg"

                clickedFunc: function() {
                    Qt.openUrlExternally(LanguageModel.getCurrentSiteUrl())
                }
            }
        }
    }

    property list<QtObject> variants: [
        qrScan,
        amneziaVpn,
        restorePurchases,
        siteLink
    ]

    QtObject {
        id: amneziaVpn

        property string title: qsTr("LodestarVPN")
        property string description: qsTr("Connect with your LodestarVPN subscription")
        property string imageSource: "qrc:/images/controls/lodestar.svg"
        property bool isVisible: true
        property var handler: function() {
            PageController.showBusyIndicator(true)
            var result = ApiConfigsController.fillAvailableServices()
            PageController.showBusyIndicator(false)
            if (result) {
                PageController.goToPage(PageEnum.PageSetupWizardApiServicesList)
            }
        }
    }

    QtObject {
        id: backupRestore

        property string title: qsTr("Restore from backup")
        property string description: qsTr("")
        property string imageSource: "qrc:/images/controls/archive-restore.svg"
        property bool isVisible: PageController.isStartPageVisible()
        property var handler: function() {
            var filePath = SystemController.getFileName(qsTr("Open backup file"),
                                                        qsTr("Backup files (*.backup)"))
            if (filePath !== "") {
                PageController.showBusyIndicator(true)
                SettingsController.restoreAppConfig(filePath)
                PageController.showBusyIndicator(false)
            }
        }
    }

    QtObject {
        id: fileOpen

        property string title: qsTr("File with connection settings")
        property string description: qsTr("")
        property string imageSource: "qrc:/images/controls/folder-search-2.svg"
        property bool isVisible: true
        property var handler: function() {
            var nameFilter = !ServersModel.getServersCount() ? "Config or backup files (*.vpn *.conf *.json *.backup)" :
                                                               "Config files (*.vpn *.conf *.json)"
            var fileName = SystemController.getFileName(qsTr("Open config file"), nameFilter)
            if (fileName !== "") {
                if (ImportController.extractConfigFromFile(fileName)) {
                    ImportController.queueConfigForConfirmation()
                }
            }
        }
    }

    QtObject {
        id: qrScan

        property string title: qsTr("QR code")
        property string description: qsTr("")
        property string imageSource: "qrc:/images/controls/scan-line.svg"
        property bool isVisible: SettingsController.isCameraPresent()
        property var handler: function() {
            ImportController.startDecodingQr()
            if (Qt.platform.os === "ios") {
                PageController.goToPage(PageEnum.PageSetupWizardQrReader)
            }
        }
    }

    QtObject {
        id: restorePurchases

        property string title: qsTr("Restore purchases")
        property string description: qsTr("")
        property string imageSource: "qrc:/images/controls/refresh-cw.svg"
        property bool isVisible: Qt.platform.os === "ios" || IsMacOsNeBuild
        property var handler: function() {
            PageController.showBusyIndicator(true)
            ApiConfigsController.restoreSerivceFromAppStore()
            PageController.showBusyIndicator(false)
        }
    }

    QtObject {
        id: siteLink

        property string title: qsTr("I have nothing")
        property string description: qsTr("")
        property string imageSource: "qrc:/images/controls/help-circle.svg"
        property bool isVisible: PageController.isStartPageVisible() && Qt.platform.os !== "ios" && !IsMacOsNeBuild
        property var handler: function() {
            Qt.openUrlExternally(LanguageModel.getCurrentSiteUrl())
        }
    }

    DrawerType2 {
        id: subscriptionDrawer

        property int configCount: 0

        parent: root
        anchors.fill: parent

        expandedStateContent: ColumnLayout {
            id: subscriptionContent

            anchors.top: parent.top
            anchors.left: parent.left
            anchors.right: parent.right
            spacing: 0

            // measured again once the texts wrap and the count arrives
            onImplicitHeightChanged: {
                subscriptionDrawer.expandedHeight = subscriptionContent.implicitHeight + 32
                        + SettingsController.safeAreaBottomMargin
            }

            Header2Type {
                Layout.fillWidth: true
                Layout.topMargin: 24
                Layout.rightMargin: 16
                Layout.leftMargin: 16
                Layout.bottomMargin: 16

                // a single pasted key or config is one connection, not a subscription
                headerText: subscriptionDrawer.configCount === 1 ? qsTr("Add this connection?")
                                                                 : qsTr("Subscription loaded")
            }

            ParagraphTextType {
                Layout.fillWidth: true
                Layout.rightMargin: 16
                Layout.leftMargin: 16
                Layout.bottomMargin: 24

                visible: subscriptionDrawer.configCount !== 1

                text: qsTr("Found %n configuration(s). Add them all?", "", subscriptionDrawer.configCount)
            }

            CheckBoxType {
                id: replacePreviousCheckbox
                Layout.fillWidth: true
                Layout.rightMargin: 16
                // the box itself in line with the texts and buttons at 16 px
                Layout.leftMargin: 0
                Layout.bottomMargin: 16

                text: qsTr("Delete previous configurations")
                checked: false
                visible: ServersModel.getServersCount() > 0
            }

            BasicButtonType {
                Layout.fillWidth: true
                Layout.rightMargin: 16
                Layout.leftMargin: 16
                Layout.bottomMargin: 8

                text: subscriptionDrawer.configCount === 1 ? qsTr("Add")
                                                           : qsTr("Add %n server(s)", "", subscriptionDrawer.configCount)

                clickedFunc: function() {
                    PageController.showBusyIndicator(true)
                    subscriptionDrawer.closeTriggered()
                    ImportController.importSubscriptionConfigs(replacePreviousCheckbox.checked)
                }
            }

            BasicButtonType {
                Layout.fillWidth: true
                Layout.rightMargin: 16
                Layout.leftMargin: 16

                defaultColor: DopamineStyle.color.transparent
                hoveredColor: DopamineStyle.color.translucentWhite
                pressedColor: DopamineStyle.color.sheerWhite
                textColor: DopamineStyle.color.paleGray

                text: qsTr("Cancel")

                clickedFunc: function() {
                    subscriptionDrawer.closeTriggered()
                }
            }
        }
    }

}
