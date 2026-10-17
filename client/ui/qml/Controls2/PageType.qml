import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

import "../Config"

Item {
    id: root

    property StackView stackView: StackView.view
    property bool enableTimer: true
    // Android's navigation bar under the page: the night's bottom edge (shaders/pagesky.frag)
    property real navigationBarColor: 0xFF10173A

    onVisibleChanged: {
        if (visible) {
            PageController.updateNavigationBarColor(navigationBarColor)
        }
        if (visible && enableTimer) {
            timer.start()
        }
    }

    // Set a timer to set focus after a short delay
    Timer {
        id: timer
        interval: 200 // Milliseconds
        onTriggered: {
            FocusController.resetRootObject()
            FocusController.setFocusOnDefaultItem()
        }
        repeat: false // Stop the timer after one trigger
        running: enableTimer // Start the timer
    }
}
