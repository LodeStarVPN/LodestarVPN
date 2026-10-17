import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

import Style 1.0
import "../Controls2"
import "../Controls2/TextTypes"

Item {
    id: root

    property bool enabled: true
    property string placeholderText: ""
    property alias textField: searchField.textField

    signal addClicked(string text)
    signal moreClicked()

    implicitWidth: 360
    implicitHeight: 96

    Rectangle {
        id: background
        anchors.fill: parent
        // the night at the page's bottom edge, fading in over the list's last rows, like the panels
        // of the split pages
        gradient: Gradient {
            GradientStop { position: 0.0; color: "#0010173A" }
            GradientStop { position: 0.45; color: DopamineStyle.color.nightBottom }
            GradientStop { position: 1.0; color: DopamineStyle.color.nightBottom }
        }
        z: -1
    }

    RowLayout {
        id: addSiteButton

        enabled: root.enabled
        spacing: 2

        anchors {
            fill: parent
            topMargin: 16
            leftMargin: 16
            rightMargin: 16
            bottomMargin: 24
        }

        TextFieldWithHeaderType {
            id: searchField

            Layout.fillWidth: true
            rightButtonClickedOnEnter: true

            textField.placeholderText: root.placeholderText
            buttonImageSource: "qrc:/images/controls/plus.svg"

            clickedFunc: function() {
                root.addClicked(textField.text)
                textField.text = ""
            }
        }

        ImageButtonType {
            id: addSiteButtonImage
            implicitWidth: 56
            implicitHeight: 56

            image: "qrc:/images/controls/more-vertical.svg"
            imageColor: DopamineStyle.color.paleGray

            onClicked: root.moreClicked()

            Keys.onReturnPressed: addSiteButtonImage.clicked()
            Keys.onEnterPressed: addSiteButtonImage.clicked()
        }
    }
} 
