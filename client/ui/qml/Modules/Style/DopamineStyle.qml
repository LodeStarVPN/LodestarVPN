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
        readonly property color sheerWhite: Qt.rgba(201/255, 209/255, 234/255, 0.12)
        readonly property color translucentWhite: Qt.rgba(201/255, 209/255, 234/255, 0.08)
        readonly property color barelyTranslucentWhite: Qt.rgba(201/255, 209/255, 234/255, 0.05)
        readonly property color translucentMidnightBlack: Qt.rgba(2/255, 4/255, 14/255, 0.7)
        readonly property color softGoldenApricot: Qt.rgba(39/255, 87/255, 255/255, 0.3)
        readonly property color mistyGray: Qt.rgba(211/255, 218/255, 240/255, 0.8)
        readonly property color cloudyGray: Qt.rgba(211/255, 218/255, 240/255, 0.65)
        readonly property color pearlGray: '#E9EDFB'        // titles: the home card's country
        readonly property color translucentRichBrown: Qt.rgba(39/255, 87/255, 255/255, 0.26)
        readonly property color translucentSlateGray: Qt.rgba(120/255, 146/255, 255/255, 0.10)
        readonly property color translucentOnyxBlack: Qt.rgba(12/255, 18/255, 48/255, 0.13)

        // the update sheet's buttons: starlight for the main action, soft glass for the rest
        readonly property color starlight: '#E6ECFF'
        readonly property color starlightHovered: '#F1F4FF'
        readonly property color starlightPressed: '#D2DCFA'
        readonly property color starlightText: '#0C1433'
        readonly property color glassButton: '#14C9D1EA'
        readonly property color glassButtonHovered: '#1FC9D1EA'
        readonly property color glassButtonPressed: '#29C9D1EA'
        readonly property color glassButtonText: '#C9D1EA'
        // a link: the connected text's blue (the ring's own is too deep on the night)
        readonly property color link: '#A3BEFF'
    }

    // one look for the whole app, the night sky's: there is no light theme (the owner's
    // word, 2026-10-16)
    readonly property QtObject color: darkColorPalette
}
