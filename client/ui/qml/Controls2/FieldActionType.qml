import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

import Style 1.0

// an action of a field (TextFieldWithHeaderType.actions) in the strip along the bottom of its frame:
// an icon and a word in the connected text's blue, the strip shared out evenly with the others, the
// rows' glass under it only while pointed at or pressed. A hairline on its left parts it from the one
// before
Item {
    id: root

    property alias text: button.text
    property alias iconSource: button.leftImageSource
    property bool divider: false
    property var clickedFunc

    Layout.fillWidth: true
    Layout.fillHeight: true
    implicitHeight: 44

    Rectangle {
        visible: root.divider

        width: 1
        height: parent.height - 20
        anchors.left: parent.left
        anchors.verticalCenter: parent.verticalCenter

        color: "#2E6E91FF"
    }

    BasicButtonType {
        id: button

        anchors.fill: parent
        anchors.margins: 4

        // pressing it leaves the cursor where it was: no keyboard on a phone
        focusPolicy: Qt.NoFocus

        cornerRadius: 12

        // the rows' glass, a little more of it pressed
        defaultColor: DopamineStyle.color.transparent
        hoveredColor: DopamineStyle.color.translucentSlateGray
        pressedColor: "#2E7892FF"
        textColor: DopamineStyle.color.link

        buttonTextLabel.lineHeight: 20
        buttonTextLabel.font.pixelSize: 14
        buttonTextLabel.font.weight: 500

        clickedFunc: function() {
            if (root.clickedFunc && typeof root.clickedFunc === "function") {
                root.clickedFunc()
            }
        }
    }
}
