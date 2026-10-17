import QtQuick
import QtQuick.Layouts

// Rows that belong together, in one glass card (GlassSegment): each visible row that has a glass
// property is told where it stands - "single", "first", "middle", "last" - whichever rows the
// platform shows, and the dividers between them are folded away (the card draws its own lines)
ColumnLayout {
    id: root

    spacing: 0

    function arrange() {
        const rows = []
        for (let i = 0; i < children.length; i++) {
            const child = children[i]
            if (child.inGlass !== undefined) {
                child.inGlass = true
            }
            if (child.glass !== undefined && child.visible) {
                rows.push(child)
            }
        }
        for (let i = 0; i < rows.length; i++) {
            rows[i].glass = rows.length === 1 ? "single" : i === 0 ? "first" : i === rows.length - 1 ? "last" : "middle"
        }
    }

    onVisibleChildrenChanged: arrange()
    Component.onCompleted: arrange()
}
