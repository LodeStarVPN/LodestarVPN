import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Qt5Compat.GraphicalEffects

import Style 1.0

import "../Controls2"
import "../Controls2/TextTypes"
import "../Config"

DrawerType2 {
    id: root

    expandedStateContent: Item {
        id: container

        implicitHeight: root.height * 0.9

        Component.onCompleted: {
            root.expandedHeight = container.implicitHeight
        }

        ColumnLayout {
            id: backButtonLayout

            anchors.top: parent.top
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.topMargin: 16

            BackButtonType {
                id: backButton

                Layout.fillWidth: true

                backButtonImage: "qrc:/images/controls/arrow-left.svg"
                backButtonFunction: function() { root.closeTriggered() }
            }

            Header2Type {
                id: header

                Layout.fillWidth: true
                Layout.topMargin: 16
                Layout.rightMargin: 16
                Layout.leftMargin: 16

                headerText: qsTr("Choose language")
            }
        }

        ListViewType {
            id: listView

            anchors.top: backButtonLayout.bottom
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.bottom: parent.bottom

            property int selectedIndex: LanguageModel.currentLanguageIndex

            model: LanguageModel

            ButtonGroup {
                id: buttonGroup
            }

            delegate: Item {
                implicitWidth: root.width
                implicitHeight: delegateContent.implicitHeight

                ColumnLayout {
                    id: delegateContent

                    anchors.fill: parent

                    RadioButton {
                        id: radioButton

                        implicitWidth: parent.width
                        implicitHeight: radioButtonContent.implicitHeight

                        hoverEnabled: true

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

                        // the languages in one glass card; the chosen one lit by the lodestar
                        indicator: GlassSegment {
                            width: parent.width
                            height: parent.height

                            position: listView.count === 1 ? "single" : index === 0 ? "first" : index === listView.count - 1 ? "last" : "middle"
                            pressed: radioButton.pressed || radioButton.hovered
                            lit: radioButton.checked
                        }

                        RowLayout {
                            id: radioButtonContent
                            anchors.fill: parent

                            anchors.rightMargin: 28
                            anchors.leftMargin: 32

                            spacing: 0

                            z: 1

                            ParagraphTextType {
                                Layout.fillWidth: true
                                Layout.topMargin: 20
                                Layout.bottomMargin: 20

                                text: languageName
                            }

                            LodestarMark {
                                visible: radioButton.checked
                            }
                        }

                        ButtonGroup.group: buttonGroup
                        checked: listView.selectedIndex === index

                        onClicked: {
                            listView.selectedIndex = index
                            LanguageModel.changeLanguage(languageIndex)
                            root.closeTriggered()
                        }
                    }
                }

                Keys.onEnterPressed: radioButton.clicked()
                Keys.onReturnPressed: radioButton.clicked()
            }
        }
    }
}
