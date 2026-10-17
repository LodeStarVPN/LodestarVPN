import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

import Style 1.0

import "../Controls2"
import "../Controls2/TextTypes"

Rectangle {
    id: root

    property var filterModel
    property string currentValue

    signal selected(string value)

    implicitHeight: buttonContent.implicitHeight
    radius: 16

    color: DopamineStyle.color.onyxBlack
    border.color: popup.opened ? DopamineStyle.color.goldenApricot : DopamineStyle.color.slateGray
    border.width: 1

    Behavior on border.color {
        PropertyAnimation { duration: 200 }
    }

    RowLayout {
        id: buttonContent

        anchors.left: parent.left
        anchors.right: parent.right

        spacing: 0

        ButtonTextType {
            Layout.fillWidth: true
            Layout.leftMargin: 16
            Layout.topMargin: 16
            Layout.bottomMargin: 16

            horizontalAlignment: Text.AlignLeft
            verticalAlignment: Text.AlignVCenter

            color: DopamineStyle.color.paleGray
            // one line under the chevron: elide only works without wrapping
            wrapMode: Text.NoWrap
            elide: Text.ElideRight

            text: {
                if (!root.filterModel) {
                    return root.currentValue
                }
                for (let i = 0; i < root.filterModel.count; i++) {
                    const item = root.filterModel.get(i)
                    if (item.value === root.currentValue) {
                        return item.name
                    }
                }
                return root.currentValue
            }
        }

        ImageButtonType {
            Layout.rightMargin: 16

            implicitWidth: 40
            implicitHeight: 40

            hoverEnabled: false
            image: "qrc:/images/controls/chevron-down.svg"
            imageColor: DopamineStyle.color.goldenApricot

            rotation: popup.opened ? 180 : 0

            Behavior on rotation {
                PropertyAnimation { duration: 200 }
            }
        }
    }

    MouseArea {
        anchors.fill: parent
        cursorShape: Qt.PointingHandCursor

        onClicked: {
            if (popup.opened) {
                popup.close()
            } else {
                popup.open()
            }
        }
    }

    Popup {
        id: popup

        // a press on the header is the header's own (it closes the list): with
        // the default CloseOnPressOutside the press closed it and the click
        // that followed opened it again
        closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutsideParent

        y: root.height + 4
        width: root.width
        implicitHeight: Math.min(list.contentHeight + topPadding + bottomPadding, 320)

        topPadding: 4
        bottomPadding: 4
        leftPadding: 4
        rightPadding: 4

        // the night itself under the list, not the rows' glass: the glass is see-through and the
        // rows under the open list showed through it (the owner, 2026-10-17: «список прозрачный»)
        background: Rectangle {
            radius: 16
            color: DopamineStyle.color.darkCharcoal
            border.color: DopamineStyle.color.sheerWhite
            border.width: 1
        }

        contentItem: ListView {
            id: list

            model: root.filterModel
            clip: true
            interactive: contentHeight > height
            boundsBehavior: Flickable.StopAtBounds

            delegate: Rectangle {
                width: list.width
                height: 44
                radius: 12

                // the hover tint every other row uses: lightGray hid the text
                color: delegateMouseArea.containsMouse ? DopamineStyle.color.translucentWhite : DopamineStyle.color.transparent

                ButtonTextType {
                    anchors.left: parent.left
                    anchors.right: chosenMark.left
                    anchors.verticalCenter: parent.verticalCenter
                    anchors.leftMargin: 12
                    anchors.rightMargin: 8

                    horizontalAlignment: Text.AlignLeft
                    wrapMode: Text.NoWrap
                    elide: Text.ElideRight

                    text: name
                    color: DopamineStyle.color.paleGray
                }

                // the chosen one: the lodestar, as everywhere a choice is shown
                LodestarMark {
                    id: chosenMark

                    anchors.right: parent.right
                    anchors.rightMargin: 12
                    anchors.verticalCenter: parent.verticalCenter

                    implicitWidth: 22
                    implicitHeight: 22

                    visible: value === root.currentValue
                }

                MouseArea {
                    id: delegateMouseArea

                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    hoverEnabled: true

                    onClicked: {
                        root.selected(value)
                        popup.close()
                    }
                }
            }
        }
    }
}
