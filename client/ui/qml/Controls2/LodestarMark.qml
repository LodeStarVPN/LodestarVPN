import QtQuick
import QtQuick.Window

// The lodestar that marks the chosen one in a list - the chosen server, this device (the owner's
// design, local-tools/design/app/screens.html in the service repo): the connect button's star at
// a row's size. Drawn at its own size and without mipmaps: smaller through them the star came out
// as stripes on the emulator's GPU
Item {
    implicitWidth: 30
    implicitHeight: 30

    Image {
        anchors.fill: parent

        source: "qrc:/images/star.png"
        sourceSize: Qt.size(width * Screen.devicePixelRatio, height * Screen.devicePixelRatio)
        smooth: true
    }
}
