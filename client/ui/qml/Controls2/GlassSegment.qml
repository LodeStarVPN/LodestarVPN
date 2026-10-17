import QtQuick

import Style 1.0

// A row's part of a glass card, as the home's server card is glass (the owner's design,
// local-tools/design/app/screens.html in the service repo): rows that belong together stand in one
// card, a thin line between them. position: "single" (a card of one row), "first", "middle",
// "last". The card stands 16 px in from the row's sides; the row's content goes 16 px further.
// Its edge is drawn by a rectangle reaching past the row where the card goes on, clipped: so only
// the card's outer edge shows
Item {
    id: root

    property string position: "single"
    property bool pressed: false
    // lit by the lodestar: the chosen server, this device
    property bool lit: false

    // where the card begins and ends (top and bottom are Item's own, final)
    readonly property bool opensCard: position === "single" || position === "first"
    readonly property bool closesCard: position === "single" || position === "last"
    readonly property real inset: 16

    clip: true

    Rectangle {
        x: root.inset
        width: root.width - 2 * root.inset
        y: root.opensCard ? 0 : -radius - 1
        height: root.height - y + (root.closesCard ? 0 : radius + 1)

        radius: 16
        color: root.pressed ? "#217892FF" : "#127892FF"
        border.width: 1
        border.color: "#17A9C1FF"

        Behavior on color {
            ColorAnimation { duration: 150 }
        }
    }

    // the lodestar's light on the row it marks
    Rectangle {
        visible: root.lit
        x: root.inset + 1
        width: root.width - 2 * root.inset - 2
        y: root.opensCard ? 1 : 0
        height: root.height - y - (root.closesCard ? 1 : 0)
        topLeftRadius: root.opensCard ? 15 : 0
        topRightRadius: root.opensCard ? 15 : 0
        bottomLeftRadius: root.closesCard ? 15 : 0
        bottomRightRadius: root.closesCard ? 15 : 0

        gradient: Gradient {
            orientation: Gradient.Horizontal
            GradientStop { position: 0.0; color: "#0A3458E1" }
            GradientStop { position: 0.6; color: "#1A3458E1" }
            GradientStop { position: 1.0; color: "#4D3458E1" }
        }
    }

    // between two rows of a card
    Rectangle {
        visible: !root.opensCard
        x: root.inset * 2
        width: root.width - 4 * root.inset
        height: 1
        color: "#13A9C1FF"
    }
}
