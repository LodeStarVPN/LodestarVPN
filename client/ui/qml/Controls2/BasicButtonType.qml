import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Qt5Compat.GraphicalEffects

import Style 1.0

import "TextTypes"

Button {
    id: root

    // by default the main action of a page or a sheet: glass lit by the connected ring's blue, with
    // the ring's light at its edge and around it (DopamineStyle ringButton*; the owner, 2026-10-22:
    // the white starlight one «не в нашей стилистике», then «дизайн приложения должен соответствовать
    // приложению полностью»). The soft glass one is glassButton* with glassButtonText
    property string hoveredColor: DopamineStyle.color.ringButtonHovered
    property string defaultColor: DopamineStyle.color.ringButton
    // under the busy spinner a page is disabled: the button stays in its own colours, not a grey slab
    property string disabledColor: defaultColor
    property string pressedColor: DopamineStyle.color.ringButtonPressed

    property string textColor: DopamineStyle.color.ringButtonText

    // the edge and the glow belong to the main action's own colours; a button in other colours has
    // neither unless it asks
    readonly property bool lit: Qt.colorEqual(defaultColor, DopamineStyle.color.ringButton)
    property string borderColor: lit ? DopamineStyle.color.ringButtonBorder : DopamineStyle.color.paleGray
    property string borderFocusedColor: DopamineStyle.color.paleGray
    property int borderWidth: lit ? 1 : 0
    property int borderFocusedWidth: 1

    property string leftImageSource
    property string rightImageSource
    property string leftImageColor: textColor
    property bool changeLeftImageSize: true

    property bool squareLeftSide: false
    property int cornerRadius: 16
    // a light around it, as around the switch that is on: the main action's own
    property string glowColor: lit ? DopamineStyle.color.ringButtonGlow : ""

    property var clickedFunc

    property alias buttonTextLabel: buttonText

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
    
    implicitHeight: 56

    hoverEnabled: true

    background: Rectangle {
        id: focusBorder

        color: DopamineStyle.color.transparent
        border.color: root.activeFocus ? root.borderFocusedColor : DopamineStyle.color.transparent
        border.width: root.activeFocus ? root.borderFocusedWidth : 0

        anchors.fill: parent

        radius: root.cornerRadius

        RectangularGlow {
            z: -1
            anchors.fill: background

            visible: root.glowColor !== "" && root.enabled
            glowRadius: 12
            spread: 0.1
            cornerRadius: background.radius + glowRadius
            color: root.glowColor !== "" ? root.glowColor : DopamineStyle.color.transparent
        }

        Rectangle {
            id: background

            anchors.fill: focusBorder
            anchors.margins: root.activeFocus ? 2 : 0

            radius: root.activeFocus ? root.cornerRadius - 2 : root.cornerRadius
            color: {
                if (root.enabled) {
                    if (root.pressed) {
                        return pressedColor
                    }
                    return root.hovered ? hoveredColor : defaultColor
                } else {
                    return disabledColor
                }
            }
            border.color: borderColor
            border.width: borderWidth

            Behavior on color {
                PropertyAnimation { duration: 200 }
            }

            Rectangle {
                visible: root.squareLeftSide

                z: 1

                width: parent.radius
                height: parent.radius
                anchors.top: parent.top
                anchors.bottom: parent.bottom
                anchors.left: parent.left
                color: {
                    if (root.enabled) {
                        if (root.pressed) {
                            return root.pressedColor
                        }
                        return root.hovered ? root.hoveredColor : root.defaultColor
                    } else {
                        return root.disabledColor
                    }
                }

                Behavior on color {
                    PropertyAnimation { duration: 200 }
                }
            }
        }
    }

    MouseArea {
        anchors.fill: focusBorder
        enabled: false
        cursorShape: Qt.PointingHandCursor
    }

    contentItem: Item {
        anchors.fill: focusBorder

        implicitWidth: content.implicitWidth
        implicitHeight: content.implicitHeight

        RowLayout {
            id: content
            anchors.centerIn: parent

            Image {
                id: leftImage
                source: root.leftImageSource
                visible: root.leftImageSource === "" ? false : true

                layer {
                    enabled: leftImageColor !== "" ? true : false
                    effect: ColorOverlay {
                        color: leftImageColor
                    }
                }

                Component.onCompleted: {
                    if (root.changeLeftImageSize) {
                        leftImage.Layout.preferredHeight = 20
                        leftImage.Layout.preferredWidth = 20
                    }
                }
            }

            ButtonTextType {
                id: buttonText

                color: root.textColor
                text: root.text
                visible: root.text === "" ? false : true

                horizontalAlignment: Text.AlignLeft
                verticalAlignment: Text.AlignVCenter
            }

            Image {
                Layout.preferredHeight: 20
                Layout.preferredWidth: 20

                source: root.rightImageSource
                visible: root.rightImageSource === "" ? false : true

                layer {
                    enabled: true
                    effect: ColorOverlay {
                        color: textColor
                    }
                }
            }
        }
    }

    Keys.onEnterPressed: {
        if (root.clickedFunc && typeof root.clickedFunc === "function") {
            root.clickedFunc()
        }
    }

    Keys.onReturnPressed: {
        if (root.clickedFunc && typeof root.clickedFunc === "function") {
            root.clickedFunc()
        }
    }

    onClicked: {
        if (root.clickedFunc && typeof root.clickedFunc === "function") {
            root.clickedFunc()
        }
    }
}
