import QtQuick
import QtQuick.Layouts
import QtQuick.Window
import QtQuick.Controls as QQC2
import org.kde.kirigami as Kirigami

Rectangle {
    id: page

    required property var app

    readonly property var hostWindow: Window.window
    readonly property var agentList: app.agents ? app.agents.list.filter(a => a.ctx !== null && a.ctx !== undefined) : []
    property int warn: app.settings.warn
    property int critical: app.settings.critical

    implicitWidth: Kirigami.Units.gridUnit * 26
    implicitHeight: Kirigami.Units.gridUnit * 30
    Layout.preferredWidth: Kirigami.Units.gridUnit * 26
    Layout.preferredHeight: Kirigami.Units.gridUnit * 30
    Layout.minimumWidth: Kirigami.Units.gridUnit * 20
    Layout.minimumHeight: Kirigami.Units.gridUnit * 20

    Kirigami.Theme.colorSet: Kirigami.Theme.Window
    Kirigami.Theme.inherit: false
    color: Kirigami.Theme.backgroundColor

    onHostWindowChanged: {
        if (!app.windowed || !hostWindow)
            return
        hostWindow.title = "Claude bar settings"
        hostWindow.width = Layout.preferredWidth
        hostWindow.height = Layout.preferredHeight
    }

    Connections {
        target: page.app
        function onSettingsChanged() {
            if (!warnRow.slider.pressed)
                page.warn = page.app.settings.warn
            if (!criticalRow.slider.pressed)
                page.critical = page.app.settings.critical
        }
    }

    component Heading: QQC2.Label {
        color: page.app.dim
        font.pointSize: Kirigami.Theme.smallFont.pointSize
        font.capitalization: Font.AllUppercase
        font.letterSpacing: 1
        Layout.topMargin: Kirigami.Units.largeSpacing
    }

    component Threshold: RowLayout {
        id: threshold
        property string label
        property int value
        property color tone
        property alias slider: control
        signal moved(int value)
        signal released()
        Layout.fillWidth: true
        spacing: Kirigami.Units.largeSpacing
        QQC2.Label {
            text: threshold.label
            Layout.preferredWidth: Kirigami.Units.gridUnit * 4
        }
        QQC2.Slider {
            id: control
            Layout.fillWidth: true
            from: 30
            to: 95
            stepSize: 5
            snapMode: QQC2.Slider.SnapAlways
            value: threshold.value
            onMoved: threshold.moved(Math.round(value))
            onPressedChanged: {
                if (pressed)
                    return
                value = Qt.binding(() => threshold.value)
                threshold.released()
            }
        }
        QQC2.Label {
            text: threshold.value + "%"
            color: threshold.tone
            font.family: "monospace"
            font.weight: Font.DemiBold
            horizontalAlignment: Text.AlignRight
            Layout.preferredWidth: Kirigami.Units.gridUnit * 2.2
        }
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: Kirigami.Units.gridUnit
        spacing: Kirigami.Units.smallSpacing * 2

        RowLayout {
            spacing: Kirigami.Units.largeSpacing
            Image {
                source: Qt.resolvedUrl("../images/clawd.svg")
                sourceSize: Qt.size(Kirigami.Units.gridUnit * 1.8, Kirigami.Units.gridUnit * 1.2)
                smooth: false
            }
            Kirigami.Heading {
                level: 3
                text: "Claude bar"
            }
        }

        Heading { text: "Context thresholds" }

        Threshold {
            id: warnRow
            label: "Warn"
            value: page.warn
            tone: page.app.ctxWarn
            onMoved: value => {
                page.warn = value
                if (page.critical < value + 5)
                    page.critical = Math.min(95, value + 5)
            }
            onReleased: {
                page.app.saveSetting("warn", page.warn)
                page.app.saveSetting("critical", page.critical)
            }
        }

        Threshold {
            id: criticalRow
            label: "Critical"
            value: page.critical
            tone: page.app.critical
            onMoved: value => {
                page.critical = Math.max(value, page.warn + 5)
            }
            onReleased: page.app.saveSetting("critical", page.critical)
        }

        Item {
            id: scale
            Layout.fillWidth: true
            Layout.topMargin: Kirigami.Units.smallSpacing
            implicitHeight: Kirigami.Units.gridUnit * 1.6
            readonly property real track: Kirigami.Units.smallSpacing * 1.5

            Row {
                width: parent.width
                height: scale.track
                Rectangle { width: parent.width * page.warn / 100; height: parent.height; color: page.app.ok }
                Rectangle { width: parent.width * (page.critical - page.warn) / 100; height: parent.height; color: page.app.ctxWarn }
                Rectangle { width: parent.width * (100 - page.critical) / 100; height: parent.height; color: page.app.critical }
            }
            Repeater {
                model: page.agentList.map(a => a.ctx)
                Rectangle {
                    required property real modelData
                    x: Math.min(scale.width - width, scale.width * modelData / 100)
                    y: scale.track + 2
                    width: Math.max(1, Math.round(Screen.devicePixelRatio)) / Screen.devicePixelRatio * 2
                    height: Kirigami.Units.smallSpacing * 2
                    color: page.app.levelColor(page.app.ctxLevel(modelData), Kirigami.Theme.textColor)
                }
            }
        }
        QQC2.Label {
            Layout.fillWidth: true
            wrapMode: Text.WordWrap
            text: page.agentList.length
                ? "Ticks are your " + page.agentList.length + " live agents."
                : "No live agents reporting context yet."
            color: page.app.dim
            font.pointSize: Kirigami.Theme.smallFont.pointSize
        }

        Heading { text: "Alerts" }

        QQC2.Switch {
            text: "Notify when an agent reaches critical"
            checked: page.app.settings.notify
            onToggled: page.app.saveSetting("notify", checked)
        }

        Heading { text: "Outfits" }

        RowLayout {
            spacing: Kirigami.Units.largeSpacing
            QQC2.ComboBox {
                id: outfitMode
                readonly property var modes: ["auto", "fixed", "off"]
                model: ["Automatic", "Favourite", "Off"]
                currentIndex: Math.max(0, modes.indexOf(page.app.settings.outfits))
                onActivated: index => page.app.saveSetting("outfits", modes[index])
            }
            QQC2.ComboBox {
                visible: page.app.settings.outfits === "fixed"
                readonly property var keys: Object.keys(page.app.outfits)
                model: keys.map(key => page.app.outfits[key].name)
                currentIndex: Math.max(0, keys.indexOf(page.app.settings.outfit_fav))
                onActivated: index => page.app.saveSetting("outfit_fav", keys[index])
            }
        }
        GridLayout {
            visible: page.app.settings.outfits === "auto"
            columns: 2
            columnSpacing: Kirigami.Units.gridUnit
            QQC2.Switch {
                text: "Events"
                checked: page.app.settings.outfit_events
                onToggled: page.app.saveSetting("outfit_events", checked)
            }
            QQC2.Switch {
                text: "Season & clock"
                checked: page.app.settings.outfit_seasons
                onToggled: page.app.saveSetting("outfit_seasons", checked)
            }
            QQC2.Switch {
                text: "Wallpaper"
                checked: page.app.settings.outfit_wallpaper
                onToggled: page.app.saveSetting("outfit_wallpaper", checked)
            }
            QQC2.Switch {
                text: "Random closet"
                checked: page.app.settings.outfit_random
                onToggled: page.app.saveSetting("outfit_random", checked)
            }
        }

        Heading { text: "Claude" }

        QQC2.Switch {
            text: "Playful Claude"
            checked: page.app.settings.playful
            onToggled: page.app.saveSetting("playful", checked)
        }

        Item { Layout.fillHeight: true }
    }
}
