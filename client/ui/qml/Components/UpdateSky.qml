import QtQuick
import QtQuick.Window

import UpdateEnum 1.0

// The night sky of the in-app update (shaders/updatesky.frag) with its lodestar,
// the connect button's star sprite: the sheet's (card: false) or the home card's
// (card: true). It follows UpdateController by itself: the light runs along the
// route as the update comes down, the stars it passes ignite and the relays flash;
// as it comes into the lodestar the star flashes and a wave of light lights the
// rest, as the connect button's landing does; a broken download greys the route
// where it broke.
// The sky colours do not follow the theme, as the button's do not. It moves only
// while `running` (on screen) and something changes: the download, a flash, the
// landing; then the frame stands still and is drawn from its layer.
Item {
    id: root

    property bool card: false
    property bool running: false

    readonly property int updateState: UpdateController.state
    readonly property int updateFailure: UpdateController.failure

    // avail | dl (downloading) | ver (checking the file) | done (the file is here) | err (the download broke off)
    readonly property string phase: {
        switch (updateState) {
        case UpdateEnum.Downloading:
            return UpdateController.progress >= 1 ? "ver" : "dl"
        case UpdateEnum.ReadyToInstall:
        case UpdateEnum.WaitingPermission:
        case UpdateEnum.Installing:
            return "done"
        case UpdateEnum.Failed:
            return updateFailure === UpdateEnum.Network || updateFailure === UpdateEnum.Corrupt ? "err" : "done"
        }
        return "avail"
    }

    // where the download was when it broke off: the controller resets its progress then
    property real lastProgress: 0

    Connections {
        target: UpdateController

        function onProgressChanged() {
            if (UpdateController.state === UpdateEnum.Downloading && UpdateController.progress > 0) {
                root.lastProgress = UpdateController.progress
            }
        }

        function onStateChanged() {
            if (UpdateController.state === UpdateEnum.Downloading && UpdateController.progress === 0) {
                root.lastProgress = 0
            }
        }
    }

    // the light's place along the route (0..1 of its length), eased between the
    // controller's steps
    readonly property real target: phase === "avail" ? 0 : phase === "err" ? lastProgress
                                 : phase === "dl" ? UpdateController.progress : 1
    property real shown: target

    Behavior on shown {
        enabled: root.ready
        NumberAnimation { duration: 450; easing.type: Easing.OutQuad }
    }

    property bool ready: false

    // ------------------------------------------------------------------
    // the route: the sheet's climbs from beyond its left edge into the lodestar at
    // the end of the title row, as on the app icon; the card's runs straight under
    // its text into the lodestar under the percent
    readonly property real scaleX: width / (card ? 328 : 360)
    readonly property point star: card ? Qt.point(width - 24, 46) : Qt.point(width - 50, 46)
    readonly property point p0: card ? Qt.point(16, 46) : Qt.point(-12, 200)
    readonly property point p1: card ? Qt.point(16 + (width - 47) / 3, 46) : Qt.point(40 * scaleX, 120)
    readonly property point p2: card ? Qt.point(16 + 2 * (width - 47) / 3, 46) : Qt.point(214 * scaleX, 98)
    readonly property point p3: card ? Qt.point(width - 31, 46) : star

    // the route's points with the length up to each: the light and the relays go by length
    property var table: []

    function bez(t) {
        const u = 1 - t
        return Qt.point(u * u * u * p0.x + 3 * u * u * t * p1.x + 3 * u * t * t * p2.x + t * t * t * p3.x,
                        u * u * u * p0.y + 3 * u * u * t * p1.y + 3 * u * t * t * p2.y + t * t * t * p3.y)
    }

    function rebuild() {
        const points = []
        let length = 0
        let previous = null
        for (let i = 0; i <= 120; i++) {
            const point = bez(i / 120)
            if (previous) {
                length += Math.hypot(point.x - previous.x, point.y - previous.y)
            }
            points.push({ x: point.x, y: point.y, l: length })
            previous = point
        }
        table = points
    }

    function at(fraction) {
        if (table.length < 2) {
            return p0
        }
        const s = Math.max(0, Math.min(1, fraction)) * table[table.length - 1].l
        let i = 1
        while (i < table.length - 1 && table[i].l < s) {
            i++
        }
        const a = table[i - 1]
        const b = table[i]
        const k = b.l > a.l ? (s - a.l) / (b.l - a.l) : 0
        return Qt.point(a.x + (b.x - a.x) * k, a.y + (b.y - a.y) * k)
    }

    onWidthChanged: rebuild()

    readonly property point head: table.length ? at(shown) : p0

    // ------------------------------------------------------------------
    // the relays (the sheet's route only): each flashes as the light reaches it
    readonly property var relayAt: [0.30, 0.52, 0.72]
    property real glow1: 0
    property real glow2: 0
    property real glow3: 0

    component Flash: NumberAnimation {
        from: 2
        to: 1
        duration: 600
        easing.type: Easing.OutCubic
    }

    Flash { id: flash1; target: root; property: "glow1" }
    Flash { id: flash2; target: root; property: "glow2" }
    Flash { id: flash3; target: root; property: "glow3" }

    function updateRelays() {
        const flashes = [flash1, flash2, flash3]
        const names = ["glow1", "glow2", "glow3"]
        for (let i = 0; i < 3; i++) {
            if (card || phase === "avail" || shown < relayAt[i]) {
                flashes[i].stop()
                root[names[i]] = 0
            } else if (root[names[i]] < 0.5) {
                if (ready) {
                    flashes[i].restart()
                } else {
                    root[names[i]] = 1
                }
            }
        }
    }

    onShownChanged: updateRelays()

    // ------------------------------------------------------------------
    // the landing, as the connect button's: the light comes into the lodestar
    // (the whole file is here) and the star flashes - its rays shoot out, light
    // swells round it - and a soft wave of light runs out over the sky, the stars
    // flaring as it passes them and the rest of them igniting
    readonly property bool atStar: (phase === "ver" || phase === "done") && shown > 0.995
    property real glint: 0          // the star's flash
    property real landed: 0         // the star grown to its landed size
    property real wave: 0           // the wave's radius: the stars inside it are lit
    property real waveAmount: 0     // the wave's light, fading as it runs out
    readonly property real waveReach: width * 1.1
    // past every star, whatever the size (it may not be laid out yet, or change)
    readonly property real arrived: 100000

    ParallelAnimation {
        id: landing

        SequentialAnimation {
            NumberAnimation { target: root; property: "glint"; from: 0; to: 1; duration: 140; easing.type: Easing.OutQuad }
            NumberAnimation { target: root; property: "glint"; to: 0; duration: 1000; easing.type: Easing.InOutSine }
        }
        NumberAnimation { target: root; property: "landed"; from: 0; to: 1; duration: 500; easing.type: Easing.OutCubic }
        NumberAnimation { target: root; property: "wave"; from: 0; to: root.waveReach; duration: 1800; easing.type: Easing.OutCubic }
        NumberAnimation { target: root; property: "waveAmount"; from: 1; to: 0; duration: 1800; easing.type: Easing.InOutSine }

        onFinished: root.wave = root.arrived
    }

    // landed with the light seen coming in, or found landed (the sky made, or the
    // update came down unseen)
    function land(seen) {
        if (seen) {
            landing.restart()
            return
        }
        landing.stop()
        glint = 0
        waveAmount = 0
        landed = 1
        wave = arrived
    }

    onAtStarChanged: {
        if (atStar) {
            land(ready)
        }
    }

    onPhaseChanged: {
        updateRelays()
        // a new download, or none: the sky goes dark again
        if (phase === "avail" || phase === "dl" || phase === "err") {
            landing.stop()
            glint = 0
            landed = 0
            waveAmount = 0
            wave = 0
        }
    }

    // checking the file: the lodestar breathes
    property real breath: 0

    SequentialAnimation on breath {
        running: root.running && root.phase === "ver"
        loops: Animation.Infinite
        NumberAnimation { to: 1; duration: 600; easing.type: Easing.InOutSine }
        NumberAnimation { to: 0; duration: 600; easing.type: Easing.InOutSine }
        onStopped: root.breath = 0
    }

    // the twinkle clock, in step with rendering, only while something moves
    property real time: 0

    FrameAnimation {
        running: root.running && (root.phase === "dl" || root.phase === "ver" || landing.running
                                  || flash1.running || flash2.running || flash3.running)
        onTriggered: root.time += frameTime
    }

    Component.onCompleted: {
        rebuild()
        if (atStar) {
            land(false)
        }
        updateRelays()
        ready = true
    }

    // ------------------------------------------------------------------
    ShaderEffect {
        id: sky

        anchors.fill: parent

        // a still frame is drawn from the layer: the page around may keep the
        // window rendering (the connect button's twinkle)
        layer.enabled: true

        property size itemSize: Qt.size(width, height)
        property real pixel: 1 / Screen.devicePixelRatio
        property real corner: root.card ? 13 : 16
        property real allCorners: root.card ? 1 : 0
        property real vignette: root.card ? 0.25 : 0.42
        property real lit: root.phase === "done" ? 1 : root.shown
        property point glowPos: root.star
        property real glowAmount: (0.55 + 0.45 * root.shown + 0.35 * root.glint) * (root.phase === "err" ? 0.5 : 1)
        property real glowRadius: root.card ? 22 : 72
        property point p0: root.p0
        property point p1: root.p1
        property point p2: root.p2
        property point p3: root.p3
        property point headPos: root.phase === "avail" ? Qt.point(-1000, 0) : root.head
        // on until it is in the star
        property real headOn: root.phase === "err" ? 0.3 : root.phase === "avail" || root.atStar ? 0 : 1
        property real failed: root.phase === "err" ? 1 : 0
        property point relay1: root.card ? Qt.point(-1000, -1000) : root.at(root.relayAt[0])
        property point relay2: root.card ? Qt.point(-1000, -1000) : root.at(root.relayAt[1])
        property point relay3: root.card ? Qt.point(-1000, -1000) : root.at(root.relayAt[2])
        property vector3d relayGlow: Qt.vector3d(root.glow1, root.glow2, root.glow3)
        property real time: root.time
        property real wave: root.wave
        property real scaleX: root.scaleX
        property real cardMode: root.card ? 1 : 0
        property real glint: root.glint
        property real waveAmount: root.waveAmount
        // the lodestar's size against the sheet's: the flash and the glint go with it
        property real starScale: root.card ? 20 / 46 : 1
        // the flash spreads as the wave runs out, as the button's
        property real flashSize: starScale * (12 + 37.5 * Math.min(1, root.wave / Math.max(1, root.waveReach)))

        Behavior on headOn {
            NumberAnimation { duration: 300 }
        }

        Behavior on failed {
            NumberAnimation { duration: 400 }
        }

        fragmentShader: "qrc:/shaders/updatesky.frag.qsb"
    }

    // the lodestar: dim while the update is only offered, brighter as it comes,
    // flashing and growing as the light comes in, breathing while the file is
    // checked, dim again if the download broke off
    Image {
        id: lodestar

        readonly property real size: {
            if (root.phase === "avail" || root.phase === "err") {
                return 0.78
            }
            return 0.78 + 0.17 * root.shown + 0.17 * root.landed + 0.3 * root.glint
        }

        // drawn at its own size (the card's small from the start) and without mipmaps: shown
        // smaller through them it came out as stripes on the emulator's GPU, the sheet's too
        width: root.card ? 20 : 46
        height: width
        x: root.star.x - width / 2
        y: root.star.y - height / 2
        scale: size

        source: "qrc:/images/star.png"
        sourceSize: Qt.size(width * Screen.devicePixelRatio, height * Screen.devicePixelRatio)
        smooth: true

        opacity: {
            switch (root.phase) {
            case "done":
                return 1
            case "ver":
                return Math.min(1, 0.9 + 0.1 * root.breath + root.glint)
            case "dl":
                return 0.55 + 0.35 * root.shown
            case "err":
                return 0.38
            }
            return 0.55
        }
    }
}
