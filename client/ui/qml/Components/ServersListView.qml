import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Qt5Compat.GraphicalEffects

import SortFilterProxyModel 0.2

import PageEnum 1.0
import ProtocolEnum 1.0
import ContainerProps 1.0
import ContainersModelFilters 1.0
import Style 1.0

import "./"
import "../Controls2"
import "../Controls2/TextTypes"
import "../Config"

ListViewType {
    id: root

    property int selectedIndex: ServersModel.defaultIndex
    property string protocolFilter: ""
    property bool protocolFilterTouched: false
    property string envFilter: ""

    ButtonGroup {
        id: serversRadioButtonGroup
    }

    Component.onCompleted: {
        const saved = SettingsController.serversProtocolFilter
        if (saved !== "" && saved !== "all") {
            root.protocolFilterTouched = true
            root.protocolFilter = saved
        }
        const savedEnv = SettingsController.serversEnvFilter
        if (savedEnv !== "" && savedEnv !== "all") {
            root.envFilter = savedEnv
        }
        rebuildProtocolsModel()
        rebuildEnvsModel()

        // probing is meaningful only with VPN off (see healthcheck research)
        if (!ConnectionController.isConnected) {
            HealthCheckController.startProbe()
        }

        // server loads for the next choice of server (at most every few minutes)
        ApiConfigsController.refreshLoadIfStale()
    }

    function flagCountryCode(cc) {
        // backend sometimes sends non-ISO codes
        const aliases = {
            "SWE": "SE", "HEL": "FI", "UK": "GB",
            "EST": "EE", "TLL": "EE", "EESTI": "EE", "ESTONIA": "EE", "TALLINN": "EE"
        }
        return aliases[cc] !== undefined ? aliases[cc] : cc
    }

    function protocolLabel(proto) {
        if (proto === "") {
            return qsTr("All")
        }
        if (proto === "vless") {
            return "VLESS"
        }
        if (proto === "hysteria2") {
            return "Hysteria2"
        }
        if (proto === "awg") {
            return "AmneziaWG"
        }
        if (proto === "awg-mobile" || proto === "amneziawgmobile") {
            return "AmneziaWG Mobile"
        }
        if (proto === "wireguard") {
            return "WireGuard"
        }
        return proto
    }

    function rebuildProtocolsModel() {
        // only protocols the selected env actually has - no dead options
        const protos = ServersModel.availableProtocolsForEnv(root.envFilter)

        // same priority as auto-select: mobile AWG first, then plain AWG
        function pickDefault() {
            if (protos.indexOf("awg-mobile") >= 0) return "awg-mobile"
            if (protos.indexOf("awg") >= 0) return "awg"
            return protos.length > 0 ? protos[0] : ""
        }

        if (!root.protocolFilterTouched) {
            root.protocolFilter = pickDefault()
        } else if (protos.length > 0 && protos.indexOf(root.protocolFilter) < 0) {
            root.protocolFilter = pickDefault()
        }

        protocolsModel.clear()
        for (let i = 0; i < protos.length; i++) {
            protocolsModel.append({ "name": protocolLabel(protos[i]), "value": protos[i] })
        }
    }

    ListModel {
        id: protocolsModel
    }

    function envLabel(env) {
        if (env === "") {
            return qsTr("All")
        }
        if (env === "wl") {
            return qsTr("White Elephants")
        }
        if (env === "dev") {
            return qsTr("Regular")
        }
        if (env === "ru") {
            return qsTr("Reverse")
        }
        return env
    }

    function rebuildEnvsModel() {
        const envs = ServersModel.availableEnvs

        if (envs.length > 0 && root.envFilter !== "" && envs.indexOf(root.envFilter) < 0) {
            root.envFilter = ""
        }

        envsModel.clear()
        envsModel.append({ "name": envLabel(""), "value": "" })
        for (let i = 0; i < envs.length; i++) {
            envsModel.append({ "name": envLabel(envs[i]), "value": envs[i] })
        }
    }

    ListModel {
        id: envsModel
    }

    header: Item {
        visible: true
        width: root.width
        // the auto-select card, then the servers' card
        height: visible ? headerColumn.implicitHeight + 16 : 0

        ColumnLayout {
            id: headerColumn

            anchors.top: parent.top
            anchors.left: parent.left
            anchors.right: parent.right
            spacing: 8

            RowLayout {
                id: filtersRow

                Layout.fillWidth: true
                Layout.leftMargin: 16
                Layout.rightMargin: 16

                spacing: 8

                FilterDropDown {
                    id: envFilterDropDown

                    Layout.fillWidth: true

                    visible: ServersModel.availableEnvs.length > 1

                    filterModel: envsModel
                    currentValue: root.envFilter

                    onSelected: function(value) {
                        root.envFilter = value
                        SettingsController.serversEnvFilter = value === "" ? "all" : value
                        // protocol options depend on the env
                        root.rebuildProtocolsModel()
                    }
                }

                FilterDropDown {
                    id: protocolFilterDropDown

                    Layout.fillWidth: true

                    visible: protocolsModel.count > 1

                    filterModel: protocolsModel
                    currentValue: root.protocolFilter

                    onSelected: function(value) {
                        root.protocolFilterTouched = true
                        root.protocolFilter = value
                        SettingsController.serversProtocolFilter = value === "" ? "all" : value
                    }
                }

                // re-measures the servers; next to the filters an icon is
                // enough, alone it needs its label
                BasicButtonType {
                    id: refreshHealthButton

                    readonly property bool iconOnly: envFilterDropDown.visible || protocolFilterDropDown.visible

                    Layout.alignment: Qt.AlignVCenter
                    Layout.preferredWidth: iconOnly ? 48 : implicitWidth

                    implicitHeight: 40
                    cornerRadius: 12

                    // the soft glass button
                    defaultColor: DopamineStyle.color.glassButton
                    hoveredColor: DopamineStyle.color.glassButtonHovered
                    pressedColor: DopamineStyle.color.glassButtonPressed
                    textColor: DopamineStyle.color.glassButtonText

                    leftImageSource: "qrc:/images/controls/gauge.svg"
                    text: iconOnly ? "" : qsTr("Check servers")

                    clickedFunc: function() {
                        if (HealthCheckController.isOtherVpnUp()) {
                            PageController.showNotificationMessage(qsTr("Another VPN is on: the ping through it would be wrong. Turn it off and check again."))
                        }
                        HealthCheckController.startProbe(true)
                    }
                }
            }

            // auto-select: a glass card of its own, lit by the lodestar while it is the choice
            Item {
                Layout.fillWidth: true
                Layout.topMargin: 4

                implicitHeight: Math.max(64, autoSelectButton.implicitHeight + 16)

                GlassSegment {
                    anchors.fill: parent

                    pressed: autoSelectButton.pressed
                    lit: autoSelectButton.checked
                }

                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: 32
                    anchors.rightMargin: 32

                    spacing: 14

                    // the gauge in a ring, where a server has its flag
                    Rectangle {
                        Layout.preferredWidth: 26
                        Layout.preferredHeight: 26

                        radius: 13
                        color: DopamineStyle.color.transparent
                        border.width: 1.5
                        border.color: "#47A9C1FF"

                        Image {
                            anchors.centerIn: parent
                            width: 14
                            height: 14

                            source: "qrc:/images/controls/gauge.svg"
                            sourceSize: Qt.size(42, 42)

                            layer.enabled: true
                            layer.effect: ColorOverlay {
                                color: DopamineStyle.color.mutedGray
                            }
                        }
                    }

                    VerticalRadioButton {
                        id: autoSelectButton
                        objectName: "autoSelectButton"

                        Layout.fillWidth: true

                        bare: true
                        selectedTextColor: textColor

                        text: qsTr("Auto-select")
                        descriptionText: qsTr("Fastest available server")

                        checked: SettingsController.autoServerSelection
                        checkable: true

                        ButtonGroup.group: serversRadioButtonGroup

                        onClicked: {
                            SettingsController.autoServerSelection = true

                            // connected already - reconnect to the auto-picked server
                            if (ConnectionController.isConnected) {
                                ConnectionController.openConnection()
                            }
                        }

                        Keys.onEnterPressed: autoSelectButton.clicked()
                        Keys.onReturnPressed: autoSelectButton.clicked()
                    }

                    LodestarMark {
                        visible: autoSelectButton.checked
                    }
                }
            }
        }
    }

    model: SortFilterProxyModel {
        id: proxyServersModel
        sourceModel: ServersModel

        filters: [
            ValueFilter {
                roleName: "serviceProtocolFilter"
                value: root.protocolFilter
                enabled: root.protocolFilter !== ""
            },
            ValueFilter {
                roleName: "connectionEnv"
                value: root.envFilter
                enabled: root.envFilter !== ""
            }
        ]
    }

    Connections {
        target: ServersModel
        function onDefaultServerIndexChanged(serverIndex) {
            root.selectedIndex = serverIndex
        }
        function onAvailableProtocolsChanged() {
            root.rebuildProtocolsModel()
        }
        function onAvailableEnvsChanged() {
            root.rebuildEnvsModel()
        }
    }

    delegate: Item {
        id: menuContentDelegate
        objectName: "menuContentDelegate"

        property variant delegateData: model
        property VerticalRadioButton serverRadioButtonProperty: serverRadioButton

        implicitWidth: root.width
        implicitHeight: Math.max(64, serverRadioButtonContent.implicitHeight)

        // the servers stand in one glass card; the chosen one is lit by the lodestar
        GlassSegment {
            anchors.fill: parent

            position: root.count === 1 ? "single" : index === 0 ? "first" : index === root.count - 1 ? "last" : "middle"
            pressed: serverRadioButton.pressed
            lit: serverRadioButton.checked
        }

        ColumnLayout {
            id: serverRadioButtonContent
            objectName: "serverRadioButtonContent"

            anchors.fill: parent
            anchors.rightMargin: 20
            anchors.leftMargin: 32

            spacing: 0

            RowLayout {
                objectName: "serverRadioButtonRowLayout"

                Layout.fillWidth: true

                spacing: 14

                Image {
                    id: serverCountryFlag

                    objectName: "serverCountryFlag"

                    Layout.alignment: Qt.AlignVCenter
                    Layout.preferredWidth: 24
                    Layout.preferredHeight: 24

                    sourceSize.width: 48
                    sourceSize.height: 48
                    fillMode: Image.PreserveAspectFit

                    source: countryCode !== ""
                            ? "qrc:/countriesFlags/images/flagKit/" + root.flagCountryCode(countryCode) + ".svg"
                            : ""
                    visible: countryCode !== "" && status !== Image.Error

                    layer.enabled: true
                    layer.effect: OpacityMask {
                        maskSource: Rectangle {
                            width: serverCountryFlag.width
                            height: serverCountryFlag.height
                            radius: 5
                        }
                    }
                }

                VerticalRadioButton {
                    id: serverRadioButton
                    objectName: "serverRadioButton"

                    Layout.fillWidth: true

                    // chosen: lit by the lodestar, the name keeps its colour
                    bare: true
                    selectedTextColor: textColor

                    text: listName
                    // no address/protocol/country here - technical details live
                    // on the server details card; legacy servers keep services.
                    // The ping goes under the name: in a column of its own it
                    // left the name ~10 letters and long countries broke mid-word.
                    // Its dot is the home card's: green, amber, red as it gets slower
                    descriptionText: {
                        var parts = []
                        if (!isServerFromGatewayApi && serverDescription !== "") {
                            parts.push(serverDescription.replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;"))
                        }
                        // the server the VPN is on: the home card's ping through the tunnel, not the
                        // figure from before the connect (the two did not agree)
                        var latency = ConnectionController.isConnected && ConnectionController.ping !== ""
                                && index === proxyServersModel.mapFromSource(root.selectedIndex)
                                ? Number(ConnectionController.ping) : healthLatency
                        if (latency !== -2) {
                            var dot = "<font color='" + (latency < 0 || latency >= 300 ? "#F08A93"
                                                         : latency < 120 ? "#5FD497" : "#F2B45A") + "'>●</font>"
                            if (SettingsController.isServerPingTextVisible) {
                                parts.push(dot + " " + (latency >= 0 ? qsTr("%1 ms").arg(latency) : qsTr("offline")))
                            } else {
                                parts.push(dot)
                            }
                        }
                        return parts.join(" · ")
                    }

                    checked: index === proxyServersModel.mapFromSource(root.selectedIndex) && !SettingsController.autoServerSelection
                    checkable: true

                    ButtonGroup.group: serversRadioButtonGroup

                    onClicked: {
                        SettingsController.autoServerSelection = false

                        root.selectedIndex = proxyServersModel.mapToSource(index)

                        ServersModel.defaultIndex = root.selectedIndex

                        // connected already - reconnect to the newly selected server
                        if (ConnectionController.isConnected) {
                            ConnectionController.openConnection()
                        }
                    }

                    Keys.onEnterPressed: serverRadioButton.clicked()
                    Keys.onReturnPressed: serverRadioButton.clicked()
                }

                LodestarMark {
                    visible: serverRadioButton.checked
                }

                ImageButtonType {
                    id: serverInfoButton
                    objectName: "serverInfoButton"

                    image: "qrc:/images/controls/settings.svg"
                    imageColor: DopamineStyle.color.mutedGray

                    implicitWidth: 48
                    implicitHeight: 56

                    z: 1

                    onClicked: function() {
                        ServersModel.processedIndex = proxyServersModel.mapToSource(index)

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
        }
    }
}
