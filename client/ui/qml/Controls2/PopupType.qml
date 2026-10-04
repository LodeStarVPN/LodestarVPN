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

    background: Rectangle {
        anchors.fill: parent

        color: DopamineStyle.color.charcoalGray
        radius: 12
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

                defaultColor: DopamineStyle.color.mutedGray
                hoveredColor: DopamineStyle.color.lightGray
                pressedColor: DopamineStyle.color.lightGray
                disabledColor: DopamineStyle.color.charcoalGray

                textColor: DopamineStyle.color.midnightBlack
                borderWidth: 0

                text: qsTr("Close")

                clickedFunc: function() {
                    root.close()
                }
            }
        }
    }
}
