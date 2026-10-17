import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Qt5Compat.GraphicalEffects

import Style 1.0

import "TextTypes"

Switch {
    id: root

    property alias descriptionText: description.text
    property string descriptionTextColor: DopamineStyle.color.mutedGray
    property string descriptionTextDisabledColor: DopamineStyle.color.charcoalGray

    property string textColor: DopamineStyle.color.paleGray
    property string textDisabledColor: DopamineStyle.color.mutedGray

    // on: the connected ring's blue with its glow, the knob a little star; off: dim glass
    property string checkedIndicatorColor: DopamineStyle.color.richBrown
    property string defaultIndicatorColor: "#1A7892FF"
    property string checkedDisabledIndicatorColor: DopamineStyle.color.deepBrown

    property string borderFocusedColor: DopamineStyle.color.paleGray
    property int borderFocusedWidth: 1

    property string checkedIndicatorBorderColor: "#5996B4FF"
    property string defaultIndicatorBorderColor: "#29A9C1FF"
    property string checkedDisabledIndicatorBorderColor: DopamineStyle.color.deepBrown

    property string checkedInnerCircleColor: "#F3F6FF"
    property string defaultInnerCircleColor: "#7A84A6"
    property string checkedDisabledInnerCircleColor: DopamineStyle.color.mutedGray
    property string defaultDisabledInnerCircleColor: DopamineStyle.color.charcoalGray

    property string hoveredIndicatorBackgroundColor: DopamineStyle.color.translucentWhite
    property string defaultIndicatorBackgroundColor: DopamineStyle.color.transparent

    property bool isFocusable: true

    // a finger on it that has not moved (the row's own touch, tapArea below): Switch's pressed
    // no longer sees the touches
    readonly property bool tapPressed: tapArea.pressed && !tapArea.moved

    // its place in a glass card (GlassSegment, GlassColumn): "" none, "single", "first",
    // "middle", "last"; then the row stands in the card without margins of its own
    property string glass: ""

    topPadding: glass !== "" ? 16 : padding
    bottomPadding: glass !== "" ? 16 : padding

    background: GlassSegment {
        visible: root.glass !== ""
        position: root.glass !== "" ? root.glass : "single"
        pressed: root.tapPressed
    }

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
    focusPolicy: Qt.TabFocus

    indicator: Rectangle {
        id: switcher

        anchors.right: parent.right
        anchors.rightMargin: root.glass !== "" ? 32 : 0
        anchors.verticalCenter: parent.verticalCenter

        implicitWidth: 52
        implicitHeight: 32

        radius: 16
        color: root.checked ? (root.enabled ? root.checkedIndicatorColor : root.checkedDisabledIndicatorColor)
                            : root.defaultIndicatorColor

        border.color: root.activeFocus ? root.borderFocusedColor : (root.checked ? (root.enabled ? root.checkedIndicatorBorderColor : root.checkedDisabledIndicatorBorderColor)
                            : root.defaultIndicatorBorderColor)

        Behavior on color {
            PropertyAnimation { duration: 200 }
        }
        Behavior on border.color {
            PropertyAnimation { duration: 200 }
        }

        RectangularGlow {
            z: -1
            anchors.fill: parent

            glowRadius: 7
            spread: 0.15
            cornerRadius: parent.radius + glowRadius
            color: "#6B2757FF"

            opacity: root.checked && root.enabled ? 1 : 0
            visible: opacity > 0

            Behavior on opacity {
                PropertyAnimation { duration: 200 }
            }
        }

        Rectangle {
            id: innerCircle

            anchors.verticalCenter: parent.verticalCenter
            x: root.checked ? parent.width - width - 4 : 8
            width: root.checked ? 24 : 16
            height: root.checked ? 24 : 16
            radius: 23
            color: root.checked ? (root.enabled ? root.checkedInnerCircleColor : root.checkedDisabledInnerCircleColor)
                                : (root.enabled ? root.defaultInnerCircleColor : root.defaultDisabledInnerCircleColor)

            Behavior on x {
                PropertyAnimation { duration: 200 }
            }

            RectangularGlow {
                z: -1
                anchors.fill: parent

                glowRadius: 4
                spread: 0.1
                cornerRadius: width / 2 + glowRadius
                color: "#B3CDDCFF"

                opacity: root.checked && root.enabled ? 1 : 0
                visible: opacity > 0

                Behavior on opacity {
                    PropertyAnimation { duration: 200 }
                }
            }
        }

        Rectangle {
            anchors.centerIn: innerCircle
            width: 40
            height: 40
            radius: 23
            color: root.hovered || tapArea.containsMouse ? root.hoveredIndicatorBackgroundColor : root.defaultIndicatorBackgroundColor

            Behavior on color {
                PropertyAnimation { duration: 200 }
            }
        }
    }

    contentItem: ColumnLayout {
        id: content

        anchors.verticalCenter: parent.verticalCenter
        anchors.left: parent.left
        anchors.leftMargin: root.glass !== "" ? 32 : 0
        // in a card the text keeps clear of the card's edge; elsewhere the control sizes it
        anchors.right: root.glass !== "" ? parent.right : undefined
        anchors.rightMargin: root.glass !== "" ? 32 : 0

        ListItemTitleType {
            Layout.fillWidth: true
            rightPadding: indicator.width

            text: root.text
            color: root.enabled ? root.textColor : root.textDisabledColor
        }

        CaptionTextType {
            id: description

            Layout.fillWidth: true
            rightPadding: indicator.width

            color: root.enabled ? root.descriptionTextColor : root.descriptionTextDisabledColor

            visible: text !== ""
        }
    }

    // A tap turns it, a finger that moves does not. Switch turns on a release anywhere on it, so a
    // finger that scrolled the page from this row, up or down, turned the switch (the owner,
    // 2026-10-17) - a sheet or a page that fits the screen does not take the move away from it.
    // The row takes the touch itself: a tap turns it, a slide along the switch's own track turns
    // it that way (right on, left off) as on any phone, the rest is left to the page
    MouseArea {
        id: tapArea

        property point pressPoint
        property bool moved: false
        property bool onTrack: false

        anchors.fill: parent
        cursorShape: Qt.PointingHandCursor
        hoverEnabled: root.hoverEnabled
        enabled: root.enabled

        onPressed: function(mouse) {
            pressPoint = Qt.point(mouse.x, mouse.y)
            moved = false
            onTrack = mouse.x >= switcher.x - 16 && mouse.x <= switcher.x + switcher.width + 16
        }
        onPositionChanged: function(mouse) {
            const t = Qt.styleHints.startDragDistance
            if (Math.abs(mouse.x - pressPoint.x) > t || Math.abs(mouse.y - pressPoint.y) > t) {
                moved = true
            }
        }
        onReleased: function(mouse) {
            const dx = mouse.x - pressPoint.x
            const dy = mouse.y - pressPoint.y
            const slide = moved && onTrack && Math.abs(dx) > 2 * Math.abs(dy) && (dx > 0) !== root.checked
            if (!moved || slide) {
                // toggle() keeps the switch's binding to what it shows, as a tap on Switch did
                root.toggle()
                root.toggled()
            }
        }
    }

    Keys.onEnterPressed: event => handleSwitch(event)
    Keys.onReturnPressed: event => handleSwitch(event)
    Keys.onSpacePressed: event => handleSwitch(event)

    function handleSwitch(event) {
        if (!event.isAutoRepeat) {
            root.checked = !root.checked
            root.toggled()
        }
        event.accepted = true
    }
}
