import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

import Style 1.0

import "TextTypes"
import "../Config"

Popup {
    id: root

    property string text
    property bool closeButtonVisible: true

    // the same side margins as the cards and buttons under it
    leftMargin: 16
    rightMargin: 16
    bottomMargin: 70 + SettingsController.safeAreaBottomMargin

    width: parent.width - leftMargin - rightMargin

    anchors.centerIn: parent
    modal: root.closeButtonVisible
    closePolicy: Popup.CloseOnEscape

    Overlay.modal: Rectangle {
        visible: root.closeButtonVisible
        color: DopamineStyle.color.translucentMidnightBlack
    }

    onOpened: {
        timer.start()
    }

    onClosed: {
        FocusController.dropRootObject(root)
    }

    // a card of the night, opaque over the page under it, with the rows' light edge (a grey slab
    // was out of the app's look, the owner, 2026-10-22: «дизайн приложения должен соответствовать
    // приложению полностью»)
    background: Rectangle {
        anchors.fill: parent

        color: DopamineStyle.color.darkCharcoal
        radius: 16
        border.width: 1
        border.color: "#2EA9C1FF"
    }

    Timer {
        id: timer
        interval: 200 // Milliseconds
        onTriggered: {
            FocusController.pushRootObject(root)
            FocusController.setFocusItem(closeButton)
        }
        repeat: false // Stop the timer after one trigger
        running: true // Start the timer
    }

    contentItem: Item {
        implicitWidth: content.implicitWidth
        implicitHeight: content.implicitHeight

        anchors.fill: parent

        RowLayout {
            id: content

            anchors.fill: parent
            anchors.leftMargin: 16
            anchors.rightMargin: 16

            spacing: 12

            CaptionTextType {
                horizontalAlignment: Text.AlignLeft
                Layout.fillWidth: true

                // the caption's default colour is the page background: black on
                // the grey toast. Light text reads in both themes
                color: DopamineStyle.color.paleGray
                linkColor: DopamineStyle.color.paleGray

                onLinkActivated: function(link) {
                    Qt.openUrlExternally(LanguageModel.getCurrentDocsUrl(link))
                }

                text: root.text

                MouseArea {
                    anchors.fill: parent
                    acceptedButtons: Qt.NoButton
                    cursorShape: parent.hoveredLink ? Qt.PointingHandCursor : Qt.ArrowCursor
                }
            }

            BasicButtonType {
                id: closeButton
                visible: closeButtonVisible

                implicitHeight: 32
                // a long message wraps instead of squeezing the button under its label
                Layout.minimumWidth: implicitWidth
                leftPadding: 16
                rightPadding: 16

                // the soft glass of the second actions
                cornerRadius: 10
                defaultColor: DopamineStyle.color.glassButton
                hoveredColor: DopamineStyle.color.glassButtonHovered
                pressedColor: DopamineStyle.color.glassButtonPressed

                textColor: DopamineStyle.color.glassButtonText

                buttonTextLabel.lineHeight: 20
                buttonTextLabel.font.pixelSize: 14
                buttonTextLabel.font.weight: 500

                text: qsTr("Close")

                clickedFunc: function() {
                    root.close()
                }
            }
        }
    }
}
