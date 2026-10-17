pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

import Style 1.0

import "../Controls2"
import "../Controls2/TextTypes"

import "../Config"

DrawerType2 {
    id: root

    property string headerText
    property string descriptionText
    property string yesButtonText
    // a third choice between the two, when a question has one; none when empty
    property string middleButtonText
    property string noButtonText

    property var yesButtonFunction
    property var middleButtonFunction
    property var noButtonFunction

    expandedStateContent: ColumnLayout {
        id: content

        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right

        spacing: 8

        onImplicitHeightChanged: {
            root.expandedHeight = content.implicitHeight + 32 + SettingsController.safeAreaBottomMargin
        }

        Header2TextType {
            Layout.fillWidth: true
            Layout.topMargin: 16
            Layout.rightMargin: 16
            Layout.leftMargin: 16

            // words wrap at spaces; only a token longer than the line (a long
            // domain in "Remove <site>?") is broken instead of running off the sheet
            wrapMode: Text.Wrap

            text: root.headerText
        }

        ParagraphTextType {
            Layout.fillWidth: true
            Layout.topMargin: 8
            Layout.rightMargin: 16
            Layout.leftMargin: 16

            // an empty line would leave a gap between the question and the buttons
            visible: root.descriptionText !== ""

            text: root.descriptionText
        }

        BasicButtonType {
            id: yesButton
            Layout.fillWidth: true
            Layout.topMargin: 16
            Layout.rightMargin: 16
            Layout.leftMargin: 16

            text: root.yesButtonText

            clickedFunc: function() {
                if (root.yesButtonFunction && typeof root.yesButtonFunction === "function") {
                    root.yesButtonFunction()
                }
            }
        }

        BasicButtonType {
            id: middleButton
            Layout.fillWidth: true
            Layout.rightMargin: 16
            Layout.leftMargin: 16

            defaultColor: DopamineStyle.color.glassButton
            hoveredColor: DopamineStyle.color.glassButtonHovered
            pressedColor: DopamineStyle.color.glassButtonPressed
            disabledColor: DopamineStyle.color.mutedGray
            textColor: DopamineStyle.color.glassButtonText

            visible: root.middleButtonText !== ""

            text: root.middleButtonText

            clickedFunc: function() {
                if (root.middleButtonFunction && typeof root.middleButtonFunction === "function") {
                    root.middleButtonFunction()
                }
            }
        }

        BasicButtonType {
            id: noButton
            Layout.fillWidth: true
            Layout.rightMargin: 16
            Layout.leftMargin: 16

            defaultColor: DopamineStyle.color.glassButton
            hoveredColor: DopamineStyle.color.glassButtonHovered
            pressedColor: DopamineStyle.color.glassButtonPressed
            disabledColor: DopamineStyle.color.mutedGray
            textColor: DopamineStyle.color.glassButtonText

            visible: root.noButtonText !== ""

            text: root.noButtonText

            clickedFunc: function() {
                if (root.noButtonFunction && typeof root.noButtonFunction === "function") {
                    root.noButtonFunction()
                }
            }
        }
    }
}
