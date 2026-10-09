import QtQuick
import QtQuick.Layouts
import QtQuick.Shapes

import Style 1.0

import "../Controls2/TextTypes"

// What Google Play Protect shows for an app it does not know yet, and the two
// taps that get past it. A drawing of that window, not a screenshot: Google
// changes its look and words, the order of the taps stays. Shown before the
// install (the user reads it first) and again when Play Protect stopped one
ColumnLayout {
    id: root

    spacing: 12

    // one row of the window to tap, outlined in our accent, with its step number
    component StepRow: Rectangle {
        id: stepRow

        property string label
        property string step
        property bool chevron: false

        Layout.fillWidth: true
        implicitHeight: 44

        radius: 12
        color: "transparent"
        border.width: 2
        border.color: DopamineStyle.color.goldenApricot

        RowLayout {
            anchors.fill: parent
            anchors.leftMargin: 14
            anchors.rightMargin: 10
            spacing: 8

            Text {
                // with the chevron the text keeps its own width, the chevron right after it
                Layout.fillWidth: !stepRow.chevron

                text: stepRow.label
                color: "#A8C7FA"
                font.pixelSize: 15
                font.weight: 500
                elide: Text.ElideRight
            }

            Shape {
                Layout.alignment: Qt.AlignVCenter
                implicitWidth: 12
                implicitHeight: 8

                visible: stepRow.chevron
                layer.enabled: true
                layer.samples: 4

                ShapePath {
                    fillColor: "transparent"
                    strokeColor: "#A8C7FA"
                    strokeWidth: 2
                    capStyle: ShapePath.RoundCap
                    joinStyle: ShapePath.RoundJoin

                    PathSvg { path: "M 1 1 L 6 6 L 11 1" }
                }
            }

            Item {
                Layout.fillWidth: true
                visible: stepRow.chevron
            }

            Rectangle {
                Layout.alignment: Qt.AlignVCenter
                implicitWidth: 24
                implicitHeight: 24

                radius: 12
                color: DopamineStyle.color.goldenApricot

                Text {
                    anchors.centerIn: parent

                    text: stepRow.step
                    color: "#FFFFFF"
                    font.pixelSize: 13
                    font.weight: 700
                }
            }
        }
    }

    SmallTextType {
        Layout.fillWidth: true

        text: qsTr("Google Play Protect may block the installation because it doesn't know our app yet — this happens to apps installed outside Google Play. Tap «More details», then «Install anyway».")
    }

    // the system window is dark or light with the phone; one dark card reads as "that window"
    Rectangle {
        Layout.fillWidth: true
        Layout.topMargin: 4

        implicitHeight: card.implicitHeight + 36
        radius: 24
        color: "#2B2D31"
        border.width: 1
        border.color: "#3C3F44"

        ColumnLayout {
            id: card

            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.margins: 18

            spacing: 12

            RowLayout {
                spacing: 8

                Shape {
                    implicitWidth: 16
                    implicitHeight: 19

                    layer.enabled: true
                    layer.samples: 4

                    ShapePath {
                        fillColor: "#A8C7FA"
                        strokeColor: "transparent"

                        PathSvg { path: "M 8 0 L 16 3 L 16 9 C 16 14 12.5 17.5 8 19 C 3.5 17.5 0 14 0 9 L 0 3 Z" }
                    }
                }

                Text {
                    text: qsTr("Google Play Protect")
                    color: "#C4C7C5"
                    font.pixelSize: 13
                }
            }

            Text {
                Layout.fillWidth: true

                text: qsTr("App blocked to protect your device")
                color: "#E3E3E3"
                font.pixelSize: 19
                font.weight: 500
                wrapMode: Text.WordWrap
            }

            StepRow {
                Layout.topMargin: 4

                label: qsTr("More details")
                step: "1"
                chevron: true
            }

            StepRow {
                label: qsTr("Install anyway")
                step: "2"
            }

            // the big button of that window: it cancels, so it stays dim here
            Rectangle {
                Layout.fillWidth: true
                Layout.topMargin: 4

                implicitHeight: 40
                radius: 20
                color: "#A8C7FA"
                opacity: 0.3

                Text {
                    anchors.centerIn: parent

                    text: qsTr("OK")
                    color: "#062E6F"
                    font.pixelSize: 15
                    font.weight: 500
                }
            }
        }
    }

    CaptionTextType {
        Layout.fillWidth: true

        horizontalAlignment: Text.AlignHCenter
        color: DopamineStyle.color.mutedGray
        font.pixelSize: 13

        text: qsTr("«OK» cancels the update")
    }
}
