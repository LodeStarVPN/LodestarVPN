import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtQuick.Window

import Style 1.0

import "TextTypes"

Item {
    id: root

    readonly property string drawerExpandedStateName: "expanded"
    readonly property string drawerCollapsedStateName: "collapsed"

    readonly property bool isOpened: isExpandedStateActive() || (isCollapsedStateActive() && (dragArea.drag.active === true))
    readonly property bool isClosed: isCollapsedStateActive() && (dragArea.drag.active === false)

    property Component collapsedStateContent
    property Component expandedStateContent

    // the sheet is the update sheet's night (shaders/pagesky.frag); a flat colour only with sky: false
    property bool sky: true
    property string defaultColor: DopamineStyle.color.midnightBlack
    property string borderColor: "#1FA9C1FF"

    property real expandedHeight
    property real collapsedHeight: 0

    property int depthIndex: 0
    // the navigation bar's colour under the page, given back as the sheet closes
    property real pageNavigationBarColor: 0

    // a handle on top of the sheet: a bar, and a zone round it (over the sheet's edge too) that
    // drags the sheet at once, over any scroll inside
    property bool handle: false
    property color handleColor: DopamineStyle.color.mutedGray

    signal cursorEntered
    signal cursorExited
    signal pressed(bool pressed, bool entered)

    signal aboutToHide
    signal aboutToShow
    signal closeTriggered
    signal openTriggered
    signal closed
    signal opened

    function isExpandedStateActive() {
        return isStateActive(drawerExpandedStateName)
    }

    // the sheet let go after a drag: back up when it was neither pulled far nor flicked down,
    // closed otherwise (it used to close on any pull). Back up, it follows its height again:
    // the content may grow
    function finishDrag(velocity) {
        if (drawerContent.y - dragArea.drag.minimumY > Math.min(120, root.expandedHeight * 0.25) || velocity > 0.5) {
            root.closeTriggered()
            return
        }
        snapBack.from = drawerContent.y
        snapBack.restart()
    }

    // where the sheet was over the drag's last 100 ms: its speed down, px/ms
    property var dragTrail: []

    function trackDrag(restart) {
        const now = Date.now()
        const trail = restart ? [] : dragTrail.filter(function(point) { return now - point.t < 100 })
        trail.push({ t: now, y: drawerContent.y })
        dragTrail = trail
    }

    function dragVelocity() {
        const trail = dragTrail
        if (trail.length < 2) {
            return 0
        }
        const first = trail[0]
        const last = trail[trail.length - 1]
        return last.t > first.t ? (last.y - first.y) / (last.t - first.t) : 0
    }

    NumberAnimation {
        id: snapBack

        target: drawerContent
        property: "y"
        to: dragArea.drag.minimumY
        duration: 220
        easing.type: Easing.OutCubic

        onFinished: drawerContent.y = Qt.binding(function() { return dragArea.drag.minimumY })
    }

    function isCollapsedStateActive() {
        return isStateActive(drawerCollapsedStateName)
    }

    function isStateActive(stateName) {
        return drawerContent.state === stateName
    }

    function isDrawerType2(obj) {
        return obj && typeof obj.drawerExpandedStateName !== "undefined" && 
               typeof obj.drawerCollapsedStateName !== "undefined"
    }

    function isDescendantOfDrawer(obj) {
        var current = obj
        while (current && current !== root.parent) {
            if (isDrawerType2(current)) {
                return true
            }
            current = current.parent
        }
        return false
    }

    function findComponent(obj, typeCtor) {
        if (!obj)
            return null

        if (isDrawerType2(obj) || isDescendantOfDrawer(obj))
            return null

        if (obj instanceof typeCtor)
            return obj

        if (obj.children && obj.children.length > 0) {
            for (var i = 0; i < obj.children.length; i++) {
                var matchingChildren = findComponent(obj.children[i], typeCtor)
                if (matchingChildren) return matchingChildren
            }
        }

        if (obj.contentItem) {
            var matchingContentItem = findComponent(obj.contentItem, typeCtor)
            if (matchingContentItem) return matchingContentItem
        }

        return null
    }

    function setParentInteractive(value) {
        var flickableType = findComponent(root.parent, Flickable)
        var listViewType = findComponent(root.parent, ListView)

        if (flickableType) flickableType.interactive = value
        if (listViewType) listViewType.interactive = value
    }

    Connections {
        target: Qt.application

        function onStateChanged() {
            if (Qt.application.state !== Qt.ApplicationActive) {
                if (dragArea.drag.active) {
                    dragArea.drag.target = null
                    dragArea.drag.target = drawerContent
                }
                if (isOpened && !isCollapsedStateActive()) {
                    root.closeTriggered()
                }
            }
        }
    }

    Connections {
        target: PageController

        function onCloseTopDrawer() {
            if (depthIndex === PageController.getDrawerDepth()) {
                if (isCollapsedStateActive()) {
                    return
                }

                aboutToHide()

                drawerContent.state = root.drawerCollapsedStateName
                depthIndex = 0
                closed()
            }
        }
    }

    Connections {
        target: root

        function onCloseTriggered() {
            if (isCollapsedStateActive()) {
                return
            }

            aboutToHide()

            setParentInteractive(true)

            closed()
        }

        function onClosed() {
            drawerContent.state = root.drawerCollapsedStateName
            
            if (root.isCollapsedStateActive() && root.pageNavigationBarColor !== 0) {
                PageController.updateNavigationBarColor(root.pageNavigationBarColor)
                root.pageNavigationBarColor = 0
            }

            depthIndex = 0
            PageController.decrementDrawerDepth()
            FocusController.dropRootObject(root)
        }

        function onOpenTriggered() {
            if (root.isExpandedStateActive()) {
                return
            }

            root.aboutToShow()

            setParentInteractive(false)

            root.opened()
        }

        function onOpened() {
            drawerContent.state = root.drawerExpandedStateName

            // the sheet's night at its bottom edge (shaders/pagesky.frag, a sheet)
            if (isExpandedStateActive() && root.pageNavigationBarColor === 0) {
                root.pageNavigationBarColor = PageController.navigationBarColor()
                PageController.updateNavigationBarColor(0xFF04071A)
            }

            depthIndex = PageController.incrementDrawerDepth()
            FocusController.pushRootObject(root)
        }
    }

    Rectangle {
        id: background

        anchors.fill: parent
        color: root.isCollapsedStateActive() ? DopamineStyle.color.transparent : DopamineStyle.color.translucentMidnightBlack
        // lightens as the sheet is pulled down
        opacity: 1 - Math.max(0, Math.min(1, (drawerContent.y - dragArea.drag.minimumY)
                                          / Math.max(1, dragArea.drag.maximumY - dragArea.drag.minimumY)))

        Behavior on color {
            PropertyAnimation { duration: 200 }
        }
    }

    MouseArea {
        id: emptyArea
        anchors.fill: parent

        onClicked: {
            root.closeTriggered()
        }
    }

    MouseArea {
        id: dragArea
        objectName: "dragArea"

        anchors.fill: drawerContentBackground
        hoverEnabled: true

        enabled: drawerContent.implicitHeight > 0

        drag.target: drawerContent
        drag.axis: Drag.YAxis
        drag.maximumY: root.height - root.collapsedHeight
        drag.minimumY: root.height - root.expandedHeight

        onPressed: function(mouse) {
            snapBack.stop()
            root.trackDrag(true)
        }

        onPositionChanged: function(mouse) {
            if (drag.active) {
                root.trackDrag(false)
            }
        }

        /** If drag area is released at any point other than min or max y: a collapsed sheet opens, an open one goes back or closes */
        onReleased: {
            if (isCollapsedStateActive() && drawerContent.y < dragArea.drag.maximumY) {
                root.openTriggered()
                return
            }
            if (isExpandedStateActive() && drawerContent.y > dragArea.drag.minimumY) {
                root.finishDrag(root.dragVelocity())
                return
            }
        }

        onEntered: {
            root.cursorEntered()
        }
        onExited: {
            root.cursorExited()
        }
        onPressedChanged: {
            root.pressed(pressed, entered)
        }

        onClicked: {
            if (isCollapsedStateActive()) {
                root.openTriggered()
            }
        }
    }

    Rectangle {
        id: drawerContentBackground
        objectName: "drawerContentBackground"

        anchors { left: drawerContent.left; right: drawerContent.right; top: drawerContent.top }
        height: root.height
        radius: 16
        color: root.sky ? DopamineStyle.color.transparent : root.defaultColor
        border.color: root.borderColor
        border.width: 1

        Rectangle {
            width: parent.radius
            height: parent.radius
            anchors.bottom: parent.bottom
            anchors.right: parent.right
            anchors.left: parent.left
            color: parent.color
        }

        // still: drawn once
        ShaderEffect {
            z: -1
            anchors.fill: parent

            visible: root.sky
            layer.enabled: true

            property size itemSize: Qt.size(width, height)
            property real pixel: 1 / Screen.devicePixelRatio
            property real sheet: 1
            property real corner: parent.radius

            fragmentShader: "qrc:/shaders/pagesky.frag.qsb"
        }
    }

    Item {
        id: drawerContent
        objectName: "drawerContent"

        Drag.active: dragArea.drag.active
        anchors.right: root.right
        anchors.left: root.left

        state: root.drawerCollapsedStateName

        states: [
            State {
                name: root.drawerCollapsedStateName
                PropertyChanges {
                    target: drawerContent
                    implicitHeight: collapsedHeight
                    y: root.height - root.collapsedHeight
                }
                PropertyChanges {
                    target: background
                    color: DopamineStyle.color.transparent
                }
                PropertyChanges {
                    target: dragArea
                    cursorShape: Qt.PointingHandCursor
                }
                PropertyChanges {
                    target: emptyArea
                    enabled: false
                    visible: false
                }
                PropertyChanges {
                    target: collapsedLoader
                    // visible: true
                }
                PropertyChanges {
                    target: expandedLoader
                    visible: false

                }
            },
            State {
                name: root.drawerExpandedStateName
                PropertyChanges {
                    target: drawerContent
                    implicitHeight: expandedHeight
                    y: dragArea.drag.minimumY
                }
                PropertyChanges {
                    target: background
                    color: Qt.rgba(14/255, 14/255, 17/255, 0.8)
                }
                PropertyChanges {
                    target: dragArea
                    cursorShape: Qt.ArrowCursor
                }
                PropertyChanges {
                    target: emptyArea
                    enabled: true
                    visible: true
                }
                PropertyChanges {
                    target: collapsedLoader
                    // visible: false
                }
                PropertyChanges {
                    target: expandedLoader
                    visible: true
                }
            }
        ]

        transitions: [
            Transition {
                from: root.drawerCollapsedStateName
                to: root.drawerExpandedStateName
                PropertyAnimation {
                    target: drawerContent
                    properties: "y"
                    duration: 250
                    easing.type: Easing.OutCubic
                }
            },
            Transition {
                from: root.drawerExpandedStateName
                to: root.drawerCollapsedStateName
                PropertyAnimation {
                    target: drawerContent
                    properties: "y"
                    duration: 250
                    easing.type: Easing.OutCubic
                }
            }
        ]

        // defer instantiation to the next event loop tick so the parent
        // (PageHome) can finish its first paint without paying for the
        // collapsed+expanded drawer components up front
        Loader {
            id: collapsedLoader
            asynchronous: true

            sourceComponent: root.collapsedStateContent

            anchors.right: parent.right
            anchors.left: parent.left
        }

        Loader {
            id: expandedLoader
            asynchronous: true

            sourceComponent: root.expandedStateContent

            anchors.right: parent.right
            anchors.left: parent.left
        }

        Rectangle {
            z: 2
            anchors.horizontalCenter: parent.horizontalCenter
            y: 8

            width: 36
            height: 4
            radius: 2

            visible: root.handle
            color: root.handleColor
        }

        // the handle's zone: wider than the bar and a little over the edge, as a finger lands;
        // the sheet follows it from the first move (no start distance) and nothing inside
        // takes the drag over
        MouseArea {
            id: handleArea

            property real pressY: 0
            property real startY: 0

            z: 2
            anchors.left: parent.left
            anchors.right: parent.right
            y: -16
            height: 60

            enabled: root.handle && root.isExpandedStateActive()
            preventStealing: true
            cursorShape: pressed ? Qt.ClosedHandCursor : Qt.OpenHandCursor

            onPressed: function(mouse) {
                snapBack.stop()
                pressY = mapToItem(root, mouse.x, mouse.y).y
                startY = drawerContent.y
                root.trackDrag(true)
            }

            onPositionChanged: function(mouse) {
                const y = startY + mapToItem(root, mouse.x, mouse.y).y - pressY
                drawerContent.y = Math.max(dragArea.drag.minimumY, Math.min(dragArea.drag.maximumY, y))
                root.trackDrag(false)
            }

            onReleased: function(mouse) {
                root.finishDrag(root.dragVelocity())
            }

            onCanceled: root.finishDrag(0)
        }
    }
}
