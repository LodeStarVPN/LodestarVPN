import QtQuick
import QtQuick.Window
import QtQuick.Controls
import QtQuick.Layouts
import QtQuick.Shapes
import Qt5Compat.GraphicalEffects

import ConnectionState 1.0
import PageEnum 1.0
import Style 1.0

Button {
    id: root

    // the ring frames the night sky, so its idle colours do not follow the theme
    property string defaultButtonColor: "#283052"
    property string progressButtonColor: "#34427E"
    property string connectedButtonColor: DopamineStyle.color.goldenApricot
    // the text sits on the night sky in both themes
    property string textColor: "#C9D1EA"
    property string connectedTextColor: "#A3BEFF"
    property bool buttonActiveFocus: activeFocus && (Qt.platform.os !== "android" || SettingsController.isOnTv())

    // glow of the ring (shadow opacity, 0..1): eased between states, and
    // breathing while connected
    property real ringGlowBase: 0.3
    property real glowStrength: 1
    readonly property real ringGlow: ringGlowBase * glowStrength

    Behavior on ringGlowBase {
        NumberAnimation { duration: 900; easing.type: Easing.InOutSine }
    }

    // ------------------------------------------------------------------
    // The night sky inside the ring (shaders/nightsky.frag). Idle it is dark
    // and still; while connecting the orbiting star lights the sky around
    // it; on landing a soft wave of light runs out from the star and
    // ignites the background stars, which then twinkle on slow sines.
    readonly property real skyRadius: 92        // under the ring's stroke
    property real skyLit: 0                     // 0 idle .. 1 connected
    property real field: 0                      // background stars on/off
    property real ignite: 0                     // stars within this distance of the landing point are lit
    property real waveRadius: 0
    property real waveAmount: 0
    property real skyTime: 0                    // s, twinkle clock

    Behavior on skyLit {
        NumberAnimation { duration: 1100; easing.type: Easing.InOutSine }
    }

    Behavior on field {
        NumberAnimation { duration: 1000; easing.type: Easing.InOutSine }
    }

    // desktop easter egg: right-click the button; on mobile PageHome
    // triggers the same trip on a shake
    signal rightClicked()

    // ------------------------------------------------------------------
    // The lodestar. Its state is the angle and angular speed on the ring,
    // how far out it is ("reach": 1 on the ring, 0 resting in the
    // middle) and how visible it is. The connection state only sets targets
    // ("intent"); every value is pulled towards its target by a critically
    // damped spring, starting from its current value and rate. So any
    // change - including one that cancels a move halfway - continues from
    // exactly where the star is, with no jump in position or speed:
    //  - "orbit"  (connecting): out to the ring, circling at the orbital
    //    speed; from nothing the star lights up at the top and speeds up;
    //  - "land"   (connected): it spirals into the middle, slowing to a
    //    stop, grows, and the text slides down under it; on arrival a wave
    //    of light ignites the background stars;
    //  - "leave"  (disconnected): back out to the ring, then it glides along
    //    it, slowing to a stop while it shrinks and fades out;
    //  - "trip"   (easter egg): out to the ring for a lap, then lands again.
    // The trail is the star's own recent positions. Frames are advanced by
    // a FrameAnimation, in step with rendering, only while something moves.

    readonly property real orbitRadius: 80      // inside the sky, rays touching the ring
    readonly property real orbitSpeed: 2 * Math.PI / 1.6   // rad/s, a lap in 1.6 s
    readonly property real landY: -22           // landed star, from the button centre
    readonly property real orbitStarSize: 32
    readonly property real landedStarSize: 46
    readonly property real textShiftLanded: 26  // state text moves down under the star

    property string intent: "leave"             // orbit | land | leave | trip
    property string leaveStage: "out"           // out (back to the ring) | glide (to a stop, fading)
    property bool starShown: false
    property bool moving: false                 // the springs have not settled yet
    property real angle: -Math.PI / 2           // clockwise from the right, top = -pi/2
    property real spin: 0                       // rad/s
    property real spinRate: 0
    property real reach: 1                      // 1 on the ring .. 0 in the middle
    property real reachRate: 0
    property real shine: 0                      // 0 gone .. 1 fully visible
    property real shineRate: 0
    property real clock: 0                      // ms, for the trail
    property real speed: 0                      // px/ms, for the trail
    property var history: []                    // recent positions {t, x, y}
    property var trailPts: []
    property bool burstPending: false
    // a quick connection still gets its orbit: the landing, and with it the
    // button's "connected" look and text, waits until the star has lit up
    // and gone about once round
    readonly property real minOrbit: 2000       // ms from the start of the orbit
    property real orbitSince: 0
    property bool holdingLand: false
    property string heldText: ""
    property string shownState: "idle"          // idle | connecting | connected, as the button shows it
    property bool starsLit: false
    property real tripDirection: 1
    property real tripAngle: 0

    readonly property bool restingLanded: starShown && intent === "land" && !moving
    readonly property point starPos: Qt.point(orbitRadius * reach * Math.cos(angle),
                                              landY * (1 - reach) + orbitRadius * reach * Math.sin(angle))
    readonly property real starSize: (orbitStarSize + (landedStarSize - orbitStarSize) * (1 - reach)) * (0.7 + 0.3 * shine)
    // how far the state text has slid down (0..1)
    readonly property real textLift: 1 - reach

    function clamp01(v) {
        return Math.max(0, Math.min(1, v))
    }

    function smoothstep(p) {
        return p * p * (3 - 2 * p)
    }

    // critically damped spring towards target: exact step, stable for any dt
    function spring(x, v, target, lambda, dt) {
        const a = x - target
        const b = v + lambda * a
        const e = Math.exp(-lambda * dt)
        return [target + (a + b * dt) * e, (b - lambda * (a + b * dt)) * e]
    }

    function setIntent(next) {
        if (next === intent && (starShown || next === "leave")) {
            return
        }
        if (!starShown) {
            if (next === "leave") {
                intent = next
                return
            }
            // light up: on the ring at the top for an orbit, in the middle
            // when already connected (app start, tunnel restored)
            angle = -Math.PI / 2
            spin = 0; spinRate = 0; shine = 0; shineRate = 0
            reach = next === "land" ? 0 : 1
            reachRate = 0
            history = []
            trailPts = []
            starShown = true
        }
        if (next === "orbit" && intent !== "orbit") {
            orbitSince = clock
        }
        intent = next
        leaveStage = "out"
        burstPending = next === "land"
        moving = true
    }

    function startTrip() {
        if (!restingLanded) {
            return
        }
        tripDirection = Math.random() < 0.5 ? -1 : 1
        tripAngle = angle
        intent = "trip"
        moving = true
    }

    function step(dt) {
        const dir = spin < -0.01 ? -1 : 1       // keep the current direction
        let targetReach = 1, targetSpin = dir * orbitSpeed, targetShine = 1
        let lReach = 4.5, lSpin = 4.0, lShine = 6.0
        if (intent === "land") {
            targetReach = 0; targetSpin = 0; lSpin = 4.5
        } else if (intent === "trip") {
            targetSpin = tripDirection * orbitSpeed * 1.3; lSpin = 4.5
        } else if (intent === "leave") {
            if (leaveStage === "out" && reach > 0.96) {
                leaveStage = "glide"
            }
            if (leaveStage === "glide") {
                targetSpin = 0; targetShine = 0; lSpin = 3.2; lShine = 3.5
            }
        }
        const spin0 = spin
        let r = spring(reach, reachRate, targetReach, lReach, dt)
        reach = r[0]; reachRate = r[1]
        r = spring(spin, spinRate, targetSpin, lSpin, dt)
        spin = r[0]; spinRate = r[1]
        r = spring(shine, shineRate, targetShine, lShine, dt)
        shine = r[0]; shineRate = r[1]
        angle += (spin0 + spin) / 2 * dt
        clock += dt * 1000

        // trail: the star's own positions a few frames back
        const p = starPos
        const h = history
        const last = h.length ? h[h.length - 1] : null
        speed = last && clock > last.t ? Math.hypot(p.x - last.x, p.y - last.y) / (clock - last.t) : 0
        h.push({ t: clock, x: p.x, y: p.y })
        while (h.length > 2 && h[1].t < clock - 340) {
            h.shift()
        }
        const pts = []
        let j = h.length - 1
        for (let i = 0; i < 16; i++) {
            const t = clock - (i + 1) * 18
            while (j > 0 && h[j - 1].t > t) {
                j--
            }
            if (j === 0 || h[0].t > t) {
                pts.push({ x: h[0].x, y: h[0].y, ok: false })     // no tail before the star appeared
                continue
            }
            const a = h[j - 1], b = h[j]
            const k = (t - a.t) / Math.max(1e-6, b.t - a.t)
            pts.push({ x: a.x + (b.x - a.x) * k, y: a.y + (b.y - a.y) * k, ok: true })
        }
        trailPts = pts

        if (holdingLand && clock - orbitSince >= minOrbit) {
            holdingLand = false
            syncStar()
        }
        if (intent === "trip" && Math.abs(angle - tripAngle) > 1.5 * Math.PI) {
            intent = "land"
            burstPending = true
        }
        if (intent === "land") {
            if (burstPending && reach < 0.06) {         // ~5 px out: it has visibly arrived
                burstPending = false
                burst(!starsLit)
            }
            if (Math.abs(reach) < 5e-4 && Math.abs(reachRate) < 5e-3 && Math.abs(spin) < 1e-3 && Math.abs(spinRate) < 1e-2
                    && Math.abs(shine - 1) < 1e-3 && Math.abs(shineRate) < 1e-2) {
                reach = 0; reachRate = 0; spin = 0; spinRate = 0; shine = 1; shineRate = 0
                speed = 0
                moving = false
            }
        } else if (intent === "leave" && leaveStage === "glide" && shine < 0.004) {
            shine = 0; shineRate = 0; spin = 0; spinRate = 0
            speed = 0
            moving = false
            starShown = false
        }
    }

    function syncStar() {
        holdingLand = false
        if (ConnectionController.isConnectionInProgress) {
            heldText = ConnectionController.connectionStateText
            setIntent("orbit")
            showState("connecting")
        } else if (ConnectionController.isConnected) {
            if (starShown && intent === "orbit" && clock - orbitSince < minOrbit) {
                holdingLand = true      // step() calls back once the orbit has had its time
                return
            }
            setIntent("land")
            showState("connected")
        } else {
            setIntent("leave")
            showState("idle")
        }
    }

    function showState(state) {
        shownState = state
        skyLit = state === "connected" ? 1 : state === "connecting" ? 0.35 : 0
        ringGlowBase = state === "connected" ? 1 : state === "connecting" ? 0.6 : 0.3
        if (state !== "connected") {
            field = 0           // the stars go out while the lodestar is away
            starsLit = false
        }
    }

    Component.onCompleted: syncStar()

    Connections {
        target: ConnectionController

        function onConnectionStateChanged() {
            root.syncStar()
        }

        function onPreparingConfig() {
            PageController.showNotificationMessage(qsTr("Unable to disconnect during configuration preparation"))
        }
    }

    FrameAnimation {
        running: root.moving
        // cap a stalled frame so the star never jumps ahead
        onTriggered: root.step(Math.min(frameTime, 0.05))
    }

    FrameAnimation {
        running: root.field > 0
        onTriggered: root.skyTime += Math.min(frameTime, 0.05)
    }

    SequentialAnimation on glowStrength {
        running: root.shownState === "connected" && root.restingLanded
        loops: Animation.Infinite
        NumberAnimation { to: 0.35; duration: 1600; easing.type: Easing.InOutSine }
        NumberAnimation { to: 1; duration: 1600; easing.type: Easing.InOutSine }
        onStopped: glowSettle.restart()
    }

    NumberAnimation {
        id: glowSettle

        target: root
        property: "glowStrength"
        to: 1
        duration: 600
        easing.type: Easing.InOutSine
    }

    // landing: a wave of light runs out from the star; with ignition the
    // background stars light up as it passes them
    function burst(ignition) {
        waveAnimation.restart()
        if (ignition) {
            field = 1
            starsLit = true
            igniteAnimation.restart()
        }
    }

    readonly property real waveReach: 150       // past the far edge of the sky from the landing point
    readonly property real waveDuration: 1600

    ParallelAnimation {
        id: waveAnimation

        NumberAnimation { target: root; property: "waveRadius"; from: 0; to: root.waveReach; duration: root.waveDuration; easing.type: Easing.OutCubic }
        NumberAnimation { target: root; property: "waveAmount"; from: 1; to: 0; duration: root.waveDuration; easing.type: Easing.InOutSine }
    }

    NumberAnimation {
        id: igniteAnimation

        target: root
        property: "ignite"
        from: 0
        to: root.waveReach
        duration: root.waveDuration
        easing.type: Easing.OutCubic
    }

    property bool isFocusable: true

    Keys.onTabPressed: {
        FocusController.nextKeyTabItem()
    }

    Keys.onBacktabPressed: {
        FocusController.previousKeyTabItem()
    }

    Keys.onUpPressed: {
        FocusController.nextKeyUpItem()
    }

    Keys.onDownPressed: {
        FocusController.nextKeyDownItem()
    }

    Keys.onLeftPressed: {
        FocusController.nextKeyLeftItem()
    }

    Keys.onRightPressed: {
        FocusController.nextKeyRightItem()
    }

    TapHandler {
        acceptedButtons: Qt.RightButton
        enabled: Qt.platform.os !== "android" && Qt.platform.os !== "ios"
        onTapped: root.rightClicked()
    }

    implicitWidth: 190
    implicitHeight: 190

    text: holdingLand ? heldText : ConnectionController.connectionStateText

//    enabled: !ConnectionController.isConnectionInProgress

    background: Item {
        id: canvas

        implicitWidth: parent.width
        implicitHeight: parent.height
        transformOrigin: Item.Center

        ShaderEffect {
            id: sky

            anchors.fill: parent

            property size itemSize: Qt.size(width, height)
            property real pixel: 1 / Screen.devicePixelRatio
            property real radius: root.skyRadius
            property real lit: root.skyLit
            property real time: root.skyTime
            property point glowPos: root.starPos
            property real glowAmount: root.shine * (0.55 + 0.45 * root.textLift)
            property real glowRadius: 20 + 16 * root.textLift
            property point origin: Qt.point(0, root.landY)
            property real waveRadius: root.waveRadius
            property real waveAmount: root.waveAmount
            property real ignite: root.ignite
            property real field: root.field

            fragmentShader: "qrc:/shaders/nightsky.frag.qsb"
        }

        Shape {
            id: backgroundCircle
            width: parent.implicitWidth
            height: parent.implicitHeight
            anchors.bottom: parent.bottom
            anchors.right: parent.right
            layer.enabled: true
            layer.samples: 4
            layer.smooth: true
            layer.effect: DropShadow {
                anchors.fill: backgroundCircle
                horizontalOffset: 0
                verticalOffset: 0
                radius: 12
                samples: 25
                color: root.buttonActiveFocus ? DopamineStyle.color.slateGray
                                              : Qt.rgba(DopamineStyle.color.goldenApricot.r, DopamineStyle.color.goldenApricot.g,
                                                        DopamineStyle.color.goldenApricot.b, root.ringGlow)
                source: backgroundCircle
            }

            ShapePath {
                fillColor: DopamineStyle.color.transparent
                strokeColor: DopamineStyle.color.slateGray
                strokeWidth: root.buttonActiveFocus ? 1 : 0
                capStyle: ShapePath.RoundCap

                PathAngleArc {
                    centerX: backgroundCircle.width / 2
                    centerY: backgroundCircle.height / 2
                    radiusX: 94
                    radiusY: 94
                    startAngle: 0
                    sweepAngle: 360
                }
            }

            ShapePath {
                fillColor: DopamineStyle.color.transparent
                strokeColor: root.shownState === "connected" ? connectedButtonColor
                           : root.shownState === "connecting" ? progressButtonColor : defaultButtonColor
                strokeWidth: root.buttonActiveFocus ? 2 : 3
                capStyle: ShapePath.RoundCap

                Behavior on strokeColor {
                    ColorAnimation { duration: 700; easing.type: Easing.InOutSine }
                }

                PathAngleArc {
                    centerX: backgroundCircle.width / 2
                    centerY: backgroundCircle.height / 2
                    radiusX: 93 - (root.buttonActiveFocus ? 2 : 0)
                    radiusY: 93 - (root.buttonActiveFocus ? 2 : 0)
                    startAngle: 0
                    sweepAngle: 360
                }
            }

            MouseArea {
                anchors.fill: parent

                cursorShape: Qt.PointingHandCursor
                enabled: false
            }
        }

        // trail: the star's own positions a few frames back, fading and
        // thinning out; it shows only while the star moves
        Item {
            id: trail

            anchors.fill: parent
            opacity: root.shine * root.smoothstep(root.clamp01(root.speed / 0.12))
            visible: opacity > 0

            Repeater {
                model: 16

                Rectangle {
                    readonly property var pt: root.trailPts.length > index ? root.trailPts[index] : null
                    readonly property real fade: Math.pow(1 - index / 16, 1.5)

                    // thinner than the star's core: a streak of light behind
                    // the star, not a body of its own
                    width: 1.5 + 4.5 * fade
                    height: width
                    radius: width / 2
                    antialiasing: true
                    x: canvas.width / 2 + (pt ? pt.x : 0) - width / 2
                    y: canvas.height / 2 + (pt ? pt.y : 0) - height / 2

                    color: index < 3 ? "#DCE5FF" : "#9DB4FF"
                    opacity: pt && pt.ok ? 0.75 * fade : 0
                }
            }
        }

        Image {
            id: star

            property real twinkleScale: 1

            width: root.landedStarSize
            height: root.landedStarSize
            x: canvas.width / 2 + root.starPos.x - width / 2
            y: canvas.height / 2 + root.starPos.y - height / 2
            scale: root.starSize / root.landedStarSize * twinkleScale

            source: "qrc:/images/star.png"
            sourceSize: Qt.size(width * Screen.devicePixelRatio, height * Screen.devicePixelRatio)
            smooth: true
            mipmap: true

            opacity: root.shine
            visible: root.starShown && opacity > 0

            SequentialAnimation on twinkleScale {
                running: root.restingLanded
                loops: Animation.Infinite
                NumberAnimation { to: 1.08; duration: 1300; easing.type: Easing.InOutSine }
                NumberAnimation { to: 0.94; duration: 1300; easing.type: Easing.InOutSine }
                onStopped: twinkleSettle.restart()
            }

            NumberAnimation {
                id: twinkleSettle

                target: star
                property: "twinkleScale"
                to: 1
                duration: 400
                easing.type: Easing.InOutSine
            }
        }
    }

    contentItem: Text {
        height: 24

        font.family: "IBM Plex Mono"
        font.weight: 700
        font.pixelSize: 20

        color: root.shownState === "connected" ? connectedTextColor : textColor
        text: root.text

        Behavior on color {
            ColorAnimation { duration: 500; easing.type: Easing.InOutSine }
        }

        horizontalAlignment: Text.AlignHCenter
        verticalAlignment: Text.AlignVCenter

        // slides down in step with the landing star, back up when it leaves
        transform: Translate {
            y: root.textShiftLanded * root.textLift
        }
    }

    onClicked: {
        ServersModel.setProcessedServerIndex(ServersModel.defaultIndex)
        ConnectionController.connectButtonClicked()
    }

    Keys.onEnterPressed: this.clicked()
    Keys.onReturnPressed: this.clicked()
}
