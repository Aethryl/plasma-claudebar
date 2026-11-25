import QtQuick
import QtQuick.Layouts
import QtQuick.Shapes
import QtQuick.Window
import org.kde.plasma.core as PlasmaCore
import org.kde.plasma.plasmoid
import org.kde.plasma.components as PlasmaComponents
import org.kde.kirigami as Kirigami
import org.kde.plasma.plasma5support as P5Support
import org.kde.notification

PlasmoidItem {
    id: root

    readonly property string script: Qt.resolvedUrl("../code/claudebar.py").toString().replace("file://", "")
    readonly property string command: "python3 '" + script + "'"
    readonly property string remoteScript: "python3 '" + Qt.resolvedUrl("../code/remote.py").toString().replace("file://", "") + "'"
    readonly property string remoteLive: remoteScript + " live"
    readonly property string remoteFleet: "setsid -f " + remoteScript + " fleet >/dev/null 2>&1"
    readonly property string remoteStop: "setsid -f " + remoteScript + " stop >/dev/null 2>&1"
    readonly property var remoteHosts: bar && bar.remote ? bar.remote.slice(0, 4) : []
    readonly property var remoteCosts: remoteHosts.filter(h => !!h.cost).map(h => Object.assign({ host: h.host, stale: !!h.stale }, h.cost))
    readonly property bool remoteStale: remoteCosts.some(h => h.stale)
    readonly property var weekSpend: (costs && costs.projects ? costs.projects.week : []).concat(remoteCosts.reduce((all, h) => all.concat((h.projects || []).slice(0, 6).map(p => ({ name: p.name, cost: p.cost, host: h.host, stale: h.stale }))), []))
    readonly property string costCommand: "python3 '" + Qt.resolvedUrl("../code/costs.py").toString().replace("file://", "") + "'"
    property var costs: null
    property var bar: null
    property real now: Date.now() / 1000
    property real compactWidth: Kirigami.Units.gridUnit * 20
    property Item compactItem: null
    property bool drooped: false

    readonly property real ear: Kirigami.Units.gridUnit * 0.7
    readonly property real bottomRadius: Kirigami.Units.gridUnit * 1.1

    readonly property var agents: bar && bar.agents ? bar.agents : null
    readonly property var everyAgent: agents ? agents.list.reduce((all, a) => all.concat([a], a.workers || []), []) : []
    readonly property var fleet: bar && bar.fleet ? bar.fleet : null
    readonly property var botData: bar && bar.bots ? bar.bots : null
    readonly property var botList: botData ? botData.bots : []
    readonly property var activeBots: botList.filter(b => b.state !== "idle")
    readonly property var idleBots: botList.filter(b => b.state === "idle")
    readonly property var botTotals: botData ? botData.totals : ({ working: 0, blocked: 0, idle: 0, agents: 0, subagents: 0, needs: 0 })
    readonly property int subagentGuess: fleet ? fleet.subagents.working + fleet.subagents.waiting : 0
    readonly property bool windowed: Plasmoid.formFactor === PlasmaCore.Types.Planar || Plasmoid.location === PlasmaCore.Types.Floating
    property var pendingSettings: ({})
    readonly property var settings: Object.assign({ warn: 70, critical: 85, notify: true, playful: false, outfits: "auto", outfit_fav: "pirate", outfit_events: true, outfit_seasons: true, outfit_wallpaper: true, outfit_random: true }, bar && bar.settings ? bar.settings : {}, pendingSettings)
    readonly property string hotLevel: agents ? everyAgent.reduce((worst, a) => {
        const level = ctxLevel(a.ctx)
        return level === "crit" || worst === "crit" ? "crit" : level || worst
    }, "") : ""
    property var notified: ({})
    readonly property var outfits: ({
        party: { name: "Party hat", group: "event", hat: 5 },
        hard: { name: "Hard hat", group: "event", hat: 3 },
        phones: { name: "Headphones", group: "event", hat: 2 },
        crown: { name: "Crown", group: "event", hat: 3 },
        witch: { name: "Witch hat", group: "season", hat: 5 },
        santa: { name: "Santa hat", group: "season", hat: 5 },
        night: { name: "Nightcap", group: "season", hat: 4 },
        bow: { name: "Big bow", group: "wallpaper", hat: 4 },
        cat: { name: "Cat ears", group: "wallpaper", hat: 3 },
        magical: { name: "Magical girl", group: "wallpaper", hat: 3 },
        astro: { name: "Astronaut", group: "wallpaper", hat: 5 },
        captain: { name: "Space captain", group: "wallpaper", hat: 3 },
        aviator: { name: "Aviator", group: "wallpaper", hat: 3 },
        visor: { name: "Cyber visor", group: "wallpaper", hat: 0 },
        retro: { name: "80s headband", group: "wallpaper", hat: 1 },
        explorer: { name: "Pith helmet", group: "wallpaper", hat: 4 },
        pirate: { name: "Pirate", group: "random", hat: 3 },
        cowboy: { name: "Cowboy", group: "random", hat: 4 },
        chef: { name: "Chef", group: "random", hat: 5 },
        wizard: { name: "Wizard", group: "random", hat: 5 },
        viking: { name: "Viking", group: "random", hat: 4 },
        tophat: { name: "Top hat", group: "random", hat: 5 },
        flowers: { name: "Flower crown", group: "random", hat: 2 },
        beret: { name: "Beret", group: "random", hat: 3 },
        grad: { name: "Graduate", group: "random", hat: 2 },
        propeller: { name: "Propeller cap", group: "random", hat: 4 },
        shades: { name: "Sunglasses", group: "random", hat: 0 }
    })
    readonly property var wallpaperOutfits: ({
        "anime-ish": ["bow", "cat", "magical"],
        "space": ["astro", "captain"],
        "spaceships": ["captain", "astro", "aviator"],
        "blueprints": ["aviator", "hard"],
        "pixel-art": ["visor", "phones", "shades"],
        "retro-futurism": ["retro", "shades"],
        "illustration": ["explorer", "cowboy"]
    })

    readonly property color ok: Kirigami.Theme.positiveTextColor
    readonly property color warning: Kirigami.Theme.neutralTextColor
    readonly property color critical: Kirigami.Theme.negativeTextColor
    readonly property color blocked: Kirigami.Theme.neutralTextColor
    readonly property color dim: Qt.alpha(Kirigami.Theme.textColor, 0.7)
    readonly property color active: Kirigami.Theme.activeTextColor
    readonly property color ctxWarn: Qt.tint(Kirigami.Theme.neutralTextColor, Qt.alpha(Kirigami.Theme.negativeTextColor, 0.45))
    readonly property color hairline: Qt.alpha(Kirigami.Theme.textColor, 0.1)

    preferredRepresentation: windowed ? fullRepresentation : compactRepresentation
    activationTogglesExpanded: false
    fullRepresentation: Settings {
        app: root
    }
    Plasmoid.backgroundHints: windowed ? PlasmaCore.Types.DefaultBackground : PlasmaCore.Types.NoBackground

    function pctColor(pct) {
        return pct >= 85 ? critical : pct >= 60 ? warning : ok
    }

    function ctxLevel(pct) {
        if (pct === null || pct === undefined)
            return ""
        return pct >= settings.critical ? "crit" : pct >= settings.warn ? "warn" : ""
    }

    function levelColor(level, fallback) {
        return level === "crit" ? critical : level === "warn" ? ctxWarn : fallback
    }

    function saveSetting(key, value) {
        const next = Object.assign({}, pendingSettings)
        next[key] = value
        pendingSettings = next
        executable.connectSource(command + " set " + key + " '" + JSON.stringify(value) + "' #set")
    }

    function openSettings() {
        root.drooped = false
        executable.connectSource("setsid -f plasmawindowed io.github.aethryl.claudebar >/dev/null 2>&1")
    }

    function checkAlerts() {
        if (windowed || !agents)
            return
        const next = {}
        for (const agent of everyAgent) {
            const key = String(agent.terminal_id)
            const level = ctxLevel(agent.ctx)
            if (level === "crit") {
                next[key] = true
                if (!notified[key] && settings.notify)
                    alert.createObject(root, {
                        title: "Context " + Math.round(agent.ctx) + "% · " + (agent.name || project(agent.cwd)),
                        terminal: key,
                    }).sendEvent()
            } else if (level === "warn" && notified[key]) {
                next[key] = true
            }
        }
        notified = next
    }

    function stateColor(status) {
        return status === "working" ? ok : status === "waiting" ? blocked : status === "error" ? critical : status === "delegating" || status === "done" ? active : dim
    }

    function botColor(state) {
        return state === "working" ? ok : state === "blocked" ? blocked : dim
    }

    function minutes(since) {
        return since ? Math.max(0, Math.round((now - since) / 60)) + "m" : ""
    }

    function timeLeft(resetsAt) {
        if (!resetsAt)
            return ""
        const s = Math.max(0, resetsAt - now)
        const half = v => String(Math.round(v * 2) / 2)
        if (s >= 86400)
            return half(s / 86400) + "d"
        if (s >= 3600)
            return half(s / 3600) + "h"
        return Math.max(1, Math.round(s / 60)) + "m"
    }

    function resetClock(resetsAt) {
        const fmt = resetsAt - now > 86400 ? "ddd HH:mm" : "HH:mm"
        return new Date(resetsAt * 1000).toLocaleString(Qt.locale(), fmt)
    }

    function etaReady(key, win) {
        return !!win && win.start !== undefined && now - win.start >= (key === "seven_day" ? 6 * 3600 : 600)
    }

    function span(key, seconds) {
        const m = Math.max(0, Math.round(seconds / 60))
        const pad = n => String(n).padStart(2, "0")
        if (key === "seven_day" && m >= 1440)
            return Math.floor(m / 1440) + "d " + Math.floor(m % 1440 / 60) + "h"
        if (key === "seven_day" || m >= 60)
            return Math.floor(m / 60) + "h" + pad(m % 60)
        return m + "m"
    }

    function moment(key, t) {
        return new Date(t * 1000).toLocaleString(Qt.locale(), key === "seven_day" ? "ddd HH:mm" : "HH:mm")
    }

    function etaCritical(key, hitsIn) {
        return hitsIn < (key === "seven_day" ? 86400 : 3600)
    }

    function etaColor(key, hitsIn) {
        return etaCritical(key, hitsIn) ? critical : warning
    }

    function project(path) {
        const parts = (path || "").split("/").filter(p => p)
        return parts.length ? parts[parts.length - 1] : "~"
    }

    function focusAgent(terminalId) {
        if (!String(terminalId).startsWith("worktree:"))
            return
        executable.connectSource("\"$HOME/.config/orca/linux-orca-cli-shim/orca\" worktree activate --worktree 'id:" + String(terminalId).slice(9) + "'")
        root.drooped = false
    }

    toolTipMainText: ""
    toolTipSubText: ""

    P5Support.DataSource {
        id: executable
        engine: "executable"
        onNewData: (source, data) => {
            disconnectSource(source)
            if (source === root.costCommand) {
                try {
                    root.costs = JSON.parse(data["stdout"])
                } catch (e) {}
                return
            }
            if (source.endsWith(" #set")) {
                connectSource(root.command)
                return
            }
            if (source !== root.command)
                return
            try {
                root.bar = JSON.parse(data["stdout"])
                root.pendingSettings = {}
            } catch (e) {}
            root.now = Date.now() / 1000
            root.checkAlerts()
        }
    }

    Timer {
        interval: root.drooped ? 2000 : 5000
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: executable.connectSource(root.command)
    }

    Timer {
        interval: 5000
        running: !root.windowed
        repeat: true
        triggeredOnStart: true
        onTriggered: executable.connectSource(root.remoteLive)
    }

    Component.onDestruction: if (!root.windowed) executable.connectSource(root.remoteStop)

    Timer {
        interval: 15 * 60000
        running: !root.windowed
        repeat: true
        triggeredOnStart: true
        onTriggered: executable.connectSource(root.remoteFleet)
    }

    Timer {
        interval: 60000
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: executable.connectSource(root.costCommand)
    }

    function money(value) {
        if (value === undefined || value === null)
            return "–"
        return value >= 1000 ? "$" + (value / 1000).toFixed(1) + "k" : "$" + Math.round(value)
    }

    function count(value) {
        return value >= 1000 ? (value / 1000).toFixed(1) + "k" : String(value || 0)
    }

    function tokens(n) {
        if (n === undefined || n === null)
            return "–"
        if (n >= 1e9)
            return (n / 1e9).toFixed(n >= 1e11 ? 0 : 1) + "B"
        if (n >= 1e6)
            return (n / 1e6).toFixed(n >= 1e8 ? 0 : 1) + "M"
        if (n >= 1e3)
            return (n / 1e3).toFixed(n >= 1e5 ? 0 : 1) + "K"
        return String(n)
    }

    function totalTokens(key) {
        if (!costs || !costs.tokens)
            return null
        return remoteCosts.reduce((sum, h) => sum + (h.tokens ? h.tokens[key] : 0), costs.tokens[key])
    }

    function totalCost(key) {
        const local = costs ? costs[key] : null
        if (local === undefined || local === null)
            return null
        return remoteCosts.reduce((sum, h) => sum + (h[key] || 0), local)
    }

    function hostCosts(key) {
        const local = { host: bar && bar.hostname ? bar.hostname : "local", cost: costs ? costs[key] : 0, stale: false }
        return [local].concat(remoteCosts.map(h => ({ host: h.host, cost: h[key] || 0, stale: h.stale })))
    }

    function modelName(model) {
        const id = String(model || "").toLowerCase().replace(/^claude-/, "")
        const parts = id.split("-").filter(p => !/^\d{8}$/.test(p))
        const name = parts.find(p => /^[a-z]+$/.test(p))
        if (!name)
            return id
        const nums = parts.filter(p => /^\d+$/.test(p))
        return nums.length ? name + " " + nums.join(".") : name
    }

    readonly property var modelPalette: [
        active,
        warning,
        ok,
        critical,
        Kirigami.Theme.highlightColor,
        Qt.tint(Kirigami.Theme.positiveTextColor, Qt.alpha(Kirigami.Theme.activeTextColor, 0.5))
    ]

    function modelColor(name) {
        let h = 0
        for (const c of String(name))
            h = (h * 31 + c.charCodeAt(0)) >>> 0
        return modelPalette[h % modelPalette.length]
    }

    Component {
        id: alert
        Notification {
            id: note
            property string terminal
            componentName: "plasma_workspace"
            eventId: "notification"
            iconName: "dialog-warning"
            text: "Auto-compact is close."
            urgency: Notification.HighUrgency
            defaultAction: NotificationAction {
                onActivated: root.focusAgent(note.terminal)
            }
            actions: [
                NotificationAction {
                    label: "Focus"
                    onActivated: root.focusAgent(note.terminal)
                }
            ]
        }
    }

    Plasmoid.contextualActions: [
        PlasmaCore.Action {
            text: "Playful Claude"
            checkable: true
            checked: root.settings.playful
            onTriggered: root.saveSetting("playful", checked)
        },
        PlasmaCore.Action {
            text: "Settings…"
            icon.name: "configure"
            onTriggered: root.openSettings()
        }
    ]

    component Clawd: Item {
        id: clawd
        readonly property real dpr: Screen.devicePixelRatio || 1
        readonly property int dot: Math.max(1, Math.round(Kirigami.Units.gridUnit * 0.7 * dpr / 12))
        readonly property real px: dot / dpr
        readonly property bool playful: root.settings.playful
        readonly property bool still: Kirigami.Units.longDuration === 0
        readonly property int working: root.fleet ? root.fleet.orchestrators.working + root.fleet.orchestrators.delegating : root.agents ? root.agents.working : 0
        readonly property int waiting: root.fleet ? root.fleet.orchestrators.waiting + root.fleet.subagents.waiting : root.agents ? root.agents.blocked : 0
        readonly property int failed: root.fleet ? root.fleet.subagents.error : 0
        readonly property bool delegating: !!root.fleet && root.fleet.orchestrators.working === 0 && root.fleet.orchestrators.delegating > 0
        readonly property var frames: ({
            walk: ["clawd-walk-a", "clawd-walk-b"],
            type: ["clawd-type-a", "clawd-type-b"],
            hop: ["clawd", "clawd-walk-b", "clawd", "clawd-walk-a"],
            scan: ["clawd-look-l", "clawd-look-l", "clawd-walk-b", "clawd-look-r", "clawd-look-r", "clawd-walk-a"],
            turn: ["clawd-walk-a", "clawd-walk-b", "clawd-walk-a", "clawd-walk-b"],
            wave: ["clawd-wave-up", "clawd-wave-mid"],
            dance: ["clawd-cheer", "clawd"],
            lookaround: ["clawd-look-l", "clawd-look-l", "clawd", "clawd-look-r", "clawd-look-r", "clawd"],
            stretch: ["clawd-cheer", "clawd-cheer", "clawd-cheer", "clawd"],
            alarm: ["clawd-sweat-a", "clawd-sweat-b"]
        })
        readonly property var cues: ({
            wind: [[0.35, "clawd-look-l"], [0.7, "clawd-look-r"], [1, "clawd-look-l"], [1.6, "clawd"], [1.72, "clawd-blink"], [2, "clawd"], [2.5, "clawd-yawn-a"], [3.1, "clawd-yawn-b"], [3.4, "clawd-yawn-a"], [3.8, "clawd-doze"]],
            nod: [[1.6, "clawd-squish"], [2, "clawd-nod-1"], [2.4, "clawd-nod-2"], [2.7, "clawd-nod-up"], [3.6, "clawd-squish"], [4.2, "clawd-doze"], [4.8, "clawd-nod-1"], [5.4, "clawd-nod-2"], [5.7, "clawd-nod-up"], [6.4, "clawd-squish"], [7, "clawd-nod-1"], [8.4, "clawd-nod-2"], [9, "clawd-nod-3"]],
            wake: [[0.5, "clawd-cheer"], [0.65, "clawd-squish"], [0.9, "clawd-look-l"], [1.15, "clawd-look-r"], [1.4, "clawd-look-l"], [1.8, "clawd"]]
        })
        readonly property var names: ["clawd", "clawd-blink", "clawd-walk-a", "clawd-walk-b", "clawd-type-a", "clawd-type-b", "clawd-wave-up", "clawd-wave-mid", "clawd-cheer", "clawd-look-l", "clawd-look-r", "clawd-sweat-a", "clawd-sweat-b", "clawd-squish", "clawd-happy", "clawd-sleepy", "clawd-yawn-a", "clawd-yawn-b", "clawd-doze", "clawd-nod-up", "clawd-nod-1", "clawd-nod-2", "clawd-nod-3", "clawd-lie", "clawd-lie-blink", "clawd-lie-sl", "clawd-lie-in"]
        readonly property var hatShift: ({ "clawd-squish": [0, 1], "clawd-doze": [0, 1], "clawd-nod-1": [0, 2], "clawd-nod-2": [1, 3], "clawd-nod-3": [1, 4] })
        readonly property var routines: ["walk", "type", "hop", "scan", "turn"]
        property string routine: "walk"
        property bool flipped: false
        property bool dancing: false
        property bool blinking: false
        property string fidget: ""
        property int step: 0
        property int lastWorking: 0
        property real homeX: 0
        property real minX: 0
        property real maxX: 0
        property real pointerX: -1
        property bool pointerOnHim: false
        property string reaction: ""
        property string lastReaction: ""
        property real lastClick: 0
        property int waving: 0
        property int startle: 0
        property real rub: 0
        property real lastRubX: -1
        property string petFace: "clawd-squish"
        property string baseOutfit: ""
        property real partyUntil: 0
        property real crownUntil: 0
        property real lastWeekReset: -1
        property string wornOutfit: ""
        property string nextOutfit: ""
        property int puff: -1
        property string rest: ""
        property real restClock: 0
        property real waking: -1
        property string hobby: ""
        property bool tucking: false
        readonly property bool parked: waking >= 0 || rest !== "" && !(rest === "wind" && restClock === 0)
        readonly property int roomLeft: Math.floor((pos - minX) / px)
        readonly property int roomRight: Math.floor((homeX - pos) / px)
        readonly property int roomAbove: Math.floor(y / px)
        readonly property int roomBelow: parent ? Math.floor((parent.height - y - height) / px) : 0
        readonly property int sideRoom: Math.max(roomLeft, roomRight)
        readonly property bool bedFits: roomRight - 18 >= -roomLeft
        readonly property int bedX: Math.max(-roomLeft, Math.min(roomRight - 18, -6))
        readonly property bool inBed: rest === "sleep" && bedFits
        readonly property bool breathing: restClock > 1.5 && restClock % 3 < 1.5
        readonly property real bodyX: inBed ? (bedX + 6) * px : 0
        readonly property real bodyY: inBed ? -px * (breathing ? 5 : 4) : 0
        readonly property real beat: restClock % 6
        readonly property bool tug: hobby === "fish" && beat > 3.6 && beat < 4.6
        readonly property real sip: hobby === "sip" && beat > 2 && beat < 4 ? Math.sin((beat - 2) / 2 * Math.PI) : 0
        readonly property int rodLen: Math.max(4, Math.min(10, sideRoom - 1, 6 + roomAbove))
        readonly property int bobY: Math.min(16 + (tug ? 3 : Math.round(Math.sin(restClock * 2))), 10 + roomBelow)
        readonly property real snoreFrom: rest === "sleep" ? 1.8 : rest === "nod" ? 8.4 : -1
        readonly property point snoreAt: inBed ? Qt.point(bedX + 20, -1) : rest === "sleep" ? Qt.point(16, 3) : Qt.point(flipped ? -4 : 18, 3)
        readonly property string restFrame: rest === "wind" || rest === "nod" ? cue(cues[rest], restClock)
            : rest === "sleep" ? (restClock < 1.2 ? "clawd-lie" : restClock < 1.4 ? "clawd-lie-blink" : breathing && !bedFits ? "clawd-lie-in" : "clawd-lie-sl")
            : beat < 0.3 ? "clawd"
            : hobby === "read" ? (blinking ? "clawd-blink" : Math.floor(beat / 0.7) % 2 ? "clawd-look-r" : "clawd-look-l")
            : hobby === "sip" ? (sip > 0.5 ? "clawd-sleepy" : "clawd")
            : tug ? "clawd-look-r" : blinking ? "clawd-blink" : "clawd"
        readonly property var wallpaperPool: root.bar && root.bar.wallpaper ? root.wallpaperOutfits[root.bar.wallpaper] || [] : []
        readonly property string eventOutfit: !root.settings.outfit_events ? ""
            : partyUntil > root.now * 1000 ? "party"
            : crownUntil > root.now * 1000 ? "crown"
            : working >= 3 ? "hard"
            : root.bar && root.bar.music ? "phones"
            : ""
        readonly property string wantedOutfit: still || root.settings.outfits === "off" ? ""
            : root.settings.outfits === "fixed" ? root.settings.outfit_fav
            : eventOutfit || baseOutfit
        readonly property int hatHeight: wornOutfit && root.outfits[wornOutfit] ? root.outfits[wornOutfit].hat : 0
        readonly property bool busy: mood === "wave" || mood === "alarm" || mood === "dance"
        readonly property bool hovering: pointerX >= 0
        readonly property bool petting: pointerOnHim && rub > px * 30
        readonly property bool chasing: hovering && !busy && !parked && reaction === "chase"
        readonly property bool fleeing: !busy && reaction === "shy" && flee >= 0
        property real flee: -1
        readonly property real chaseX: Math.max(minX, Math.min(maxX, pointerX - width / 2))
        property real originX: 0
        property real wander: -1
        property bool settled: false
        property real pos: 0
        property int tick: 0
        readonly property bool roams: !still && homeX - minX > width * 2
        readonly property bool roaming: mood === "work"
        readonly property real target: parked ? pos
            : chasing ? chaseX
            : fleeing ? flee
            : roams && wander >= 0 ? Math.max(minX, Math.min(wander, homeX)) : homeX
        readonly property bool moving: settled && Math.abs(pos - target) > 0.01
        property bool heading: false
        readonly property int stride: Math.floor(tick / 3) % 2
        readonly property string mood: dancing ? "dance" : waiting > 0 ? "wave" : root.hotLevel !== "" || failed > 0 ? "alarm" : working > 0 ? "work" : "idle"
        readonly property string act: mood === "work" ? (delegating ? "walk" : routine) : mood
        readonly property real shiver: !still && mood === "alarm" && root.hotLevel === "crit" && step % 2 === 1 ? px : 0
        readonly property string lookFrame: pointerX < pos + width / 2 - px * 3 ? "clawd-look-l" : pointerX > pos + width / 2 + px * 3 ? "clawd-look-r" : "clawd"
        readonly property string frame: still ? (mood === "alarm" ? "clawd-sweat-a" : "clawd")
            : waking >= 0 ? cue(cues.wake, waking)
            : rest !== "" && parked ? restFrame
            : petting ? (step % 6 < 4 ? petFace : "clawd-cheer")
            : startle > 0 ? "clawd-cheer"
            : waving > 0 ? (waving % 4 < 2 ? "clawd-wave-up" : "clawd-wave-mid")
            : moving && mood !== "alarm" ? frames.walk[stride]
            : chasing ? "clawd-cheer"
            : hovering && !busy ? (pointerOnHim ? (blinking ? "clawd-blink" : "clawd") : lookFrame)
            : frames[act] ? frames[act][step % frames[act].length]
            : fidget !== "" ? frames[fidget][Math.min(step, frames[fidget].length - 1)]
            : blinking ? "clawd-blink" : "clawd"
        readonly property real lift: still || jump > 0 ? 0
            : moving ? stride * px
            : (act === "walk" || act === "turn") && step % 2 === 1 ? px
            : 0
        readonly property real barTop: 3
        property real jump: 0
        property real jumpHeight: 0

        function cue(list, t) {
            for (const entry of list)
                if (t < entry[0])
                    return entry[1]
            return list[list.length - 1][1]
        }

        function nodOff() {
            bedtime.interval = 120000 + Math.random() * 120000
            rest = "nod"
            restClock = 0
        }

        function pickHobby() {
            flipped = roomLeft > roomRight
            const fits = sideRoom >= 5 ? ["read", "sip", "fish"] : ["read"]
            const pool = fits.length > 1 ? fits.filter(h => h !== hobby) : fits
            hobby = pool[Math.floor(Math.random() * pool.length)]
            rest = "chill"
            restClock = 0
        }

        function tuck() {
            tucking = true
            if (puff < 0 || puff > 2) {
                nextOutfit = wantedOutfit
                puff = 0
            }
        }

        function wake() {
            if (rest === "wind" && restClock === 0) {
                rest = ""
                return
            }
            if (inBed)
                pos += bodyX
            rest = ""
            tucking = false
            restClock = 0
            waking = 0
            leap(0.6)
        }

        function leap(share) {
            const headroom = mapToItem(null, 0, 0).y + px * 2 - barTop - px * 3 - hatHeight * px
            if (still || leaping.running || headroom < px * 2)
                return
            jumpHeight = Math.round(headroom * share * dpr) / dpr
            leaping.restart()
        }

        SequentialAnimation {
            id: leaping
            NumberAnimation { target: clawd; property: "jump"; to: clawd.jumpHeight; duration: 150 + clawd.jumpHeight * 8; easing.type: Easing.OutQuad }
            NumberAnimation { target: clawd; property: "jump"; to: 0; duration: 150 + clawd.jumpHeight * 8; easing.type: Easing.InQuad }
        }

        width: px * 18
        height: px * 12
        x: Math.round((pos - originX) * dpr) / dpr
        property real lastHome: 0
        onHomeXChanged: {
            if (!settled || (wander < 0 && Math.abs(pos - lastHome) < 0.5))
                pos = homeX
            lastHome = homeX
        }
        Component.onCompleted: Qt.callLater(() => {
            clawd.pos = clawd.target
            clawd.lastHome = clawd.homeX
            clawd.pickOutfit("start")
            clawd.wornOutfit = clawd.wantedOutfit
            clawd.settled = true
        })
        Connections {
            target: root
            function onBarChanged() {
                const week = root.bar && root.bar.seven_day ? root.bar.seven_day.resets_at || 0 : 0
                if (clawd.lastWeekReset > 0 && week > clawd.lastWeekReset + 3600)
                    clawd.crownUntil = Date.now() + 600000
                if (week > 0)
                    clawd.lastWeekReset = week
            }
        }

        function pickOutfit(reason) {
            const s = root.settings
            const today = new Date()
            const day = Math.floor(today.getTime() / 86400000)
            const season = !s.outfit_seasons ? ""
                : today.getMonth() === 9 ? "witch"
                : today.getMonth() === 11 ? "santa"
                : (today.getHours() >= 23 || today.getHours() < 5) && day % 3 !== 0 ? "night"
                : ""
            const closet = s.outfit_random ? Object.keys(root.outfits).filter(k => root.outfits[k].group === "random").concat([""]) : []
            const walls = s.outfit_wallpaper ? wallpaperPool : []
            let pool = []
            if (season && Math.random() < 0.5)
                pool = [season]
            else if (reason === "wallpaper" && walls.length)
                pool = walls
            else if (walls.length && Math.random() < 0.6)
                pool = walls
            else
                pool = closet.length ? closet : walls
            pool = pool.filter(o => o !== baseOutfit)
            if (pool.length)
                baseOutfit = pool[Math.floor(Math.random() * pool.length)]
        }

        onWantedOutfitChanged: {
            if (!settled || still || rest !== "") {
                wornOutfit = wantedOutfit
                return
            }
            nextOutfit = wantedOutfit
            if (puff < 0) {
                puff = 0
                leap(0.5)
            }
        }
        onWallpaperPoolChanged: if (settled && root.settings.outfit_wallpaper) pickOutfit("wallpaper")
        onStillChanged: if (still) {
            rest = ""
            waking = -1
            tucking = false
        }

        function pointerEntered() {
            if (busy || rest !== "")
                return
            const pool = [["wave", 30], ["chase", 25], ["pet", 20], ["watch", 15], ["shy", Date.now() - lastClick < 60000 ? 0 : 10]]
                .filter(entry => entry[0] !== lastReaction && entry[1] > 0)
            let n = Math.random() * pool.reduce((sum, entry) => sum + entry[1], 0)
            reaction = pool[pool.length - 1][0]
            for (const entry of pool) {
                n -= entry[1]
                if (n < 0) {
                    reaction = entry[0]
                    break
                }
            }
            lastReaction = reaction
            petFace = Math.random() < 0.5 ? "clawd-squish" : "clawd-happy"
        }

        function pointerMoved(x, onHim) {
            if (onHim && lastRubX >= 0)
                rub += Math.abs(x - lastRubX)
            lastRubX = x
            pointerX = x
            const entering = onHim && !pointerOnHim
            pointerOnHim = onHim
            if (rest !== "") {
                if (onHim)
                    wake()
                return
            }
            if (busy)
                return
            if (entering && reaction === "wave" && waving === 0) {
                waving = 12
                leap(0.6)
            }
            if (reaction === "shy" && flee < 0 && Math.abs(x - (pos + width / 2)) < width * 1.5) {
                startle = 4
                leap(1)
                flee = x < pos + width / 2 ? Math.min(maxX, pos + width * 6) : Math.max(minX, pos - width * 6)
                heading = flee < pos
            }
        }

        function pointerLeft() {
            pointerX = -1
            pointerOnHim = false
            lastRubX = -1
            reaction = ""
            shyReturn.restart()
        }

        function clicked() {
            lastClick = Date.now()
            rub = px * 60
            pointerOnHim = true
            leap(0.6)
        }

        function walkTo(spot) {
            if (moving)
                return
            const next = spot < 0 ? homeX : Math.max(minX, Math.min(spot, homeX))
            if (Math.abs(next - pos) < width)
                return
            heading = next < pos
            wander = spot
        }

        function pickSpot() {
            walkTo(minX + Math.random() * Math.max(0, homeX - minX))
        }

        function goHome() {
            if (wander < 0)
                return
            heading = homeX < pos
            wander = -1
        }

        onMoodChanged: {
            if (rest !== "")
                wake()
            step = 0
            flipped = false
            if (!roaming)
                homeCall.restart()
        }
        onWorkingChanged: {
            if (lastWorking > 0 && working === 0 && waiting === 0 && !still) {
                step = 0
                dancing = true
                danceEnd.restart()
                partyUntil = Date.now() + 60000
            }
            lastWorking = working
        }

        Repeater {
            model: clawd.names
            Image {
                required property string modelData
                x: clawd.shiver + clawd.bodyX
                y: -clawd.lift - Math.round(clawd.jump * clawd.dpr) / clawd.dpr + clawd.bodyY
                width: clawd.width
                height: clawd.height
                visible: modelData === clawd.frame && (clawd.puff < 1 || clawd.puff > 2)
                mirror: clawd.moving ? clawd.heading : clawd.flipped
                source: Qt.resolvedUrl("../images/" + modelData + ".svg")
                sourceSize: Qt.size(clawd.width, clawd.height)
                smooth: false
            }
        }

        Timer {
            interval: clawd.playful ? 170 : 340
            running: !clawd.still && clawd.visible && (clawd.mood !== "idle" || clawd.fidget !== "" || clawd.hovering || clawd.rub > 0.5 || clawd.waving > 0 || clawd.startle > 0)
            repeat: true
            onTriggered: {
                clawd.step += 1
                clawd.rub *= 0.7
                if (clawd.waving > 0)
                    clawd.waving -= 1
                if (clawd.startle > 0)
                    clawd.startle -= 1
                if (clawd.chasing && !clawd.moving && clawd.step % 6 === 0)
                    clawd.leap(0.8)
                if (clawd.act === "hop" && clawd.step % 4 === 1)
                    clawd.leap(0.7)
                if (clawd.act === "dance" && clawd.step % 2 === 0)
                    clawd.leap(1)
                if (clawd.act === "turn" && clawd.step % 4 === 0)
                    clawd.flipped = !clawd.flipped
                if (clawd.mood === "idle" && clawd.fidget !== "" && clawd.step >= clawd.frames[clawd.fidget].length) {
                    clawd.fidget = ""
                    clawd.step = 0
                }
            }
        }
        Timer {
            interval: clawd.playful ? 60 : 80
            running: clawd.moving && clawd.visible
            repeat: true
            onTriggered: {
                const left = clawd.target - clawd.pos
                clawd.heading = left < 0
                clawd.pos += Math.sign(left) * Math.min(Math.abs(left), clawd.px * 2)
                clawd.tick += 1
                if (clawd.tick % 12 === 0 && Math.random() < (clawd.playful ? 0.35 : 0.15))
                    clawd.leap(0.5)
            }
        }
        Timer {
            id: strollBack
            interval: 12000
            onTriggered: if (clawd.mood === "idle") clawd.goHome()
        }
        Timer {
            id: homeCall
            interval: 4000
            onTriggered: if (!clawd.roaming) clawd.goHome()
        }
        Timer {
            id: danceEnd
            interval: 2400
            onTriggered: clawd.dancing = false
        }
        Timer {
            interval: 4000
            running: !clawd.still && clawd.visible && (clawd.mood === "idle" || clawd.pointerOnHim) && clawd.fidget === ""
            repeat: true
            onTriggered: {
                interval = 4000 + Math.random() * 3000
                clawd.blinking = true
                unblink.restart()
            }
        }
        Timer {
            id: unblink
            interval: 150
            onTriggered: clawd.blinking = false
        }
        Timer {
            interval: 25000
            running: !clawd.still && clawd.visible && clawd.mood === "idle" && !clawd.hovering && clawd.rest === ""
            repeat: true
            onTriggered: {
                interval = clawd.playful ? 20000 + Math.random() * 20000 : 40000 + Math.random() * 40000
                clawd.step = 0
                if (clawd.moving)
                    return
                if (clawd.wander >= 0) {
                    clawd.goHome()
                    return
                }
                if (clawd.roams && Math.random() < (clawd.playful ? 0.5 : 0.7)) {
                    clawd.pickSpot()
                    strollBack.restart()
                    return
                }
                if (clawd.playful)
                    clawd.fidget = Math.random() < 0.6 ? "lookaround" : "stretch"
            }
        }
        Timer {
            interval: 9000
            running: !clawd.still && clawd.visible && clawd.mood === "work"
            repeat: true
            onTriggered: {
                interval = (clawd.playful ? 5000 : 9000) + Math.random() * 6000
                const others = clawd.routines.filter(r => r !== clawd.routine)
                clawd.routine = others[Math.floor(Math.random() * others.length)]
                clawd.step = 0
                clawd.flipped = false
                if (clawd.roams && !clawd.moving)
                    Math.random() < 0.3 ? clawd.goHome() : clawd.pickSpot()
            }
        }
        Image {
            readonly property var shift: clawd.hatShift[clawd.frame] || [0, 0]
            x: clawd.shiver + (mirror ? -shift[0] : shift[0]) * clawd.px
            y: -clawd.lift - Math.round(clawd.jump * clawd.dpr) / clawd.dpr - clawd.px * (4 - shift[1])
            width: clawd.width
            height: clawd.px * 16
            visible: clawd.wornOutfit !== "" && !clawd.frame.startsWith("clawd-lie") && (clawd.puff < 1 || clawd.puff > 2)
            mirror: clawd.moving ? clawd.heading : clawd.flipped
            source: clawd.wornOutfit ? Qt.resolvedUrl("../images/outfits/" + clawd.wornOutfit + ".svg") : ""
            sourceSize: Qt.size(width, height)
            smooth: false
        }
        Repeater {
            model: 12
            Rectangle {
                required property int index
                readonly property real angle: index / 12 * Math.PI * 2
                readonly property real radius: (3 + Math.max(0, clawd.puff) * 2) * clawd.px
                visible: clawd.puff >= 0
                width: clawd.px
                height: clawd.px
                color: "#E9E2D0"
                opacity: Math.max(0, 1 - clawd.puff / 5)
                x: Math.round((clawd.width / 2 + Math.cos(angle) * radius) * clawd.dpr) / clawd.dpr
                y: Math.round((clawd.px * 4 + Math.sin(angle) * radius * 0.7 - Math.round(clawd.jump * clawd.dpr) / clawd.dpr) * clawd.dpr) / clawd.dpr
            }
        }
        Timer {
            interval: 80
            running: clawd.puff >= 0
            repeat: true
            onTriggered: {
                clawd.puff += 1
                if (clawd.puff === 2) {
                    clawd.wornOutfit = clawd.nextOutfit
                    if (clawd.tucking) {
                        clawd.tucking = false
                        clawd.flipped = false
                        clawd.rest = "sleep"
                        clawd.restClock = 0
                    }
                }
                if (clawd.puff > 5) {
                    clawd.puff = -1
                    if (clawd.wornOutfit !== clawd.wantedOutfit) {
                        clawd.nextOutfit = clawd.wantedOutfit
                        clawd.puff = 0
                    }
                }
            }
        }
        Timer {
            interval: 1800000
            running: !clawd.still && root.settings.outfits === "auto"
            repeat: true
            onTriggered: {
                interval = 1200000 + Math.random() * 2400000
                clawd.pickOutfit("whim")
            }
        }
        Timer {
            interval: 30000
            running: !clawd.still && clawd.visible && clawd.mood === "idle" && !clawd.hovering && clawd.rest === "" && clawd.waking < 0
            onTriggered: {
                clawd.fidget = ""
                clawd.goHome()
                clawd.rest = "wind"
                clawd.restClock = 0
            }
        }
        Timer {
            interval: 100
            running: !clawd.still && clawd.visible && (clawd.rest !== "" || clawd.waking >= 0)
            repeat: true
            onTriggered: {
                if (clawd.waking >= 0) {
                    clawd.waking = clawd.waking + 0.1 >= 1.8 ? -1 : clawd.waking + 0.1
                    return
                }
                if (clawd.rest === "wind" && clawd.restClock === 0 && clawd.moving)
                    return
                clawd.restClock += 0.1
                if (clawd.rest === "wind" && clawd.restClock >= 3.8)
                    Math.random() < 0.5 ? clawd.nodOff() : clawd.pickHobby()
            }
        }
        Timer {
            interval: 20000
            running: clawd.rest === "chill" && clawd.visible
            repeat: true
            onTriggered: {
                interval = 15000 + Math.random() * 15000
                clawd.pickHobby()
            }
        }
        Timer {
            interval: 300000
            running: clawd.rest === "chill" && clawd.visible
            repeat: true
            onTriggered: {
                interval = 240000 + Math.random() * 360000
                if (Math.random() < 0.5)
                    clawd.nodOff()
            }
        }
        Timer {
            id: bedtime
            interval: 180000
            running: clawd.rest === "nod" && clawd.visible
            onTriggered: clawd.tuck()
        }
        Image {
            z: -1
            visible: clawd.inBed
            x: clawd.bedX * clawd.px
            y: clawd.px * 2
            width: clawd.px * 36
            height: clawd.px * 10
            source: Qt.resolvedUrl("../images/clawd-bed.svg")
            sourceSize: Qt.size(width, height)
            smooth: false
        }
        Image {
            z: 1
            visible: clawd.inBed && (clawd.puff < 1 || clawd.puff > 2)
            x: (clawd.bedX + 9) * clawd.px
            y: clawd.px * 4
            width: clawd.px * 24
            height: clawd.px * 7
            source: Qt.resolvedUrl("../images/clawd-blanket-" + (clawd.breathing ? "b" : "a") + ".svg")
            sourceSize: Qt.size(width, height)
            smooth: false
        }
        Item {
            z: 1
            width: clawd.width
            height: clawd.height
            visible: clawd.rest === "chill" && clawd.beat >= 0.3
            transform: Scale { origin.x: clawd.width / 2; xScale: clawd.flipped ? -1 : 1 }
            Image {
                visible: clawd.hobby === "read"
                x: clawd.px * 3
                y: clawd.px * 5
                width: clawd.px * 11
                height: clawd.px * 6
                source: Qt.resolvedUrl("../images/clawd-book-" + (clawd.beat % 3 > 2.7 ? "f" : Math.floor(clawd.beat / 3) % 2 ? "b" : "a") + ".svg")
                sourceSize: Qt.size(width, height)
                smooth: false
            }
            Image {
                id: mug
                visible: clawd.hobby === "sip"
                x: Math.round(18 - 5 * clawd.sip) * clawd.px
                y: Math.round(6 - 4 * clawd.sip) * clawd.px
                width: clawd.px * 5
                height: clawd.px * 4
                source: Qt.resolvedUrl("../images/clawd-mug.svg")
                sourceSize: Qt.size(width, height)
                smooth: false
            }
            Repeater {
                model: 2
                Rectangle {
                    required property int index
                    readonly property real age: (clawd.beat * 3 + index * 3) % 6
                    readonly property real gy: Math.round(6 - 4 * clawd.sip) - 1 - Math.floor(age)
                    visible: clawd.hobby === "sip" && gy >= -clawd.roomAbove
                    x: mug.x + (1 + index * 2 + Math.floor(age) % 2) * clawd.px
                    y: gy * clawd.px
                    width: clawd.px
                    height: clawd.px
                    color: "#E9E2D0"
                    opacity: Math.max(0, 1 - age / 6)
                }
            }
            Item {
                visible: clawd.hobby === "fish"
                readonly property int tipX: 18 + clawd.rodLen
                readonly property int tipY: 6 - clawd.rodLen + (clawd.tug ? 1 : 0)
                Repeater {
                    model: clawd.rodLen
                    Rectangle {
                        required property int index
                        x: (19 + index) * clawd.px
                        y: (5 - index + (clawd.tug ? 1 : 0)) * clawd.px
                        width: clawd.px
                        height: clawd.px
                        color: "#8B6B4A"
                    }
                }
                Rectangle {
                    x: parent.tipX * clawd.px
                    y: (parent.tipY + 1) * clawd.px
                    width: clawd.px
                    height: Math.max(0, clawd.bobY - parent.tipY - 1) * clawd.px
                    color: "#B5AE98"
                }
                Rectangle {
                    x: (parent.tipX - 1) * clawd.px
                    y: clawd.bobY * clawd.px
                    width: clawd.px * 3
                    height: clawd.px * 2
                    color: "#E67E80"
                    Rectangle {
                        x: clawd.px
                        width: clawd.px
                        height: clawd.px
                        color: "#E9E2D0"
                    }
                }
                Rectangle {
                    visible: clawd.tug && clawd.bobY + 2 < 12 + clawd.roomBelow
                    x: (parent.tipX - 3) * clawd.px
                    y: (clawd.bobY + 2) * clawd.px
                    width: clawd.px * 7
                    height: clawd.px
                    color: "#56635F"
                }
            }
        }
        Repeater {
            model: 3
            Image {
                required property int index
                readonly property real since: clawd.restClock - clawd.snoreFrom - index * 1.5
                readonly property real age: since % 4.5
                readonly property bool big: age > 1.8
                z: 2
                visible: clawd.snoreFrom >= 0 && since >= 0 && (clawd.puff < 1 || clawd.puff > 2)
                x: Math.round(clawd.snoreAt.x + (clawd.flipped && !clawd.inBed ? -1 : 1) * (age * 2.4 + Math.sin(age * 2.2) * 1.5)) * clawd.px
                y: Math.max(-clawd.roomAbove, Math.round(clawd.snoreAt.y - age * 3.2)) * clawd.px
                width: clawd.px * (big ? 5 : 4)
                height: width
                opacity: Math.max(0, 1 - age / 4.5)
                source: Qt.resolvedUrl("../images/clawd-z-" + (big ? "l" : "s") + ".svg")
                sourceSize: Qt.size(width, height)
                smooth: false
            }
        }
        Image {
            z: 2
            visible: clawd.frame === "clawd-nod-up" || clawd.waking >= 0 && clawd.waking < 0.65
            x: clawd.px * 9
            y: Math.max(-clawd.roomAbove * clawd.px, clawd.waking >= 0 ? -clawd.px * 8 - Math.round(clawd.jump * clawd.dpr) / clawd.dpr : -clawd.px * 5)
            width: clawd.px
            height: clawd.px * 5
            source: Qt.resolvedUrl("../images/clawd-bang.svg")
            sourceSize: Qt.size(width, height)
            smooth: false
        }
        Timer {
            id: shyReturn
            interval: 2500
            onTriggered: if (!clawd.hovering) clawd.flee = -1
        }
    }

    component Pip: Rectangle {
        readonly property real dpr: Screen.devicePixelRatio || 1
        readonly property real size: Math.max(2, Math.round(Kirigami.Units.gridUnit * 0.2 * dpr)) / dpr
        Layout.preferredWidth: size
        Layout.preferredHeight: size
        Layout.alignment: Qt.AlignVCenter
        color: Qt.alpha(Kirigami.Theme.textColor, 0.3)
    }

    component Stripes: Shape {
        id: stripes
        property color ink: root.active
        property color wash: Qt.alpha(root.active, 0.45)
        readonly property real period: Math.max(2, Kirigami.Units.smallSpacing) / Math.SQRT2
        ShapePath {
            strokeWidth: -1
            fillGradient: LinearGradient {
                x2: stripes.period
                y2: stripes.period
                spread: ShapeGradient.RepeatSpread
                GradientStop { position: 0; color: stripes.ink }
                GradientStop { position: 0.5; color: stripes.ink }
                GradientStop { position: 0.5; color: stripes.wash }
                GradientStop { position: 1; color: stripes.wash }
            }
            PathLine { x: stripes.width; y: 0 }
            PathLine { x: stripes.width; y: stripes.height }
            PathLine { x: 0; y: stripes.height }
            PathLine { x: 0; y: 0 }
        }
    }

    component Dot: Rectangle {
        property string kind
        readonly property real size: Kirigami.Units.gridUnit * 0.5
        implicitWidth: size
        implicitHeight: size
        radius: size / 2
        Layout.alignment: Qt.AlignVCenter
        color: kind === "idle" ? "transparent" : root.botColor(kind)
        border.width: kind === "idle" ? 1 : 0
        border.color: root.dim
    }

    component Badge: Rectangle {
        property int value
        implicitWidth: Math.max(implicitHeight, badgeLabel.implicitWidth + Kirigami.Units.smallSpacing * 2)
        implicitHeight: badgeLabel.implicitHeight
        radius: height / 2
        color: root.blocked
        Layout.alignment: Qt.AlignVCenter
        PlasmaComponents.Label {
            id: badgeLabel
            anchors.centerIn: parent
            text: parent.value
            color: Kirigami.Theme.backgroundColor
            font.pointSize: Kirigami.Theme.smallFont.pointSize * 0.9
            font.weight: Font.DemiBold
        }
    }

    component BotChip: Rectangle {
        id: chip
        property var bot
        readonly property bool waiting: bot.state === "blocked"
        readonly property int running: bot.agents.filter(a => a.state === "working").length
        implicitWidth: chipRow.implicitWidth + Kirigami.Units.largeSpacing
        implicitHeight: chipRow.implicitHeight + Kirigami.Units.smallSpacing
        radius: height / 2
        color: Qt.alpha(Kirigami.Theme.textColor, 0.08)
        border.width: waiting ? 1 : 0
        border.color: root.blocked
        Layout.alignment: Qt.AlignVCenter
        RowLayout {
            id: chipRow
            anchors.centerIn: parent
            spacing: Kirigami.Units.smallSpacing
            Dot { kind: chip.bot.state }
            PlasmaComponents.Label {
                text: chip.bot.name
                font.pointSize: Kirigami.Theme.smallFont.pointSize
            }
            PlasmaComponents.Label {
                visible: chip.running > 0
                text: chip.running
                color: root.dim
                font.pointSize: Kirigami.Theme.smallFont.pointSize
            }
            Badge { visible: chip.waiting; value: chip.bot.needs.length }
        }
    }

    component IdleChip: Rectangle {
        implicitWidth: idleRow.implicitWidth + Kirigami.Units.largeSpacing
        implicitHeight: idleRow.implicitHeight + Kirigami.Units.smallSpacing
        radius: height / 2
        color: Qt.alpha(Kirigami.Theme.textColor, 0.08)
        Layout.alignment: Qt.AlignVCenter
        RowLayout {
            id: idleRow
            anchors.centerIn: parent
            spacing: Kirigami.Units.smallSpacing
            Dot { kind: "idle" }
            PlasmaComponents.Label {
                text: root.idleBots.length
                color: root.dim
                font.pointSize: Kirigami.Theme.smallFont.pointSize
            }
        }
        HoverHandler { id: idleHover }
        PlasmaComponents.ToolTip {
            visible: idleHover.hovered
            text: root.idleBots.map(b => b.name).join(", ") + " idle"
        }
    }

    component AgentTotal: RowLayout {
        readonly property int busy: root.botTotals.subagents_working || 0
        spacing: Kirigami.Units.smallSpacing
        opacity: busy > 0 ? 1 : 0.4
        Layout.alignment: Qt.AlignVCenter
        Rectangle {
            Layout.preferredWidth: Kirigami.Units.gridUnit * 0.4
            Layout.preferredHeight: Kirigami.Units.gridUnit * 0.4
            Layout.alignment: Qt.AlignVCenter
            rotation: 45
            color: busy > 0 ? Kirigami.Theme.textColor : "transparent"
            border.width: 1
            border.color: busy > 0 ? Kirigami.Theme.textColor : root.dim
        }
        PlasmaComponents.Label {
            visible: busy > 0
            text: busy
            font.pointSize: Kirigami.Theme.smallFont.pointSize
            font.weight: Font.DemiBold
        }
        HoverHandler { id: totalHover }
        PlasmaComponents.ToolTip {
            visible: totalHover.hovered
            text: busy + " subagents working · " + root.botTotals.agents + " agents, " + root.botTotals.subagents + " live subagents in total"
        }
    }

    component DayChart: RowLayout {
        id: chart
        property var days: []
        property real peak: 1
        property int levels: 12
        property string valueKey: "cost"
        property string labelMode: "letters"
        property real colGap: Kirigami.Units.smallSpacing
        property bool mondayGap: false
        property var format: v => Math.round(v)
        readonly property real dpr: Screen.devicePixelRatio || 1
        readonly property real cell: Math.max(2, Math.round(Kirigami.Units.gridUnit * 0.22 * dpr)) / dpr
        readonly property real gap: Math.max(1, Math.round(dpr)) / dpr
        readonly property real plotHeight: levels * cell + (levels - 1) * gap
        spacing: Kirigami.Units.largeSpacing

        Item {
            Layout.alignment: Qt.AlignTop
            Layout.preferredWidth: axisTop.implicitWidth
            Layout.preferredHeight: chart.plotHeight
            PlasmaComponents.Label {
                id: axisTop
                anchors.top: parent.top
                anchors.right: parent.right
                text: chart.format(chart.peak)
                color: root.dim
                font.pointSize: Kirigami.Theme.smallFont.pointSize * 0.85
            }
            PlasmaComponents.Label {
                anchors.verticalCenter: parent.verticalCenter
                anchors.right: parent.right
                text: chart.format(chart.peak / 2)
                color: root.dim
                font.pointSize: Kirigami.Theme.smallFont.pointSize * 0.85
            }
            PlasmaComponents.Label {
                anchors.bottom: parent.bottom
                anchors.right: parent.right
                text: "0"
                color: root.dim
                font.pointSize: Kirigami.Theme.smallFont.pointSize * 0.85
            }
        }

        Item {
            id: plot
            Layout.fillWidth: true
            Layout.alignment: Qt.AlignTop
            Layout.preferredHeight: plotRow.implicitHeight
            readonly property int count: chart.days.length
            readonly property int bigGaps: chart.mondayGap ? chart.days.filter((d, i) => i > 0 && new Date(d.day + "T12:00:00").getDay() === 1).length : 0
            readonly property real extra: chart.colGap * 2
            readonly property real colW: count > 0 ? Math.max(1, Math.floor((width - (count - 1) * chart.colGap - bigGaps * extra) * chart.dpr / count)) / chart.dpr : 0
            Row {
                id: plotRow
                spacing: chart.colGap
                Repeater {
                    model: chart.days
                    Item {
                        id: col
                        readonly property var date: new Date(modelData.day + "T12:00:00")
                        readonly property real value: modelData[chart.valueKey] || 0
                        readonly property int lit: value > 0 ? Math.max(1, Math.round(value / chart.peak * chart.levels)) : 0
                        readonly property bool isToday: index === chart.days.length - 1
                        readonly property bool monday: date.getDay() === 1
                        readonly property real lead: chart.mondayGap && monday && index > 0 ? plot.extra : 0
                        readonly property bool clashesWithToday: chart.labelMode !== "letters" && !isToday && x + lead + dayLabel.implicitWidth + Kirigami.Units.smallSpacing > plotRow.width - todayText.advanceWidth
                        width: plot.colW + lead
                        implicitHeight: chart.plotHeight + chart.gap + dayLabel.implicitHeight
                        TextMetrics {
                            id: todayText
                            font: dayLabel.font
                            text: chart.days.length ? new Date(chart.days[chart.days.length - 1].day + "T12:00:00").toLocaleString(Qt.locale(), "d MMM") : ""
                        }
                        height: implicitHeight
                        Column {
                            x: col.lead
                            spacing: chart.gap
                            Repeater {
                                model: chart.levels
                                Rectangle {
                                    width: plot.colW
                                    height: chart.cell
                                    color: chart.levels - index <= col.lit
                                        ? (col.isToday ? Kirigami.Theme.highlightColor : Qt.alpha(Kirigami.Theme.textColor, 0.85))
                                        : Qt.alpha(Kirigami.Theme.textColor, 0.12)
                                }
                            }
                        }
                        PlasmaComponents.Label {
                            id: dayLabel
                            x: col.lead + (chart.labelMode === "letters" ? (plot.colW - implicitWidth) / 2 : (col.isToday ? plot.colW - implicitWidth : 0))
                            y: chart.plotHeight + chart.gap
                            visible: chart.labelMode === "letters" || col.isToday || col.monday && !col.clashesWithToday
                            text: chart.labelMode === "letters" ? col.date.toLocaleString(Qt.locale(), "ddd").slice(0, 1) : col.date.toLocaleString(Qt.locale(), "d MMM")
                            color: col.isToday ? Kirigami.Theme.highlightColor : root.dim
                            font.pointSize: Kirigami.Theme.smallFont.pointSize * 0.85
                        }
                    }
                }
            }
        }
    }

    component Costs: ColumnLayout {
        spacing: Kirigami.Units.smallSpacing
        readonly property var daily: root.costs ? root.costs.daily.map(d => ({ day: d.day, cost: root.remoteCosts.reduce((sum, h) => sum + ((h.daily || []).find(r => r.day === d.day) || { cost: 0 }).cost, d.cost) })) : []
        readonly property var models: {
            const merged = {}
            for (const m of (root.costs ? root.costs.models : []).concat(root.remoteCosts.reduce((all, h) => all.concat(h.models || []), [])))
                merged[m.model] = (merged[m.model] || 0) + m.cost
            return Object.keys(merged).map(k => ({ model: k, cost: merged[k] })).sort((a, b) => b.cost - a.cost)
        }
        readonly property real costPeak: Math.max(1, ...daily.map(d => d.cost))

        RowLayout {
            Layout.fillWidth: true
            spacing: Kirigami.Units.smallSpacing
            PlasmaComponents.Label {
                text: "Cost"
                font.weight: Font.DemiBold
            }
            PlasmaComponents.Label {
                Layout.fillWidth: true
                text: "API-price estimate"
                color: root.dim
                font.pointSize: Kirigami.Theme.smallFont.pointSize
                elide: Text.ElideRight
            }
        }

        RowLayout {
            Layout.fillWidth: true
            spacing: Kirigami.Units.gridUnit

            Repeater {
                model: [
                    { label: "Today", value: root.totalCost("today") },
                    { label: "7 days", value: root.totalCost("week") },
                    { label: "30 days", value: root.totalCost("month") }
                ]
                ColumnLayout {
                    spacing: 0
                    PlasmaComponents.Label {
                        text: root.money(modelData.value)
                        font.pointSize: Kirigami.Theme.defaultFont.pointSize * 1.2
                        font.weight: Font.DemiBold
                    }
                    PlasmaComponents.Label {
                        text: modelData.label
                        color: root.dim
                        font.pointSize: Kirigami.Theme.smallFont.pointSize
                    }
                }
            }

        }

        PlasmaComponents.Label {
            Layout.topMargin: Kirigami.Units.largeSpacing
            text: "7 days"
            color: root.dim
            font.pointSize: Kirigami.Theme.smallFont.pointSize
        }
        DayChart {
            Layout.fillWidth: true
            days: daily.slice(-7)
            peak: costPeak
            colGap: Kirigami.Units.smallSpacing * 2
            labelMode: "letters"
            format: root.money
        }

        PlasmaComponents.Label {
            Layout.topMargin: Kirigami.Units.largeSpacing * 2
            text: "30 days"
            color: root.dim
            font.pointSize: Kirigami.Theme.smallFont.pointSize
        }
        DayChart {
            Layout.fillWidth: true
            days: daily
            peak: costPeak
            colGap: Kirigami.Units.smallSpacing / 2
            mondayGap: true
            labelMode: "dates"
            format: root.money
        }

        PlasmaComponents.Label {
            visible: root.remoteCosts.length > 0
            Layout.fillWidth: true
            Layout.topMargin: Kirigami.Units.largeSpacing
            text: "7 days · " + root.hostCosts("week").map(h => h.host + " " + root.money(h.cost) + (h.stale ? " (stale)" : "")).join(" · ")
            color: root.dim
            opacity: root.remoteStale ? 0.6 : 1
            font.pointSize: Kirigami.Theme.smallFont.pointSize
            elide: Text.ElideRight
        }

        Flow {
            Layout.fillWidth: true
            spacing: Kirigami.Units.largeSpacing
            Repeater {
                model: models.filter(m => m.cost >= 0.5).slice(0, 4)
                PlasmaComponents.Label {
                    text: root.modelName(modelData.model) + " " + root.money(modelData.cost)
                    color: root.dim
                    font.pointSize: Kirigami.Theme.smallFont.pointSize
                }
            }
        }
    }

    component Tokens: ColumnLayout {
        spacing: Kirigami.Units.smallSpacing
        readonly property var kinds: {
            const sum = { "in": 0, "out": 0, "cache_w": 0, "cache_r": 0 }
            for (const k in sum)
                sum[k] = root.remoteCosts.reduce((acc, h) => acc + (h.tokens ? h.tokens.kinds[k] : 0), root.costs && root.costs.tokens ? root.costs.tokens.kinds[k] : 0)
            return sum
        }
        readonly property int hit: {
            const all = kinds.cache_r + kinds.cache_w + kinds["in"]
            return all > 0 ? Math.round(100 * kinds.cache_r / all) : 0
        }

        RowLayout {
            Layout.fillWidth: true
            spacing: Kirigami.Units.smallSpacing
            PlasmaComponents.Label {
                text: "Tokens"
                font.weight: Font.DemiBold
            }
            PlasmaComponents.Label {
                Layout.fillWidth: true
                text: "fresh"
                color: root.dim
                font.pointSize: Kirigami.Theme.smallFont.pointSize
                elide: Text.ElideRight
            }
        }

        RowLayout {
            Layout.fillWidth: true
            spacing: Kirigami.Units.gridUnit

            Repeater {
                model: [
                    { label: "Today", value: root.totalTokens("today") },
                    { label: "7 days", value: root.totalTokens("week") },
                    { label: "30 days", value: root.totalTokens("month") }
                ]
                ColumnLayout {
                    spacing: 0
                    PlasmaComponents.Label {
                        text: root.tokens(modelData.value)
                        font.pointSize: Kirigami.Theme.defaultFont.pointSize * 1.2
                        font.weight: Font.DemiBold
                    }
                    PlasmaComponents.Label {
                        text: modelData.label
                        color: root.dim
                        font.pointSize: Kirigami.Theme.smallFont.pointSize
                    }
                }
            }

            Item { Layout.fillWidth: true }
        }

        PlasmaComponents.Label {
            Layout.fillWidth: true
            text: "30d: out " + root.tokens(kinds.out) + " · in " + root.tokens(kinds["in"]) + " · cache w " + root.tokens(kinds.cache_w)
            color: root.dim
            opacity: root.remoteStale ? 0.6 : 1
            font.pointSize: Kirigami.Theme.smallFont.pointSize
            elide: Text.ElideRight
        }

        PlasmaComponents.Label {
            Layout.fillWidth: true
            text: "+ " + root.tokens(kinds.cache_r) + " cache reads (" + hit + "% hit)"
            color: root.dim
            opacity: root.remoteStale ? 0.6 : 1
            font.pointSize: Kirigami.Theme.smallFont.pointSize
            elide: Text.ElideRight
        }
    }

    component Bar: Rectangle {
        property real pct
        property color fill
        implicitHeight: Kirigami.Units.smallSpacing * 1.5
        radius: height / 2
        color: Qt.alpha(Kirigami.Theme.textColor, 0.15)
        Rectangle {
            width: pct > 0 ? Math.max(parent.height, parent.width * Math.min(100, pct) / 100) : 0
            height: parent.height
            radius: parent.radius
            color: fill
            Behavior on width { NumberAnimation { duration: Kirigami.Units.longDuration } }
        }
    }

    component Meter: RowLayout {
        property string label
        property var win
        readonly property real pct: win ? win.pct : 0
        spacing: Kirigami.Units.smallSpacing
        opacity: root.bar && root.bar.stale ? 0.5 : 1
        PlasmaComponents.Label {
            text: label
            color: root.dim
        }
        Bar {
            Layout.preferredWidth: Kirigami.Units.gridUnit * 1.8
            pct: parent.pct
            fill: root.pctColor(parent.pct)
        }
        PlasmaComponents.Label {
            text: win ? Math.round(pct) + "%" : "--"
            color: win ? root.pctColor(pct) : root.dim
            font.bold: true
        }
        PlasmaComponents.Label {
            visible: !!(win && win.resets_at)
            text: win ? root.timeLeft(win.resets_at) : ""
            color: root.dim
        }
    }

    component LimitChart: Item {
        id: chart
        property string key
        property var win
        readonly property real dpr: Screen.devicePixelRatio || 1
        readonly property real hair: Math.max(1, Math.round(dpr)) / dpr
        readonly property real start: win && win.start !== undefined ? win.start : 0
        readonly property real end: win && win.resets_at ? win.resets_at : 1
        readonly property real nowT: Math.min(end, Math.max(start, root.now))
        readonly property real pct: win && win.pct !== undefined ? Math.min(100, win.pct) : 0
        readonly property color accent: root.pctColor(pct)
        readonly property bool limited: !!win && win.pct >= 100
        readonly property bool hits: !!win && !limited && win.hits_in !== undefined && win.hits_in !== null && root.etaReady(key, win)
        readonly property bool rising: !!win && !limited && win.rate > 0
        readonly property real hitT: limited ? Math.min(end, win.limited_at || nowT) : hits ? Math.min(end, nowT + win.hits_in) : end
        readonly property real endPct: hits ? 100 : win && win.projected !== undefined ? win.projected : 0
        readonly property color proj: hits ? root.etaColor(key, win.hits_in) : root.dim
        readonly property color hatch: limited || hits && root.etaCritical(key, win.hits_in) ? root.critical : root.warning
        readonly property real padL: Kirigami.Units.gridUnit * 1.4
        readonly property real padR: Kirigami.Units.smallSpacing
        readonly property real padT: Kirigami.Units.smallSpacing
        readonly property real padB: Kirigami.Units.gridUnit * 1.1
        readonly property real plotW: width - padL - padR
        readonly property real plotH: height - padT - padB
        readonly property real axisSize: Kirigami.Theme.smallFont.pointSize * 0.85
        readonly property var ticks: {
            if (!win || !win.resets_at || win.start === undefined)
                return []
            const step = key === "seven_day" ? 86400 : 3600
            const out = []
            for (let t = win.start; t <= win.resets_at + 60 && out.length < 9; t += step)
                out.push(t)
            return out
        }
        readonly property real gap: key === "seven_day" ? 3600 : 600
        readonly property var traced: {
            const series = [[start, 0]].concat((win && win.samples ? win.samples : []).filter(s => s[0] <= nowT)).concat([[nowT, pct]])
            const kept = [series[0]]
            for (let i = 1; i < series.length; i++) {
                const a = kept[kept.length - 1], b = series[i], c = series[i + 1]
                if (c && b[1] === a[1] && b[0] - a[0] > gap && c[1] !== b[1])
                    continue
                kept.push(b)
            }
            const solid = [], gaps = []
            let run = [kept[0]]
            for (let i = 1; i < kept.length; i++) {
                const a = kept[i - 1], b = kept[i]
                if (b[0] - a[0] > gap && b[1] !== a[1]) {
                    if (run.length > 1)
                        solid.push(run.map(s => Qt.point(px(s[0]), py(s[1]))))
                    gaps.push([Qt.point(px(a[0]), py(a[1])), Qt.point(px(b[0]), py(b[1]))])
                    run = [b]
                } else {
                    run.push(b)
                }
            }
            if (run.length > 1)
                solid.push(run.map(s => Qt.point(px(s[0]), py(s[1]))))
            return { points: kept.map(s => Qt.point(px(s[0]), py(s[1]))), solid: solid, gaps: gaps }
        }

        function px(t) {
            return padL + (t - start) / Math.max(1, end - start) * plotW
        }
        function py(p) {
            return padT + plotH - Math.max(0, Math.min(100, p)) / 100 * plotH
        }

        Repeater {
            model: [25, 50, 75]
            Rectangle {
                x: chart.padL
                y: chart.py(modelData)
                width: chart.plotW
                height: chart.hair
                color: Qt.alpha(Kirigami.Theme.textColor, 0.08)
            }
        }

        Repeater {
            model: chart.key === "seven_day" ? chart.ticks.slice(1, -1) : []
            Rectangle {
                x: chart.px(modelData)
                y: chart.padT
                width: chart.hair
                height: chart.plotH
                color: Qt.alpha(Kirigami.Theme.textColor, 0.06)
            }
        }

        Repeater {
            model: [50, 100]
            PlasmaComponents.Label {
                x: chart.padL - Kirigami.Units.smallSpacing - width
                y: chart.py(modelData) - height / 2
                text: modelData
                color: root.dim
                font.pointSize: chart.axisSize
            }
        }

        Repeater {
            model: chart.ticks
            PlasmaComponents.Label {
                readonly property real at: chart.px(modelData)
                x: index === 0 ? at : index === chart.ticks.length - 1 ? at - width : at - width / 2
                y: chart.padT + chart.plotH + Kirigami.Units.smallSpacing / 2
                text: new Date(modelData * 1000).toLocaleString(Qt.locale(), chart.key === "seven_day" ? "ddd" : "HH:mm")
                color: root.dim
                font.pointSize: chart.axisSize
            }
        }

        Stripes {
            visible: chart.limited || chart.hits
            x: chart.px(chart.hitT)
            y: chart.padT
            width: Math.max(0, chart.px(chart.end) - x)
            height: chart.plotH
            ink: Qt.alpha(chart.hatch, 0.3)
            wash: Qt.alpha(chart.hatch, 0.06)
        }

        Shape {
            anchors.fill: parent
            preferredRendererType: Shape.CurveRenderer
            ShapePath {
                strokeColor: Qt.alpha(Kirigami.Theme.textColor, 0.22)
                strokeWidth: chart.hair
                strokeStyle: ShapePath.DashLine
                dashPattern: [2, 2]
                fillColor: "transparent"
                startX: chart.padL
                startY: chart.py(100)
                PathLine { x: chart.padL + chart.plotW; y: chart.py(100) }
            }
            ShapePath {
                strokeWidth: -1
                fillColor: Qt.alpha(chart.accent, 0.2)
                PathPolyline { path: chart.traced.points.concat([Qt.point(chart.px(chart.nowT), chart.py(0))]) }
            }
            ShapePath {
                strokeColor: chart.accent
                strokeWidth: 1.6
                joinStyle: ShapePath.RoundJoin
                fillColor: "transparent"
                PathMultiline { paths: chart.traced.solid }
            }
            ShapePath {
                strokeColor: Qt.alpha(Kirigami.Theme.textColor, 0.35)
                strokeWidth: 1.2
                strokeStyle: ShapePath.DashLine
                dashPattern: [2, 3]
                fillColor: "transparent"
                PathMultiline { paths: chart.traced.gaps }
            }
            ShapePath {
                strokeColor: chart.rising ? chart.proj : "transparent"
                strokeWidth: 1.5
                strokeStyle: ShapePath.DashLine
                dashPattern: [2, 2]
                fillColor: "transparent"
                startX: chart.px(chart.nowT)
                startY: chart.py(chart.pct)
                PathLine { x: chart.px(chart.hitT); y: chart.py(chart.endPct) }
            }
        }

        Rectangle {
            x: chart.px(chart.nowT)
            y: chart.padT
            width: chart.hair
            height: chart.plotH
            color: Qt.alpha(Kirigami.Theme.textColor, 0.35)
        }
        Rectangle {
            readonly property real size: Kirigami.Units.smallSpacing * 1.5
            x: chart.px(chart.nowT) - size / 2
            y: chart.py(chart.pct) - size / 2
            width: size
            height: size
            radius: size / 2
            color: chart.accent
        }

        Rectangle {
            readonly property real size: Kirigami.Units.smallSpacing * (chart.hits ? 1.5 : 1.25)
            visible: chart.rising
            x: chart.px(chart.hitT) - size / 2
            y: chart.py(chart.endPct) - size / 2
            width: size
            height: size
            radius: size / 2
            color: chart.hits ? chart.proj : "transparent"
            border.width: chart.hits ? 0 : 1.2
            border.color: chart.proj
        }
        PlasmaComponents.Label {
            readonly property real at: chart.px(chart.hitT)
            readonly property bool flip: at > chart.width - Kirigami.Units.gridUnit * 4
            visible: chart.hits
            x: flip ? at - width - Kirigami.Units.smallSpacing : at + Kirigami.Units.smallSpacing
            y: chart.py(100) + Kirigami.Units.smallSpacing / 2
            text: chart.hits ? root.moment(chart.key, chart.hitT) : ""
            color: chart.proj
            font.pointSize: chart.axisSize
            font.weight: Font.DemiBold
        }

        Rectangle {
            x: chart.px(chart.end) - width / 2
            y: chart.padT
            width: chart.hair * 1.5
            height: chart.plotH
            color: root.ok
        }
        PlasmaComponents.Label {
            x: chart.px(chart.end) - width - Kirigami.Units.smallSpacing
            y: chart.padT + chart.plotH - height
            text: "reset"
            color: root.ok
            font.pointSize: chart.axisSize
        }
    }

    component LimitRow: ColumnLayout {
        id: lim
        property string key
        property string title
        property string sub
        property bool separated: false
        property string burnTitle
        property string windowTitle: "This window"
        property var win
        property var window: null
        property var spend: []
        readonly property bool paced: !!win && win.rate !== undefined
        readonly property real pct: win ? win.pct : 0
        readonly property color accent: win ? root.pctColor(pct) : root.dim
        readonly property bool limited: !!win && pct >= 100
        readonly property bool hits: paced && !limited && win.hits_in !== null && root.etaReady(key, win)
        readonly property color eta: limited ? root.critical : hits ? root.etaColor(key, win.hits_in) : root.dim
        readonly property string unit: key === "seven_day" ? "%/day" : "%/h"
        readonly property string rateText: !paced ? "" : win.rate >= 1 ? "+" + Math.round(win.rate) + unit : "idle"
        readonly property string paceText: {
            if (!paced)
                return ""
            const dim = String(root.dim)
            if (limited)
                return "<font color='" + root.critical + "'><b>Limited</b></font><font color='" + dim + "'> · back at " + root.moment(key, win.resets_at) + " (in " + root.span(key, win.resets_at - root.now) + ")</font>"
            if (!root.etaReady(key, win))
                return "<font color='" + dim + "'>" + rateText + "</font>"
            if (hits)
                return "<font color='" + dim + "'>" + rateText + " · </font><font color='" + eta + "'><b>100% " + (key === "seven_day" ? "" : "at ") + root.moment(key, root.now + win.hits_in) + " (in " + root.span(key, win.hits_in) + ")</b></font>"
            return "<font color='" + dim + "'>" + rateText + " · on pace for " + Math.round(win.projected) + "% at reset " + root.moment(key, win.resets_at) + "</font>"
        }
        readonly property var burners: {
            const total = (spend || []).reduce((sum, p) => sum + p.cost, 0)
            if (!paced || total <= 0 || !(win.burned > 0))
                return []
            return spend.map(p => ({ name: p.name, host: p.host || "", stale: !!p.stale, value: p.cost / total * win.burned })).filter(p => p.value >= 0.5).sort((a, b) => b.value - a.value).slice(0, 3)
        }
        readonly property real peak: Math.max(0.01, ...burners.map(b => b.value))
        readonly property var windowRows: {
            if (!window || !win || !(pct > 0))
                return []
            const list = window.projects || []
            const total = list.reduce((sum, p) => sum + p.cost, 0)
            const scaled = total > 0 ? list.map(p => ({ name: p.name, host: p.host || "", stale: !!p.stale, value: p.cost / total * pct })) : []
            const big = scaled.filter(p => p.value >= 0.5)
            const shown = big.slice(0, 6)
            const rest = big.slice(6).concat(scaled.filter(p => p.value < 0.5))
            const restValue = rest.reduce((sum, p) => sum + p.value, 0)
            if (rest.length > 0 && restValue >= 0.5)
                shown.push({ name: rest.length + " more", host: "", stale: false, value: restValue })
            const other = pct - scaled.reduce((sum, p) => sum + p.value, 0)
            if (other >= 0.5)
                shown.push({ name: "unattributed", host: "", stale: false, value: other })
            return shown
        }
        readonly property real windowPeak: Math.max(0.01, ...windowRows.map(r => r.value))
        readonly property var windowModels: {
            if (!window || !win || !(pct > 0))
                return []
            const list = window.models || []
            const total = list.reduce((sum, m) => sum + m.cost, 0)
            if (total <= 0)
                return []
            const grouped = {}
            list.forEach(m => {
                const family = root.modelName(m.model)
                grouped[family] = (grouped[family] || 0) + m.cost / total * pct
            })
            return Object.keys(grouped).map(n => ({ name: n, value: grouped[n] })).filter(m => m.value >= 0.1).sort((x, y) => y.value - x.value)
        }
        Layout.fillWidth: true
        spacing: 0
        opacity: root.bar && root.bar.stale ? 0.5 : 1

        Rectangle {
            visible: lim.separated
            Layout.fillWidth: true
            Layout.preferredHeight: 1
            Layout.topMargin: Kirigami.Units.largeSpacing * 2
            Layout.bottomMargin: Kirigami.Units.largeSpacing * 2
            color: root.hairline
        }

        RowLayout {
            Layout.fillWidth: true
            Layout.leftMargin: Kirigami.Units.smallSpacing / 2
            Layout.rightMargin: Kirigami.Units.smallSpacing / 2
            spacing: Kirigami.Units.smallSpacing
            PlasmaComponents.Label {
                text: lim.title
                font.weight: Font.DemiBold
            }
            PlasmaComponents.Label {
                Layout.fillWidth: true
                text: lim.sub + (lim.win && lim.win.resets_at ? " · resets " + root.moment(lim.key, lim.win.resets_at) : "")
                color: root.dim
                font.pointSize: Kirigami.Theme.smallFont.pointSize
                elide: Text.ElideRight
            }
            PlasmaComponents.Label {
                text: lim.win ? Math.round(lim.pct) + "%" : "--"
                color: lim.accent
                font.weight: Font.Bold
                font.pointSize: Kirigami.Theme.defaultFont.pointSize * 1.15
            }
        }

        ColumnLayout {
            id: body
            Layout.fillWidth: true
            Layout.topMargin: Kirigami.Units.largeSpacing
            Layout.leftMargin: Kirigami.Units.smallSpacing / 2
            Layout.rightMargin: Kirigami.Units.smallSpacing / 2
            spacing: Kirigami.Units.smallSpacing

            LimitChart {
                visible: lim.paced && !!lim.win.resets_at
                Layout.fillWidth: true
                Layout.preferredHeight: Kirigami.Units.gridUnit * 4
                key: lim.key
                win: lim.win
            }
            PlasmaComponents.Label {
                Layout.fillWidth: true
                visible: text !== ""
                text: lim.paced ? lim.paceText : lim.win ? "No pace data yet" : "No limit data"
                textFormat: Text.StyledText
                color: root.dim
                font.pointSize: Kirigami.Theme.smallFont.pointSize
                wrapMode: Text.WordWrap
            }
            RowLayout {
                visible: lim.windowRows.length > 0
                Layout.fillWidth: true
                Layout.topMargin: Kirigami.Units.smallSpacing / 2
                spacing: Kirigami.Units.smallSpacing
                Heading {
                    Layout.fillWidth: true
                    text: lim.windowTitle
                    elide: Text.ElideRight
                }
                PlasmaComponents.Label {
                    text: "% of limit · est."
                    color: root.dim
                    font.pointSize: Kirigami.Theme.smallFont.pointSize
                }
            }
            BurnGrid {
                visible: lim.windowRows.length > 0
                rows: lim.windowRows
                peak: lim.windowPeak
                tone: lim.accent
                plain: true
            }
            RowLayout {
                visible: lim.windowModels.length > 0
                Layout.fillWidth: true
                spacing: 2
                Repeater {
                    model: lim.windowModels
                    delegate: Rectangle {
                        required property var modelData
                        required property int index
                        Layout.fillWidth: true
                        Layout.preferredWidth: Math.max(1, modelData.value)
                        implicitHeight: Kirigami.Units.smallSpacing * 1.25
                        radius: height / 2
                        color: root.modelColor(modelData.name)
                    }
                }
            }
            Flow {
                visible: lim.windowModels.length > 0
                Layout.fillWidth: true
                spacing: Kirigami.Units.smallSpacing * 2
                Repeater {
                    model: lim.windowModels
                    delegate: PlasmaComponents.Label {
                        required property var modelData
                        required property int index
                        text: "<font color='" + root.modelColor(modelData.name) + "'>●</font> " + modelData.name + " · " + (modelData.value < 1 ? modelData.value.toFixed(1) : Math.round(modelData.value)) + "%"
                        textFormat: Text.StyledText
                        color: root.dim
                        font.pointSize: Kirigami.Theme.smallFont.pointSize
                    }
                }
            }
            RowLayout {
                visible: lim.burners.length > 0
                Layout.fillWidth: true
                Layout.topMargin: Kirigami.Units.smallSpacing / 2
                spacing: Kirigami.Units.smallSpacing
                Heading {
                    Layout.fillWidth: true
                    text: lim.burnTitle
                    elide: Text.ElideRight
                }
                PlasmaComponents.Label {
                    text: "% of limit · est."
                    color: root.dim
                    font.pointSize: Kirigami.Theme.smallFont.pointSize
                }
            }
            BurnGrid {
                visible: lim.burners.length > 0
                rows: lim.burners
                peak: lim.peak
                tone: lim.accent
            }
        }
    }

    component BurnGrid: GridLayout {
        id: grid
        property var rows: []
        property real peak: 0.01
        property color tone: root.dim
        property bool plain: false
        Layout.fillWidth: true
        columns: 3
        columnSpacing: Kirigami.Units.smallSpacing * 2
        rowSpacing: Kirigami.Units.smallSpacing / 2
        Repeater {
            model: grid.rows
            delegate: RowLayout {
                required property var modelData
                required property int index
                Layout.row: index
                Layout.column: 0
                Layout.maximumWidth: Kirigami.Units.gridUnit * 9
                spacing: Kirigami.Units.smallSpacing
                opacity: modelData.stale ? 0.6 : 1
                PlasmaComponents.Label {
                    Layout.maximumWidth: Kirigami.Units.gridUnit * 6
                    text: modelData.name
                    font.pointSize: Kirigami.Theme.smallFont.pointSize
                    elide: Text.ElideRight
                }
                HostTag {
                    visible: !!modelData.host
                    host: modelData.host || ""
                }
            }
        }
        Repeater {
            model: grid.rows
            delegate: Item {
                required property var modelData
                required property int index
                Layout.row: index
                Layout.column: 1
                Layout.fillWidth: true
                implicitHeight: Kirigami.Units.smallSpacing * 1.25
                Rectangle {
                    width: Math.max(height, parent.width * modelData.value / grid.peak)
                    height: parent.height
                    radius: height / 2
                    color: grid.tone
                }
            }
        }
        Repeater {
            model: grid.rows
            delegate: PlasmaComponents.Label {
                required property var modelData
                required property int index
                Layout.row: index
                Layout.column: 2
                Layout.alignment: Qt.AlignRight
                text: (grid.plain ? "" : "+") + Math.round(modelData.value)
                color: root.dim
                font.pointSize: Kirigami.Theme.smallFont.pointSize
            }
        }
    }

    component Tally: PlasmaComponents.Label {
        property int value
        property color tone: Kirigami.Theme.textColor
        Layout.alignment: Qt.AlignRight
        text: value
        color: value ? tone : Qt.alpha(root.dim, 0.5)
        font.weight: value && tone !== root.dim ? Font.DemiBold : Font.Normal
    }

    component Heading: PlasmaComponents.Label {
        color: root.dim
        font.pointSize: Kirigami.Theme.smallFont.pointSize
        font.capitalization: Font.AllUppercase
        font.letterSpacing: 1
    }

    component AgentRow: Rectangle {
        id: agentRow
        property var agent
        implicitHeight: agentLine.implicitHeight + Kirigami.Units.smallSpacing
        radius: Kirigami.Units.cornerRadius
        color: agentHover.hovered && agent.worktree && !agent.host ? Qt.alpha(Kirigami.Theme.textColor, 0.08) : "transparent"
        RowLayout {
            id: agentLine
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            anchors.margins: Kirigami.Units.smallSpacing
            spacing: Kirigami.Units.smallSpacing
            Dot { kind: agentRow.agent.state === "working" ? "working" : agentRow.agent.state === "done" ? "idle" : "blocked" }
            PlasmaComponents.Label {
                Layout.fillWidth: true
                text: agentRow.agent.title
                elide: Text.ElideRight
            }
            PlasmaComponents.Label {
                text: agentRow.agent.repo + (agentRow.agent.branch ? " · " + agentRow.agent.branch : "")
                color: root.dim
                font.pointSize: Kirigami.Theme.smallFont.pointSize
                elide: Text.ElideMiddle
                Layout.maximumWidth: Kirigami.Units.gridUnit * 9
            }
            PlasmaComponents.Label {
                visible: agentRow.agent.subagents > 0
                text: "+" + agentRow.agent.subagents
                color: root.active
                font.pointSize: Kirigami.Theme.smallFont.pointSize
            }
        }
        HoverHandler { id: agentHover; cursorShape: agentRow.agent.worktree && !agentRow.agent.host ? Qt.PointingHandCursor : Qt.ArrowCursor }
        TapHandler { enabled: !!agentRow.agent.worktree && !agentRow.agent.host; onTapped: root.focusAgent("worktree:" + agentRow.agent.worktree) }
    }

    component BotCard: Rectangle {
        id: card
        property var bot
        implicitHeight: cardColumn.implicitHeight + Kirigami.Units.largeSpacing
        radius: Kirigami.Units.cornerRadius
        color: Qt.alpha(Kirigami.Theme.textColor, 0.05)
        border.width: bot.state === "blocked" ? 1 : 0
        border.color: root.blocked
        ColumnLayout {
            id: cardColumn
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            anchors.margins: Kirigami.Units.smallSpacing
            spacing: Kirigami.Units.smallSpacing
            RowLayout {
                Layout.fillWidth: true
                spacing: Kirigami.Units.smallSpacing
                Dot { kind: card.bot.state }
                PlasmaComponents.Label {
                    text: card.bot.name
                    font.weight: Font.DemiBold
                }
                HostTag { visible: !!card.bot.host; host: card.bot.host }
                Item { Layout.fillWidth: true }
                PlasmaComponents.Label {
                    text: card.bot.agents.length + (card.bot.agents.length === 1 ? " agent" : " agents") + (card.bot.subagents ? " · +" + card.bot.subagents : "")
                    color: root.dim
                    font.pointSize: Kirigami.Theme.smallFont.pointSize
                }
            }
            Repeater {
                model: card.bot.progress.slice(0, 3)
                PlasmaComponents.Label {
                    Layout.fillWidth: true
                    Layout.leftMargin: Kirigami.Units.gridUnit * 0.8
                    text: "▸ " + modelData
                    color: root.dim
                    font.pointSize: Kirigami.Theme.smallFont.pointSize
                    elide: Text.ElideRight
                }
            }
            Repeater {
                model: card.bot.agents
                AgentRow { Layout.fillWidth: true; agent: modelData }
            }
        }
    }

    component TotalCell: RowLayout {
        property var cell
        readonly property bool numeric: cell.col > 0
        Layout.fillWidth: !numeric
        Layout.alignment: numeric ? Qt.AlignRight | Qt.AlignVCenter : Qt.AlignLeft | Qt.AlignVCenter
        spacing: Kirigami.Units.smallSpacing
        Dot { visible: !numeric && !!cell.kind; kind: cell.kind || "idle" }
        PlasmaComponents.Label {
            Layout.fillWidth: !numeric
            horizontalAlignment: numeric ? Text.AlignRight : Text.AlignLeft
            text: cell.text
            elide: Text.ElideRight
            color: cell.head || cell.dim ? root.dim : Kirigami.Theme.textColor
            font.pointSize: cell.head ? Kirigami.Theme.smallFont.pointSize : Kirigami.Theme.defaultFont.pointSize
            font.weight: cell.strong ? Font.DemiBold : Font.Normal
            font.features: ({ "tnum": 1 })
        }
    }

    component BotsPanel: ColumnLayout {
        id: panel
        spacing: Kirigami.Units.largeSpacing
        readonly property var totalCells: {
            const row = (kind, name, agents, subs, extra) => [
                Object.assign({ col: 0, kind: kind, text: name }, extra),
                Object.assign({ col: 1, text: String(agents) }, extra),
                Object.assign({ col: 2, text: String(subs) }, extra)
            ]
            const other = root.botData ? root.botData.other : []
            return [].concat(
                row("", "", "agents", "subagents", { head: true }),
                root.botList.reduce((all, b) => all.concat(row(b.state, b.name, b.agents.length, b.subagents, {})), []),
                row("", "Other (no bot)", other.length, other.reduce((n, a) => n + a.subagents, 0), { dim: true }),
                row("", "Total", root.botTotals.agents, root.botTotals.subagents, { strong: true })
            )
        }

        Heading { text: "Needs you" }
        PlasmaComponents.Label {
            visible: root.botTotals.needs === 0
            text: root.botData ? "Nothing waits on you" : "Orca not reachable"
            color: root.dim
        }
        Repeater {
            model: root.botList.reduce((all, b) => all.concat(b.needs.map(n => Object.assign({ bot: b.name }, n))), [])
            Rectangle {
                id: needRow
                Layout.fillWidth: true
                implicitHeight: needColumn.implicitHeight + Kirigami.Units.largeSpacing
                radius: Kirigami.Units.cornerRadius
                color: Qt.alpha(root.blocked, 0.12)
                ColumnLayout {
                    id: needColumn
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    anchors.margins: Kirigami.Units.smallSpacing
                    spacing: 0
                    RowLayout {
                        spacing: Kirigami.Units.smallSpacing
                        Dot { kind: "blocked" }
                        PlasmaComponents.Label { text: modelData.bot; font.weight: Font.DemiBold }
                        PlasmaComponents.Label {
                            Layout.fillWidth: true
                            text: "#" + modelData.number + " " + modelData.title
                            elide: Text.ElideRight
                        }
                    }
                    PlasmaComponents.Label {
                        visible: !!modelData.question
                        Layout.fillWidth: true
                        text: modelData.question
                        color: root.dim
                        font.pointSize: Kirigami.Theme.smallFont.pointSize
                        wrapMode: Text.Wrap
                        maximumLineCount: 2
                        elide: Text.ElideRight
                    }
                }
            }
        }

        Heading { text: "Totals · " + root.botTotals.working + " working, " + root.botTotals.blocked + " blocked, " + root.botTotals.idle + " idle" }
        GridLayout {
            Layout.fillWidth: true
            columns: 3
            columnSpacing: Kirigami.Units.gridUnit
            rowSpacing: Kirigami.Units.smallSpacing
            Repeater {
                model: panel.totalCells
                TotalCell { cell: modelData }
            }
        }
        PlasmaComponents.Label {
            visible: root.subagentGuess > root.botTotals.subagents
            Layout.fillWidth: true
            text: "Estimate from transcripts: " + root.subagentGuess + " running subagents, not counted"
            color: root.dim
            font.pointSize: Kirigami.Theme.smallFont.pointSize
            wrapMode: Text.Wrap
        }

        Heading { visible: root.botList.length > 0; text: "Bots" }
        Repeater {
            model: root.botList
            BotCard { Layout.fillWidth: true; bot: modelData }
        }

        Heading { visible: !!root.botData && root.botData.other.length > 0; text: "Other agents" }
        Repeater {
            model: root.botData ? root.botData.other : []
            AgentRow { Layout.fillWidth: true; agent: modelData }
        }
    }

    component HostTag: Rectangle {
        property string host
        property bool stale: false
        implicitWidth: hostLabel.implicitWidth + Kirigami.Units.smallSpacing * 2
        implicitHeight: hostLabel.implicitHeight
        radius: Kirigami.Units.cornerRadius
        color: "transparent"
        border.width: 1
        border.color: root.hairline
        PlasmaComponents.Label {
            id: hostLabel
            anchors.centerIn: parent
            text: parent.stale ? parent.host + " · stale" : parent.host
            color: root.dim
            font.pointSize: Kirigami.Theme.smallFont.pointSize * 0.85
        }
    }

    component Hosts: ColumnLayout {
        id: hosts
        spacing: Kirigami.Units.smallSpacing

        RowLayout {
            Layout.fillWidth: true
            spacing: Kirigami.Units.smallSpacing
            PlasmaComponents.Label {
                text: "Hosts"
                font.weight: Font.DemiBold
            }
            PlasmaComponents.Label {
                Layout.fillWidth: true
                text: "Orca · last 7 days"
                color: root.dim
                font.pointSize: Kirigami.Theme.smallFont.pointSize
                elide: Text.ElideRight
            }
        }

        Repeater {
            model: root.remoteHosts
            delegate: ColumnLayout {
                id: hostBlock
                required property var modelData
                readonly property var leaders: (modelData.projects || []).slice(0, 4)
                readonly property real peak: Math.max(1, ...leaders.map(p => p.calls))
                Layout.fillWidth: true
                spacing: Kirigami.Units.smallSpacing / 2
                opacity: modelData.stale ? 0.6 : 1

                RowLayout {
                    Layout.fillWidth: true
                    spacing: Kirigami.Units.smallSpacing * 1.5
                    HostTag {
                        host: hostBlock.modelData.host
                        stale: !!hostBlock.modelData.stale
                    }
                    PlasmaComponents.Label {
                        Layout.fillWidth: true
                        text: hostBlock.modelData.sessions + " sessions · " + root.count(hostBlock.modelData.calls) + " calls"
                        font.pointSize: Kirigami.Theme.smallFont.pointSize
                        elide: Text.ElideRight
                    }
                    PlasmaComponents.Label {
                        text: root.count(hostBlock.modelData.errors) + " errors · " + hostBlock.modelData.err_pct + "%"
                        color: hostBlock.modelData.err_pct >= 10 ? root.critical : root.dim
                        font.pointSize: Kirigami.Theme.smallFont.pointSize
                    }
                }

                GridLayout {
                    visible: hostBlock.leaders.length > 0
                    Layout.fillWidth: true
                    columns: 3
                    columnSpacing: Kirigami.Units.smallSpacing * 2
                    rowSpacing: Kirigami.Units.smallSpacing / 2
                    Repeater {
                        model: hostBlock.leaders
                        delegate: PlasmaComponents.Label {
                            required property var modelData
                            required property int index
                            Layout.row: index
                            Layout.column: 0
                            Layout.maximumWidth: Kirigami.Units.gridUnit * 7
                            text: modelData.name
                            font.pointSize: Kirigami.Theme.smallFont.pointSize
                            elide: Text.ElideRight
                        }
                    }
                    Repeater {
                        model: hostBlock.leaders
                        delegate: Item {
                            required property var modelData
                            required property int index
                            Layout.row: index
                            Layout.column: 1
                            Layout.fillWidth: true
                            implicitHeight: Kirigami.Units.smallSpacing * 1.25
                            Rectangle {
                                width: Math.max(height, parent.width * modelData.calls / hostBlock.peak)
                                height: parent.height
                                radius: height / 2
                                color: Qt.alpha(Kirigami.Theme.textColor, 0.8)
                            }
                        }
                    }
                    Repeater {
                        model: hostBlock.leaders
                        delegate: PlasmaComponents.Label {
                            required property var modelData
                            required property int index
                            Layout.row: index
                            Layout.column: 2
                            Layout.alignment: Qt.AlignRight
                            text: root.count(modelData.calls)
                            color: root.dim
                            font.pointSize: Kirigami.Theme.smallFont.pointSize
                        }
                    }
                }
            }
        }
    }

    compactRepresentation: Item {
        id: holder
        Layout.minimumWidth: row.implicitWidth
        Layout.preferredWidth: row.implicitWidth
        Layout.fillWidth: true
        property real globalX: 0
        function place() { globalX = mapToGlobal(0, 0).x }
        onXChanged: place()
        onWidthChanged: place()
        Component.onCompleted: { root.compactItem = area; place() }

        MouseArea {
            id: walkway
            anchors.fill: parent
            hoverEnabled: true
            readonly property bool onHim: containsMouse && mouseX >= sprite.x + sprite.bodyX - sprite.px * 3 && mouseX <= sprite.x + sprite.bodyX + sprite.width + sprite.px * 3
            onEntered: sprite.pointerEntered()
            onExited: sprite.pointerLeft()
            onPositionChanged: sprite.pointerMoved(holder.globalX + mouseX, onHim)
            onClicked: if (onHim) sprite.clicked()
        }

        MouseArea {
            id: area
            width: row.implicitWidth
            height: parent.height
            x: Math.max(0, Math.min(holder.width - width, holder.Screen.virtualX + holder.Screen.width / 2 - holder.globalX - width / 2))
            onWidthChanged: root.compactWidth = width
            onClicked: root.drooped = !root.drooped

            RowLayout {
                id: row
                anchors.centerIn: parent
                spacing: Kirigami.Units.largeSpacing

                Item {
                    id: home
                    Layout.preferredWidth: sprite.width
                    Layout.preferredHeight: sprite.height
                }

                RowLayout {
                    spacing: Kirigami.Units.smallSpacing
                    PlasmaComponents.Label {
                        visible: !root.botData
                        text: "bots n/a"
                        color: root.dim
                        font.pointSize: Kirigami.Theme.smallFont.pointSize
                    }
                    Repeater {
                        model: root.activeBots
                        BotChip { bot: modelData }
                    }
                    IdleChip { visible: root.idleBots.length > 0 }
                    AgentTotal { visible: !!root.botData }
                }
                Pip {}
                Meter { label: "5h"; win: root.bar ? root.bar.five_hour : null }
                Pip {}
                Meter { label: "7d"; win: root.bar ? root.bar.seven_day : null }
            }
        }

        Clawd {
            id: sprite
            originX: holder.globalX
            homeX: holder.globalX + area.x + row.x + home.x
            minX: holder.globalX + Kirigami.Units.largeSpacing
            y: Math.round((holder.height - height) / 2)
            maxX: homeX
        }
    }

    onDroopedChanged: {
        if (drooped) {
            executable.connectSource(root.costCommand)
            droop.visible = true
            droop.requestActivate()
            reveal.to = 1
            reveal.easing.type = Easing.OutBack
            reveal.duration = 320
        } else {
            reveal.to = 0
            reveal.easing.type = Easing.InCubic
            reveal.duration = 160
        }
        reveal.restart()
    }

    NumberAnimation {
        id: reveal
        target: notch
        property: "progress"
        onFinished: if (!root.drooped) droop.visible = false
    }

    PlasmaCore.Dialog {
        id: droop
        visualParent: root.compactItem
        location: PlasmaCore.Types.TopEdge
        type: PlasmaCore.Dialog.PopupMenu
        flags: Qt.WindowStaysOnTopHint
        backgroundHints: PlasmaCore.Dialog.NoBackground
        hideOnWindowDeactivate: true
        onVisibleChanged: if (!visible) { root.drooped = false; notch.progress = 0 }

        mainItem: Item {
            id: notch
            property real progress: 0
            focus: true
            Keys.onEscapePressed: root.drooped = false
            Kirigami.Theme.colorSet: Kirigami.Theme.Window
            Kirigami.Theme.inherit: false
            readonly property real bodyWidth: Math.max(root.compactWidth, content.implicitWidth) + Kirigami.Units.gridUnit * 1.6
            readonly property real maxContent: (Screen.height > 0 ? Screen.height * 0.6 : Kirigami.Units.gridUnit * 36) - Kirigami.Units.gridUnit * 1.6 - footer.implicitHeight - Kirigami.Units.largeSpacing
            readonly property real fullHeight: content.implicitHeight + Kirigami.Units.gridUnit * 1.6
            readonly property real shownHeight: Math.max(0, fullHeight * progress)
            width: bodyWidth + root.ear * 2
            height: fullHeight * 1.1

            Shape {
                anchors.fill: parent
                preferredRendererType: Shape.CurveRenderer
                ShapePath {
                    id: sp
                    readonly property real e: root.ear
                    readonly property real w: notch.bodyWidth
                    readonly property real h: Math.max(notch.shownHeight, e + 1)
                    readonly property real r: Math.min(root.bottomRadius, h - e)
                    strokeWidth: -1
                    fillColor: Qt.tint(Kirigami.Theme.backgroundColor, Qt.alpha(Kirigami.Theme.textColor, 0.08))
                    startX: 0; startY: 0
                    PathQuad { controlX: sp.e; controlY: 0; x: sp.e; y: sp.e }
                    PathLine { x: sp.e; y: sp.h - sp.r }
                    PathQuad { controlX: sp.e; controlY: sp.h; x: sp.e + sp.r; y: sp.h }
                    PathLine { x: sp.e + sp.w - sp.r; y: sp.h }
                    PathQuad { controlX: sp.e + sp.w; controlY: sp.h; x: sp.e + sp.w; y: sp.h - sp.r }
                    PathLine { x: sp.e + sp.w; y: sp.e }
                    PathQuad { controlX: sp.e + sp.w; controlY: 0; x: sp.e * 2 + sp.w; y: 0 }
                    PathLine { x: 0; y: 0 }
                }
            }

            Item {
                x: root.ear
                width: notch.bodyWidth
                height: notch.shownHeight
                clip: true

                ColumnLayout {
                    id: content
                    x: Kirigami.Units.gridUnit * 0.8
                    y: Kirigami.Units.gridUnit * 0.6
                    width: parent.width - Kirigami.Units.gridUnit * 1.6
                    spacing: Kirigami.Units.largeSpacing
                    opacity: Math.min(1, Math.max(0, notch.progress * 1.6 - 0.4))

                    RowLayout {
                        id: columnsRow
                        Layout.fillWidth: true
                        spacing: Kirigami.Units.gridUnit

                        ColumnLayout {
                            id: agentsColumn
                            Layout.preferredWidth: Kirigami.Units.gridUnit * 24
                            Layout.fillWidth: true
                            Layout.alignment: Qt.AlignTop
                            spacing: Kirigami.Units.largeSpacing

                            Flickable {
                                id: cardScroll
                                Layout.fillWidth: true
                                Layout.preferredHeight: Math.min(cardList.implicitHeight, Math.max(Kirigami.Units.gridUnit * 6, notch.maxContent))
                                contentWidth: width
                                contentHeight: cardList.implicitHeight
                                interactive: contentHeight > height
                                boundsBehavior: Flickable.StopAtBounds
                                clip: true
                                PlasmaComponents.ScrollBar.vertical: PlasmaComponents.ScrollBar {
                                    id: cardBar
                                    policy: cardScroll.interactive ? PlasmaComponents.ScrollBar.AsNeeded : PlasmaComponents.ScrollBar.AlwaysOff
                                }

                                BotsPanel {
                                    id: cardList
                                    width: cardScroll.width - (cardScroll.interactive ? cardBar.width + Kirigami.Units.smallSpacing : 0)
                                }
                            }
                        }

                        Rectangle {
                            visible: agentsColumn.visible
                            Layout.preferredWidth: 1
                            Layout.fillHeight: true
                            color: root.hairline
                        }

                        ColumnLayout {
                            id: limitsColumn
                            Layout.preferredWidth: Kirigami.Units.gridUnit * 20
                            Layout.fillWidth: true
                            Layout.alignment: Qt.AlignTop
                            spacing: 0
                            LimitRow {
                                key: "five_hour"
                                title: "Session"
                                sub: "5h window"
                                burnTitle: "Burning this half hour"
                                windowTitle: "This window"
                                window: root.costs && root.costs.window ? root.costs.window.five_hour : null
                                win: root.bar ? root.bar.five_hour : null
                                spend: root.costs && root.costs.projects ? root.costs.projects.half_hour : []
                            }
                            LimitRow {
                                key: "seven_day"
                                separated: true
                                title: "Weekly"
                                sub: "7d window"
                                burnTitle: "Burning this week"
                                win: root.bar ? root.bar.seven_day : null
                                spend: root.weekSpend
                            }
                        }

                        Rectangle {
                            visible: costColumn.visible
                            Layout.preferredWidth: 1
                            Layout.fillHeight: true
                            color: root.hairline
                        }

                        ColumnLayout {
                            id: costColumn
                            visible: !!root.costs || root.remoteHosts.length > 0
                            Layout.preferredWidth: Kirigami.Units.gridUnit * 18
                            Layout.alignment: Qt.AlignTop
                            spacing: Kirigami.Units.largeSpacing

                            Costs {
                                visible: !!root.costs
                                Layout.fillWidth: true
                            }

                            Tokens {
                                visible: !!root.costs && !!root.costs.tokens
                                Layout.fillWidth: true
                            }

                            Rectangle {
                                visible: !!root.costs && root.remoteHosts.length > 0
                                Layout.fillWidth: true
                                Layout.preferredHeight: 1
                                color: root.hairline
                            }

                            Hosts {
                                visible: root.remoteHosts.length > 0
                                Layout.fillWidth: true
                            }
                        }
                    }

                    RowLayout {
                        id: footer
                        Layout.fillWidth: true
                        spacing: Kirigami.Units.smallSpacing
                        Item { Layout.fillWidth: true }
                        Kirigami.Icon {
                            source: "configure"
                            color: gearHover.containsMouse ? Kirigami.Theme.textColor : root.dim
                            isMask: true
                            Layout.preferredWidth: Kirigami.Units.iconSizes.small
                            Layout.preferredHeight: Kirigami.Units.iconSizes.small
                            MouseArea {
                                id: gearHover
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: root.openSettings()
                            }
                        }
                    }
                }
            }
        }
    }
}
