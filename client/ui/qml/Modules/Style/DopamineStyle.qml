pragma Singleton

import QtQuick

QtObject {
    // the night's palette (the owner's design, local-tools/design/app/screens.html in the service
    // repo, 2026-10-17): upstream's greys turned to the home screen's night - its text, its
    // server card's glass, its ring's blue. The names are upstream's
    property QtObject darkColorPalette: QtObject {
        readonly property color transparent: 'transparent'
        readonly property color paleGray: '#D3DAF0'         // text and icons
        readonly property color lightGray: '#DCE3F7'
        readonly property color mutedGray: '#8A93B2'        // descriptions: the home card's subtitle and gear
        readonly property color charcoalGray: '#5C6589'     // disabled, chevrons
        readonly property color slateGray: '#1C2447'        // lines, soft fills
        readonly property color onyxBlack: '#147892FF'      // fields and rows: the home card's glass
        readonly property color midnightBlack: '#040713'    // the night overhead; text on light buttons
        readonly property color nightBottom: '#10173A'      // the night at a page's bottom edge (pagesky.frag)
        readonly property color goldenApricot: '#2757FF'    // the connected ring
        readonly property color burntOrange: '#002BC4'
        readonly property color mutedBrown: '#002BC4'
        readonly property color richBrown: '#2757FF'
        readonly property color deepBrown: '#2757FF'
        readonly property color vibrantRed: '#F08A93'
        readonly property color darkCharcoal: '#121834'
        // pointed at and pressed: the rows' blue glass, as the soft buttons (were a grey-white one)
        readonly property color sheerWhite: Qt.rgba(120/255, 146/255, 255/255, 0.17)
        readonly property color translucentWhite: Qt.rgba(120/255, 146/255, 255/255, 0.10)
        readonly property color barelyTranslucentWhite: Qt.rgba(120/255, 146/255, 255/255, 0.06)
        readonly property color translucentMidnightBlack: Qt.rgba(2/255, 4/255, 14/255, 0.7)
        readonly property color softGoldenApricot: Qt.rgba(39/255, 87/255, 255/255, 0.3)
        readonly property color mistyGray: Qt.rgba(211/255, 218/255, 240/255, 0.8)
        readonly property color cloudyGray: Qt.rgba(211/255, 218/255, 240/255, 0.65)
        readonly property color pearlGray: '#E9EDFB'        // titles: the home card's country
        readonly property color translucentRichBrown: Qt.rgba(39/255, 87/255, 255/255, 0.26)
        readonly property color translucentSlateGray: Qt.rgba(120/255, 146/255, 255/255, 0.10)
        readonly property color translucentOnyxBlack: Qt.rgba(12/255, 18/255, 48/255, 0.13)

        // buttons: soft glass for the second actions - the rows' blue glass, a grey one stood apart
        // from everything else on the night (the owner, 2026-10-22: «дизайн приложения должен
        // соответствовать приложению полностью») - and the main one below (ringButton*)
        readonly property color glassButton: '#1F7892FF'
        readonly property color glassButtonHovered: '#2B7892FF'
        readonly property color glassButtonPressed: '#387892FF'
        readonly property color glassButtonText: '#C9D1EA'
        // the main action, on pages and sheets alike (BasicButtonType's own): glass lit by the
        // connected ring's blue, its edge and glow the ring's light (the owner, 2026-10-22, of the
        // white starlight one: «не в нашей стилистике»; a solid blue was louder than anything else on
        // the night page)
        readonly property color ringButton: '#592757FF'
        readonly property color ringButtonHovered: '#702757FF'
        readonly property color ringButtonPressed: '#852757FF'
        readonly property color ringButtonBorder: '#A66E91FF'
        readonly property color ringButtonText: '#E6ECFF'
        readonly property color ringButtonGlow: '#4D2757FF'
        // a link: the connected text's blue (the ring's own is too deep on the night)
        readonly property color link: '#A3BEFF'
    }

    // one look for the whole app, the night sky's: there is no light theme (the owner's
    // word, 2026-10-16)
    readonly property QtObject color: darkColorPalette
}
