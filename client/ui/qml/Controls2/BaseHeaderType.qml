import QtQuick
import QtQuick.Layouts

import Style 1.0

import "TextTypes"

Item {
    id: root

    property string headerText
    // long Russian / Ukrainian titles need a third line rather than an ellipsis
    property int headerTextMaximumLineCount: 3
    property int headerTextElide: Qt.ElideRight
    property string descriptionText
    property alias headerRow: headerRow

    implicitWidth: content.implicitWidth
    implicitHeight: content.implicitHeight

    ColumnLayout {
        id: content
        anchors.fill: parent

        RowLayout {
            id: headerRow
            
            Header1TextType {
                id: header
                Layout.fillWidth: true
                // words wrap at spaces; only a token wider than the line (a
                // server renamed without spaces) breaks instead of running off
                wrapMode: Text.WrapAtWordBoundaryOrAnywhere
                text: root.headerText
                maximumLineCount: root.headerTextMaximumLineCount
                elide: root.headerTextElide
            }
        }

        ParagraphTextType {
            id: description
            Layout.topMargin: 16
            Layout.fillWidth: true
            text: root.descriptionText
            color: DopamineStyle.color.mutedGray
            visible: root.descriptionText !== ""
        }
    }
} 
