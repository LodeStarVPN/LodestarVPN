import QtQuick
import QtQuick.Window

// The home screen's night, behind everything on PageHome (the owner's design,
// local-tools/design/home/telescope.html in the service repo, 2026-10-16): the
// connect circle is the eye of a telescope standing on a hill under a night sky.
//  - the sky (shaders/homesky.frag) goes with the button: a pool of light round
//    the circle, the circling star's glow spilling past the ring, the landing
//    wave running on out over the sky, the Little Dipper (its handle leading to
//    the circle, the lodestar being Polaris) igniting as the wave passes
//  - the land (shaders/homeland.frag): layered hills and mist, drawn into a
//    layer once and again only while the landed light changes
//  - the telescope (images/telescope/) answers the tap: up the moment we
//    connect, waiting a few degrees under the landing point while the star
//    circles (a telescope is slow, it does not chase it) and taking the last of
//    them with the landing - the star lands only once it is near (ready); down
//    the moment we disconnect. A heavy instrument: it gathers speed and comes to
//    rest softly, 4 s up and 3.6 s down. It turns on the mount's round axis and
//    is aimed by its optical axis. Its lens holds a glint only while the star
//    is in and the tube on it, the wave flashing in it as it passes; the light
//    on the tube and the card comes with the wave and goes smoothly
//  - the connect circle is its eye (ConnectButton's eye* properties, given by
//    PageHome): the sky in it slides by as the tube turns, and at rest it shows
//    the mountain the tube looks at
// Lengths are the design's (a 393 px wide screen) times sc: the land and the
// telescope stand on the top of the server card, the sky's points are taken
// from the circle's centre. The colours do not follow a theme, as the button's
// do not.
Item {
    id: root

    // the connect button, its circle's centre and the server card's top, in this item
    property ConnectButton button
    property point circle
    property real cardTop

    // for the server card: its light from above and its lit top edge as the wave
    // comes to it, and its figures, in once the wave has got there
    readonly property real cardLight: reachT(cardDistance) * landedLight * 0.8
    readonly property real cardEdge: reachT(cardDistance) * landedLight * 0.6
                                     + bell(wave - cardDistance, 60 * sc) * 0.4 * waveAmount
    property real figures: button && button.shownState === "connected" && wave >= cardDistance ? 1 : 0

    Behavior on figures {
        NumberAnimation { duration: 400; easing.type: Easing.InOutSine }
    }

    readonly property real sc: width > 0 ? Math.min(width / 393, 1.35) : 1

    function sceneX(x) {
        return circle.x + (x - 196.5) * sc
    }

    function landY(y) {
        return cardTop + (y - 631) * sc
    }

    function clamp01(v) {
        return Math.max(0, Math.min(1, v))
    }

    function bell(d, width) {
        const k = d / width
        return Math.exp(-k * k)
    }

    // ------------------------------------------------------------------
    // the light: the button's landing runs on out over the screen
    property real wave: 0           // its radius from the landing point
    property real waveAmount: 0
    property real ignite: 0         // the sky's stars inside it are lit
    // the landed star's light over the land: 0 disconnected, a little while
    // connecting, full once it has landed
    property real night: !button ? 0 : button.starsLit ? 1 : button.shownState === "idle" ? 0 : 0.1
    property real scopeLit: button && button.starsLit ? 1 : 0
    readonly property real landedLight: clamp01((night - 0.1) / 0.9)
    readonly property point origin: Qt.point(circle.x, circle.y + (button ? button.landY : -22))
    readonly property real cardDistance: cardTop - origin.y + 20 * sc

    Behavior on night {
        NumberAnimation { duration: 1500; easing.type: Easing.InOutSine }
    }

    Behavior on scopeLit {
        NumberAnimation { duration: 600; easing.type: Easing.InOutSine }
    }

    // how far past a point the wave has gone
    function reachT(distance) {
        return clamp01((wave - distance) / (120 * sc))
    }

    ParallelAnimation {
        id: landing

        NumberAnimation { target: root; property: "wave"; from: 0; to: 760 * root.sc; duration: 2600; easing.type: Easing.OutCubic }
        NumberAnimation { target: root; property: "waveAmount"; from: 1; to: 0; duration: 2600; easing.type: Easing.InOutSine }
    }

    NumberAnimation {
        id: igniteAnimation

        target: root
        property: "ignite"
        from: 0
        to: 900 * root.sc
        duration: 2600
        easing.type: Easing.OutCubic
    }

    // ------------------------------------------------------------------
    // the telescope: a refractor on an alt-azimuth head on a tripod, its own
    // units 0.85 of the design's, the pivot (the altitude axis) at 0,0
    readonly property real unit: 0.85 * sc
    readonly property point pivot: Qt.point(sceneX(330), landY(507.8))
    readonly property real rest: 16         // degrees above level, pointing left
    // aimed at the landing point by its optical axis, 9.5 above the pivot: turned
    // a touch lower than the pivot's own line
    readonly property real aim: {
        const a = pivot.x - origin.x
        const b = pivot.y - origin.y
        return (Math.atan2(b, a) - Math.asin(Math.min(1, 9.5 * unit / Math.max(1, Math.hypot(a, b))))) * 180 / Math.PI
    }

    property bool up: false
    property real upFrom: 0                 // how far up it was when told
    property real upSince: -1e9             // ms on the clock
    property real clock: 0                  // ms, advanced while it moves
    property real angle: rest
    property real angleRate: 0
    property bool moving: false

    // how long it takes, ms (at the owner's word: 1.3 s up and 1.2 s down were
    // too fast, and 2.6 and 2.4 still were)
    readonly property real upTime: 4000
    readonly property real downTime: 3600
    // how many degrees under the landing point it waits while the star circles
    readonly property real waitBelow: 4

    // sine in and out: it gathers speed and comes to rest softly
    function ease(x) {
        if (x <= 0) {
            return 0
        }
        if (x >= 1) {
            return 1
        }
        return 0.5 - 0.5 * Math.cos(Math.PI * x)
    }

    function upAt(time) {
        return upFrom + ((up ? 1 : 0) - upFrom) * ease((time - upSince) / (up ? upTime : downTime))
    }

    // where it is heading: the landing point once up, a few degrees under it
    // while the star is still out
    function target(u) {
        const seek = button && button.starShown ? aim - waitBelow * button.reach : aim
        return rest + (seek - rest) * u
    }

    // near enough for the star to land: the tube takes the last degrees with it
    readonly property bool ready: !up || upAt(clock) >= 0.9

    function setUp(next) {
        if (next === up) {
            return
        }
        upFrom = upAt(clock)    // from wherever it is
        up = next
        upSince = clock
        moving = true
    }

    // critically damped spring towards target: exact step, stable for any dt
    function spring(x, v, goal, lambda, dt) {
        const a = x - goal
        const b = v + lambda * a
        const e = Math.exp(-lambda * dt)
        return [goal + (a + b * dt) * e, (b - lambda * (a + b * dt)) * e]
    }

    function step(dt) {
        clock += dt * 1000
        const goal = target(upAt(clock))
        const r = spring(angle, angleRate, goal, 8, dt)
        angle = r[0]
        angleRate = r[1]
        if (clock - upSince > (up ? upTime : downTime) && Math.abs(angle - goal) < 1e-3 && Math.abs(angleRate) < 1e-2
                && !(button && button.moving)) {
            angle = goal
            angleRate = 0
            moving = false
        }
    }

    // straight to where it should be, for a new layout or the first one
    function settle() {
        upFrom = up ? 1 : 0
        upSince = -1e9
        angle = target(upFrom)
        angleRate = 0
    }

    onAimChanged: {
        if (!moving) {
            settle()
        }
    }

    // up while connected or on the way there; a tap moves it at once, before the
    // controller (which takes the tap on the next turn of the event loop) says so
    function wantUp() {
        return ConnectionController.isConnected
                || (ConnectionController.isConnectionInProgress && !ConnectionController.isDisconnecting)
    }

    property bool tapAhead: false           // a tap's way, until the controller confirms it
    property bool tapUp: false

    function sync() {
        const want = wantUp()
        if (tapAhead) {
            if (want !== tapUp) {
                return
            }
            tapAhead = false
        }
        setUp(want)
    }

    Timer {
        id: tapTimer

        // the controller never followed (a refused connect): what it says goes
        interval: 3000
        onTriggered: {
            root.tapAhead = false
            root.sync()
        }
    }

    Connections {
        target: root.button

        function onClicked() {
            // connected: it disconnects; disconnected: it connects. A tap while
            // connecting may cancel, or be refused while the config is prepared:
            // that waits for the controller
            if (ConnectionController.isConnected || !ConnectionController.isConnectionInProgress) {
                root.tapUp = !ConnectionController.isConnected
                root.tapAhead = true
                tapTimer.restart()
                root.setUp(root.tapUp)
            }
        }

        function onLanded(ignition) {
            landing.restart()
            if (ignition) {
                igniteAnimation.restart()
            }
        }
    }

    Connections {
        target: ConnectionController

        function onConnectionStateChanged() {
            root.sync()
        }
    }

    FrameAnimation {
        running: root.moving || (root.button !== null && root.button.moving && root.up)
        // cap a stalled frame so the tube never jumps
        onTriggered: root.step(Math.min(frameTime, 0.05))
    }

    Component.onCompleted: {
        up = wantUp()
        settle()
    }

    // the lens, where the tube's front is now; the glint and the light go by how far
    // the wave is from it
    readonly property real angleRad: angle * Math.PI / 180
    readonly property point lens: Qt.point(pivot.x + (-79.5 * Math.cos(angleRad) + 9.4 * Math.sin(angleRad)) * unit,
                                           pivot.y + (-79.5 * Math.sin(angleRad) - 9.4 * Math.cos(angleRad)) * unit)
    readonly property real lensDistance: Math.hypot(lens.x - origin.x, lens.y - origin.y)
    readonly property real wavePass: bell(wave - lensDistance, 45 * sc) * waveAmount
    readonly property real tubeLight: 0.15 + 0.45 * scopeLit * reachT(lensDistance - 10 * sc) + 0.2 * wavePass

    // ------------------------------------------------------------------
    // the sky's own stars, a real sky's (shaders/homestars.frag): their shapes are drawn once, into a texture
    // the sky reads - drawn every frame they would cost it some fifty stars a pixel - and again only when the
    // screen's size changes; down to the far hills' line, the lowest about design y 530
    ShaderEffect {
        id: starField

        width: root.width
        height: Math.max(1, Math.min(root.height, root.landY(580)))

        property size itemSize: Qt.size(width, height)
        property real pixel: 1 / Screen.devicePixelRatio
        property real sc: root.sc
        property point circle: root.circle

        fragmentShader: "qrc:/shaders/homestars.frag.qsb"
    }

    ShaderEffectSource {
        id: starTexture

        sourceItem: starField
        hideSource: true
        visible: false
    }

    ShaderEffect {
        id: sky

        anchors.fill: parent

        property size itemSize: Qt.size(width, height)
        property real pixel: 1 / Screen.devicePixelRatio
        property real sc: root.sc
        property point circle: root.circle
        property real cardTop: root.cardTop
        property real time: root.button ? root.button.skyTime : 0
        property real night: root.night
        property real spill: root.button && root.button.starShown && root.button.shownState !== "connected"
                             ? 0.9 * root.button.shine * root.button.reach : 0
        property point spillDir: {
            const p = root.button ? root.button.starPos : Qt.point(0, -1)
            const l = Math.hypot(p.x, p.y) || 1
            return Qt.point(p.x / l, p.y / l)
        }
        property real wave: root.wave
        property real waveAmount: root.waveAmount
        property real ignite: root.ignite
        property real field: root.button ? root.button.field : 0
        property var stars: starTexture
        property size starsSize: Qt.size(starField.width, starField.height)

        fragmentShader: "qrc:/shaders/homesky.frag.qsb"
    }

    ShaderEffect {
        id: land

        // from where the hills can reach (design y 400) down
        x: 0
        y: Math.max(0, root.landY(400))
        width: root.width
        height: Math.max(1, root.height - y)

        // drawn once, again only when something here changes: the window keeps
        // rendering for the button's twinkle
        layer.enabled: true

        property size itemSize: Qt.size(width, height)
        property real pixel: 1 / Screen.devicePixelRatio
        property real sc: root.sc
        property point circle: root.circle
        property real cardTop: root.cardTop
        property real landTop: y
        property real night: root.night

        fragmentShader: "qrc:/shaders/homeland.frag.qsb"
    }

    Item {
        id: telescope

        x: root.pivot.x
        y: root.pivot.y

        // every foot stands on the ground homeland.frag draws (ridge4)
        Image {
            x: -44 * root.unit
            y: 12 * root.unit
            width: 98 * root.unit
            height: 99 * root.unit

            source: "qrc:/images/telescope/tripod.svg"
            sourceSize: Qt.size(width * Screen.devicePixelRatio, height * Screen.devicePixelRatio)
            smooth: true
        }

        // the tube, pointing left, raised by its angle
        Item {
            rotation: root.angle

            Image {
                x: -81 * root.unit
                y: -24 * root.unit
                width: 130 * root.unit
                height: 26 * root.unit

                source: "qrc:/images/telescope/tube.svg"
                sourceSize: Qt.size(width * Screen.devicePixelRatio, height * Screen.devicePixelRatio)
                smooth: true
                antialiasing: true
            }

            // the starlight on its sky side: the roundness of the tube, not an outline
            Image {
                x: -81 * root.unit
                y: -24 * root.unit
                width: 130 * root.unit
                height: 26 * root.unit

                source: "qrc:/images/telescope/tube_lit.svg"
                sourceSize: Qt.size(width * Screen.devicePixelRatio, height * Screen.devicePixelRatio)
                smooth: true
                antialiasing: true
                opacity: root.tubeLight
            }
        }

        // the mount's arm on our side of the tube: it visibly turns on the round hub
        Image {
            x: -8 * root.unit
            y: -8 * root.unit
            width: 19 * root.unit
            height: 25 * root.unit

            source: "qrc:/images/telescope/arm.svg"
            sourceSize: Qt.size(width * Screen.devicePixelRatio, height * Screen.devicePixelRatio)
            smooth: true
        }

        Image {
            x: -8 * root.unit
            y: -8 * root.unit
            width: 19 * root.unit
            height: 25 * root.unit

            source: "qrc:/images/telescope/hub_lit.svg"
            sourceSize: Qt.size(width * Screen.devicePixelRatio, height * Screen.devicePixelRatio)
            smooth: true
            opacity: root.tubeLight
        }
    }

    // the glint in the lens: only while the star is in and the tube is on it,
    // breathing with the star; the wave from the landed star flashes in it on its
    // way past - the telescope has it
    Image {
        readonly property real onStar: !root.button || !root.button.starShown ? 0
                                       : root.bell(root.angle - root.aim, 4) * root.button.shine
                                         * root.clamp01(1 - root.button.reach / 0.3)
        readonly property real breath: root.button && root.button.restingLanded ? (root.button.starTwinkle - 1.01) / 0.07 : 0

        width: 15 * root.sc
        height: width
        x: root.lens.x - width / 2
        y: root.lens.y - height / 2
        scale: 1 + 0.7 * root.wavePass

        source: "qrc:/images/star.png"
        sourceSize: Qt.size(width * Screen.devicePixelRatio, height * Screen.devicePixelRatio)
        smooth: true

        opacity: onStar * (0.55 * root.reachT(root.lensDistance - 20 * root.sc) * (0.87 + 0.13 * breath) + 0.9 * root.wavePass)
        visible: opacity > 0.002
    }
}
