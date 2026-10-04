import QtQuick
import QtQuick.Controls

ListView {
    id: root

    property bool isFocusable: true

    ScrollBar.vertical: ScrollBarType {}

    clip: true
    reuseItems: true
    // a fast flick stops at the first and the last item instead of flying
    // past them and springing back
    boundsBehavior: Flickable.StopAtBounds

    // A header whose texts arrive after the first layout (an account refresh)
    // grows above a view that keeps its offset: the page showed up scrolled
    // into its own header. A view at the top stays at the top
    property real previousOriginY: 0
    Component.onCompleted: previousOriginY = originY
    onOriginYChanged: {
        if (Math.abs(contentY - previousOriginY) < 1) {
            Qt.callLater(root.positionViewAtBeginning)
        }
        previousOriginY = originY
    }

    function findChildWithObjectName(items, name) {
        for (var i = 0; i < items.length; ++i) {
            if (items[i].objectName === name)
                return items[i];
        }
        return null;
    }
}
