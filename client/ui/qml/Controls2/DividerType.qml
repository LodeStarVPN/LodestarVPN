import QtQuick
import QtQuick.Layouts

import Style 1.0

Rectangle {
    // in a glass card (GlassColumn) the card draws the lines between its rows: folded away
    property bool inGlass: false

    Layout.fillWidth: true

    Layout.leftMargin: 16
    Layout.rightMargin: 16

    Layout.preferredHeight: inGlass ? 0 : 1
    height: inGlass ? 0 : 1
    color: inGlass ? DopamineStyle.color.transparent : DopamineStyle.color.slateGray
}
