import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Qt5Compat.GraphicalEffects

import Style 1.0

import "TextTypes"

CheckBox {
    id: root

    property string descriptionText
    property string descriptionTextColor: DopamineStyle.color.mutedGray
    property string descriptionTextDisabledColor: DopamineStyle.color.charcoalGray

    property string textColor: DopamineStyle.color.paleGray
    property string textDisabledColor: DopamineStyle.color.mutedGray

    property string hoveredColor: DopamineStyle.color.barelyTranslucentWhite
    property string defaultColor: DopamineStyle.color.transparent
    property string pressedColor: DopamineStyle.color.barelyTranslucentWhite

    // the box as the switch (SwitcherType): a dim glass with a faint edge, and when checked the
    // ring's blue lit with its glow and a light tick (a grey outline was out of the app's look,
    // the owner, 2026-10-22: «дизайн приложения должен соответствовать приложению полностью»)
    property string boxColor: "#1A7892FF"
    property string checkedBoxColor: DopamineStyle.color.richBrown
    property string defaultBorderColor: "#4DA9C1FF"
    property string checkedBorderColor: "#5996B4FF"
    property string checkedBorderDisabledColor: DopamineStyle.color.deepBrown

    property string borderFocusedColor: DopamineStyle.color.paleGray

    property string checkedImageColor: "#F3F6FF"
    property string pressedImageColor: DopamineStyle.color.link
    property string defaultImageColor: DopamineStyle.color.transparent
    property string checkedDisabledImageColor: DopamineStyle.color.mutedGray

    property string imageSource: "qrc:/images/controls/check.svg"

    property bool isFocusable: true

    Keys.onTabPressed: {
        FocusController.nextKeyTabItem()
    }

    Keys.onBacktabPressed: {
        FocusController.previousKeyTabItem()
    }

    Keys.onUpPressed: {
        FocusController.nextKeyUpItem()
    }
    
    Keys.onDownPressed: {
        FocusController.nextKeyDownItem()
    }
    
    Keys.onLeftPressed: {
        FocusController.nextKeyLeftItem()
    }

    Keys.onRightPressed: {
        FocusController.nextKeyRightItem()
    }

    hoverEnabled: enabled ? true : false
    focusPolicy: Qt.NoFocus

    background: Rectangle {
        color: DopamineStyle.color.transparent
        border.color: root.focus ? borderFocusedColor : DopamineStyle.color.transparent
        border.width: 1
        radius: 16
    }

    indicator: Rectangle {
        id: background

        anchors.verticalCenter: parent.verticalCenter

        implicitWidth: 56
        implicitHeight: 56
        radius: 16

        color:  {
            if (root.hovered) {
                return hoveredColor
            }
            return defaultColor
        }

        Behavior on color {
            PropertyAnimation { duration: 200 }
        }

        Rectangle {
            id: imageBorder

            anchors.centerIn: parent
            width: 24
            height: 24
            color: root.checked ? root.checkedBoxColor : root.boxColor
            border.color: root.checked ?
                              (root.enabled ?
                                   checkedBorderColor :
                                   checkedBorderDisabledColor) :
                              defaultBorderColor
            border.width: 1
            radius: 6

            Behavior on color {
                PropertyAnimation { duration: 200 }
            }

            RectangularGlow {
                z: -1
                anchors.fill: parent

                glowRadius: 6
                spread: 0.15
                cornerRadius: parent.radius + glowRadius
                color: "#6B2757FF"

                opacity: root.checked && root.enabled ? 1 : 0
                visible: opacity > 0

                Behavior on opacity {
                    PropertyAnimation { duration: 200 }
                }
            }

            Image {
                anchors.centerIn: parent
                // inside the lit box, clear of its edge
                width: 18
                height: 18
                sourceSize: Qt.size(18, 18)

                source: root.pressed ? imageSource : root.checked ? imageSource : ""
                layer {
                    enabled: true
                    effect: ColorOverlay {
                        color: {
                            if (root.pressed) {
                                return root.pressedImageColor
                            } else if (root.checked) {
                                if (root.enabled) {
                                    return root.checkedImageColor
                                } else {
                                    return root.checkedDisabledImageColor
                                }
                            } else {
                                return root.defaultImageColor
                            }
                        }
                    }
                }
            }
        }
    }

    contentItem: Item {
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.leftMargin: 8 + background.width

        implicitHeight: content.implicitHeight

        ColumnLayout {
            id: content

            anchors.left: parent.left
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter

            spacing: 4

            ListItemTitleType {
                Layout.fillWidth: true

                text: root.text
                color: root.enabled ? root.textColor : root.textDisabledColor
            }

            CaptionTextType {
                id: description

                Layout.fillWidth: true

                text: root.descriptionText
                color: root.enabled ? root.descriptionTextColor : root.descriptionTextDisabledColor

                visible: root.descriptionText !== ""
            }
        }
    }

    MouseArea {
        anchors.fill: parent
        cursorShape: Qt.PointingHandCursor
        enabled: false
    }

    Keys.onEnterPressed: event => handleSwitch(event)
    Keys.onReturnPressed: event => handleSwitch(event)
    Keys.onSpacePressed: event => handleSwitch(event)

    function handleSwitch(event) {
        if (!event.isAutoRepeat) {
            root.checked = !root.checked
            root.checkedChanged()
        }
        event.accepted = true
    }
}


