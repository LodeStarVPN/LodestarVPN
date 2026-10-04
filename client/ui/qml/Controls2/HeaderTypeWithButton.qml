import QtQuick
import QtQuick.Layouts

import Style 1.0

BaseHeaderType {
    id: root

    property string actionButtonImage
    property var actionButtonFunction
    property alias actionButton: headerActionButton

    Component.onCompleted: {
        headerRow.children.push(headerActionButton)
    }

    ImageButtonType {
        id: headerActionButton
        implicitWidth: 40
        implicitHeight: 40
        // beside the first line of a wrapped title, not its middle
        Layout.alignment: Qt.AlignRight | Qt.AlignTop
        image: root.actionButtonImage
        imageColor: DopamineStyle.color.paleGray
        visible: image ? true : false

        onClicked: {
            if (actionButtonFunction && typeof actionButtonFunction === "function") {
                actionButtonFunction()
            }
        }
    }

    Keys.onEnterPressed: {
        if (actionButtonFunction && typeof actionButtonFunction === "function") {
            actionButtonFunction()
        }
    }

    Keys.onReturnPressed: {
        if (actionButtonFunction && typeof actionButtonFunction === "function") {
            actionButtonFunction()
        }
    }
} 
