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
    property alias textArea: textArea
    property string textFieldTextColor: DopamineStyle.color.paleGray
    property string textFieldTextDisabledColor: DopamineStyle.color.mutedGray

    property bool textFieldEditable: true
    property bool multiline: false
    readonly property string inputText: multiline ? textArea.text : textField.text

    // what the field can do with its text besides typing (paste it, take it from a file): its
    // FieldActionType items in a strip along the bottom of its frame, under the text
    property alias actions: actionsRow.data

    // a well in the night with the ring's blue at its edge, not the glass of the rows: in the
    // rows' glass with their faint edge it read as a card of text, not a place to put text in
    // (the owner, 2026-10-22: «сливается и походит больше на текст»); brighter blue at the edge
    // and a glow around it while typed in
    property string borderColor: "#596E91FF"
    property string borderFocusedColor: "#BF6E91FF"
    property string glowFocusedColor: "#332757FF"

    property string backgroundColor: "#66020410"
    property string backgroundDisabledColor: DopamineStyle.color.transparent
    property string bgBorderHoveredColor: "#806E91FF"

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

            // the glow around the edge while typed in
            Rectangle {
                anchors.fill: parent
                anchors.margins: -3
                z: -1

                radius: parent.radius + 3
                color: DopamineStyle.color.transparent
                border.width: 3
                border.color: root.glowFocusedColor

                // when the edge is the focused one (getBackgroundBorderColor)
                opacity: (root.multiline ? textArea.focus : textField.focus) ? 1 : 0

                Behavior on opacity {
                    PropertyAnimation { duration: 200 }
                }
            }

            RowLayout {
                id: input
                anchors.fill: backgroud
                ColumnLayout {
                    Layout.margins: 16
                    // keep the text clear of the button inside the field
                    Layout.rightMargin: insertButton.visible ? insertButton.width + 20 : 16
                    // and of the actions' strip under it
                    Layout.bottomMargin: actionsRow.implicitHeight > 0 ? actionsRow.implicitHeight + 14 : 16
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

                            // what goes in here is long (a link, a key, a config): smaller than a
                            // line's text, so more of it shows
                            font.pixelSize: 14
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

                            // right click: paste, copy, cut (a page may add buttons of its own: actions)
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
                                // dimmer than any text on the page, so it reads as a hint and not
                                // as a paragraph
                                color: DopamineStyle.color.charcoalGray
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

        // an action on the field, as those of its strip (FieldActionType): the connected text's
        // blue, the rows' glass under it only while pointed at or pressed (a grey square was out
        // of the app's look, the owner, 2026-10-22)
        defaultColor: DopamineStyle.color.transparent
        hoveredColor: DopamineStyle.color.translucentSlateGray
        pressedColor: "#2E7892FF"
        textColor: DopamineStyle.color.link

        clickedFunc: function() {
            if (root.clickedFunc && typeof root.clickedFunc === "function") {
                root.clickedFunc()
            }
        }
    }

    // a hairline between a one-line field's text and its button, as between the strip's actions
    Rectangle {
        visible: insertButton.visible && !root.multiline

        x: insertButton.x - 4
        width: 1
        height: backgroud.height - 20
        y: 10

        color: "#2E6E91FF"
    }

    // the actions' strip along the bottom of the frame, under a hairline, its actions
    // (FieldActionType) side by side across it; over the field's mouse area, so pressing one does
    // not put the cursor in the text (on a phone that would bring up the keyboard)
    Rectangle {
        visible: actionsRow.implicitHeight > 0

        x: 1
        y: actionsRow.y - 1
        width: backgroud.width - 2
        height: 1

        color: "#2E6E91FF"
    }

    RowLayout {
        id: actionsRow

        x: 1
        y: backgroud.height - height - 1
        width: backgroud.width - 2
        spacing: 0
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
