import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

import Style 1.0

import "TextTypes"

Item {
    id: root

    property string headerText
    property string headerTextDisabledColor: DopamineStyle.color.charcoalGray
    property string headerTextColor: DopamineStyle.color.mutedGray

    property alias errorText: errorField.text
    property bool checkEmptyText: false
    property bool rightButtonClickedOnEnter: false

    property string buttonText
    // what the field is for, shown inside it while it is empty; in a multiline
    // field it wraps by words instead of being cut off
    property string hintText
    property string buttonImageSource
    property var clickedFunc

    property alias textField: textField
    property string textFieldTextColor: DopamineStyle.color.paleGray
    property string textFieldTextDisabledColor: DopamineStyle.color.mutedGray

    property bool textFieldEditable: true
    property bool multiline: false
    readonly property string inputText: multiline ? textArea.text : textField.text

    property string borderColor: DopamineStyle.color.slateGray
    property string borderFocusedColor: DopamineStyle.color.paleGray

    property string backgroundColor: DopamineStyle.color.onyxBlack
    property string backgroundDisabledColor: DopamineStyle.color.transparent
    property string bgBorderHoveredColor: DopamineStyle.color.charcoalGray

    implicitWidth: content.implicitWidth
    implicitHeight: content.implicitHeight

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

    ColumnLayout {
        id: content
        anchors.fill: parent

        Rectangle {
            id: backgroud
            Layout.fillWidth: true
            Layout.preferredHeight: input.implicitHeight
            color: root.enabled ? root.backgroundColor : root.backgroundDisabledColor
            radius: 16
            border.color: getBackgroundBorderColor(root.borderColor)
            border.width: 1

            Behavior on border.color {
                PropertyAnimation { duration: 200 }
            }

            RowLayout {
                id: input
                anchors.fill: backgroud
                ColumnLayout {
                    Layout.margins: 16
                    // keep the text clear of the button inside the field
                    Layout.rightMargin: insertButton.visible ? insertButton.width + 20 : 16
                    LabelTextType {
                        text: root.headerText
                        color: root.enabled ? root.headerTextColor : root.headerTextDisabledColor

                        visible: text !== ""

                        Layout.fillWidth: true
                    }

                    TextField {
                        id: textField

                        visible: !root.multiline
                        property bool isFocusable: true

                        Keys.onTabPressed: {
                            FocusController.nextKeyTabItem()
                        }

                        Keys.onBacktabPressed: {
                            FocusController.previousKeyTabItem()
                        }

                        enabled: root.textFieldEditable
                        color: root.enabled ? root.textFieldTextColor : root.textFieldTextDisabledColor

                        inputMethodHints: Qt.ImhNoAutoUppercase | Qt.ImhSensitiveData | Qt.ImhNoPredictiveText

                        placeholderText: root.hintText
                        placeholderTextColor: root.hintText !== "" ? DopamineStyle.color.mutedGray : DopamineStyle.color.charcoalGray

                        selectionColor:  DopamineStyle.color.richBrown
                        selectedTextColor: DopamineStyle.color.paleGray

                        font.pixelSize: 16
                        font.weight: 400
                        font.family: "IBM Plex Mono"

                        height: 24
                        Layout.fillWidth: true

                        topPadding: 0
                        rightPadding: 0
                        leftPadding: 0
                        bottomPadding: 0

                        background: Rectangle {
                            anchors.fill: parent
                            color: root.backgroundDisabledColor
                        }

                        onTextChanged: {
                            root.errorText = ""
                        }

                        onActiveFocusChanged: {
                            if (root.checkEmptyText && text === "") {
                                root.errorText = qsTr("The field can't be empty")
                            }
                        }

                        ContextMenu.menu: ContextMenuType {
                            textObj: textField
                        }

                        onFocusChanged: {
                            backgroud.border.color = getBackgroundBorderColor(root.borderColor)
                        }
                    }

                    // a pasted config is ~20 lines: the field grows up to 160 px,
                    // then scrolls inside its frame instead of painting over the
                    // buttons below
                    ScrollView {
                        id: textAreaScroll

                        visible: root.multiline
                        clip: true

                        Layout.fillWidth: true
                        Layout.preferredHeight: Math.min(160, Math.max(48, textArea.contentHeight,
                                                                       hintItem.visible ? hintItem.implicitHeight : 0))

                        ScrollBar.horizontal.policy: ScrollBar.AlwaysOff

                        TextArea {
                            id: textArea

                            enabled: root.textFieldEditable
                            color: root.enabled ? root.textFieldTextColor : root.textFieldTextDisabledColor

                            wrapMode: TextEdit.Wrap
                            selectByMouse: true
                            inputMethodHints: Qt.ImhNoAutoUppercase | Qt.ImhSensitiveData | Qt.ImhNoPredictiveText
                            placeholderTextColor: DopamineStyle.color.charcoalGray
                            selectionColor: DopamineStyle.color.richBrown
                            selectedTextColor: DopamineStyle.color.paleGray

                            font.pixelSize: 16
                            font.weight: 400
                            font.family: "IBM Plex Mono"

                            rightPadding: 0
                            topPadding: 0
                            leftPadding: 0
                            bottomPadding: 0

                            background: Rectangle {
                                anchors.fill: parent
                                color: root.backgroundDisabledColor
                            }

                            // right click: paste, copy, cut (the field has no paste button)
                            ContextMenu.menu: ContextMenuType {
                                textObj: textArea
                            }

                            Text {
                                id: hintItem

                                anchors.left: parent.left
                                anchors.right: parent.right
                                anchors.top: parent.top
                                visible: root.hintText !== "" && textArea.length === 0 && textArea.preeditText === ""

                                text: root.hintText
                                wrapMode: Text.WordWrap
                                color: DopamineStyle.color.mutedGray
                                font: textArea.font
                            }

                            onTextChanged: {
                                root.errorText = ""
                            }

                            onActiveFocusChanged: {
                                backgroud.border.color = getBackgroundBorderColor(root.borderColor)
                            }
                        }
                    }
                }
            }
        }

        SmallTextType {
            id: errorField

            text: root.errorText
            visible: root.errorText !== ""
            color: DopamineStyle.color.vibrantRed

            Layout.fillWidth: true
        }
    }

    MouseArea {
        anchors.fill: root
        cursorShape: Qt.IBeamCursor

        hoverEnabled: true

        onPressed: function(mouse) {
            if (root.multiline) {
                textArea.forceActiveFocus()
            } else {
                textField.forceActiveFocus()
            }
            mouse.accepted = false

            backgroud.border.color = getBackgroundBorderColor(root.borderColor)
        }

        onEntered: {
            backgroud.border.color = getBackgroundBorderColor(bgBorderHoveredColor)
        }


        onExited: {
            backgroud.border.color = getBackgroundBorderColor(root.borderColor)
        }
    }

    // the field's action button sits inside the field, inset evenly from its
    // edges: centred for one line, in the top corner for several lines
    BasicButtonType {
        id: insertButton

        readonly property int inset: 8

        visible: (root.buttonText !== "") || (root.buttonImageSource !== "")

        focusPolicy: Qt.NoFocus
        text: root.buttonText
        leftImageSource: root.buttonImageSource

        height: root.multiline ? 40 : Math.min(48, backgroud.height - 2 * inset)
        width: root.buttonText !== "" ? implicitWidth : height
        x: backgroud.width - width - inset
        y: root.multiline ? inset : (backgroud.height - height) / 2
        cornerRadius: 16 - inset

        // secondary look: an action on the field, not the page's main button
        defaultColor: DopamineStyle.color.slateGray
        hoveredColor: DopamineStyle.color.charcoalGray
        pressedColor: DopamineStyle.color.mutedGray
        textColor: DopamineStyle.color.paleGray

        clickedFunc: function() {
            if (root.clickedFunc && typeof root.clickedFunc === "function") {
                root.clickedFunc()
            }
        }
    }

    function insertFromClipboard() {
        var field = root.multiline ? textArea : textField
        field.text = ""
        field.paste()
    }

    function getBackgroundBorderColor(noneFocusedColor) {
        var focused = root.multiline ? textArea.focus : textField.focus
        return focused ? root.borderFocusedColor : noneFocusedColor
    }

    Keys.onEnterPressed: {
        if (root.rightButtonClickedOnEnter && root.clickedFunc && typeof root.clickedFunc === "function") {
            clickedFunc()
        }

        // if (KeyNavigation.tab) {
        //     KeyNavigation.tab.forceActiveFocus();
        // }
    }

    Keys.onReturnPressed: {
        if (root.rightButtonClickedOnEnter &&root.clickedFunc && typeof root.clickedFunc === "function") {
            clickedFunc()
        }

        // if (KeyNavigation.tab) {
        //     KeyNavigation.tab.forceActiveFocus();
        // }
    }
}
