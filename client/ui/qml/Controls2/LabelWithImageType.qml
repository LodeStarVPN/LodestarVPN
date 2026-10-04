import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

import Style 1.0

import "TextTypes"

RowLayout {
    id: root

    property string imageSource
    property string leftText
    property var rightText
    property bool isRightTextUndefined: rightText === undefined
    property int rightTextFormat: Text.PlainText

    readonly property string valueText: isRightTextUndefined ? "" : rightText
    // The value sits right of the title while the two fit on one line and
    // goes under the title when they don't. Squeezed side by side, a layout
    // broke the title inside a word ("Скорост" / "ь") or wrapped a date into
    // a column of short lines
    readonly property bool valueBelow: valueText !== ""
            && iconImage.Layout.preferredWidth + spacing + titleItem.implicitWidth + inlineRow.spacing
               + inlineValue.implicitWidth > width - 1

    visible: !isRightTextUndefined

    Image {
        id: iconImage

        Layout.preferredHeight: 18
        Layout.preferredWidth: 18
        // level with the title's first line
        Layout.alignment: Qt.AlignTop
        Layout.topMargin: 2
        sourceSize: Qt.size(18, 18)
        source: root.imageSource
    }

    ColumnLayout {
        Layout.fillWidth: true
        spacing: 4

        RowLayout {
            id: inlineRow

            Layout.fillWidth: true
            spacing: 10

            ListItemTitleType {
                id: titleItem

                Layout.fillWidth: true
                Layout.alignment: Qt.AlignTop
                wrapMode: Text.WordWrap

                text: root.leftText
            }

            ParagraphTextType {
                id: inlineValue

                visible: !root.valueBelow && root.valueText !== ""
                Layout.alignment: Qt.AlignTop

                horizontalAlignment: Text.AlignRight

                text: root.valueText
                textFormat: root.rightTextFormat
            }
        }

        ParagraphTextType {
            visible: root.valueBelow

            Layout.fillWidth: true

            text: root.valueText
            textFormat: root.rightTextFormat
        }
    }
}
