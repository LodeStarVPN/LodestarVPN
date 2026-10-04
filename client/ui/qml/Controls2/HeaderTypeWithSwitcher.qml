import QtQuick
import QtQuick.Layouts

import Style 1.0

BaseHeaderType {
    id: root

    property var switcherFunction
    property bool showSwitcher: false
    property alias switcher: headerSwitcher

    Component.onCompleted: {
        headerRow.children.push(headerSwitcher)
    }

    SwitcherType {
        id: headerSwitcher
        // beside the first line of a wrapped title, not its middle
        Layout.alignment: Qt.AlignRight | Qt.AlignTop
        Layout.topMargin: 3
        visible: root.showSwitcher

        onToggled: {
            if (switcherFunction && typeof switcherFunction === "function") {
                switcherFunction(checked)
            }
        }
    }
} 
