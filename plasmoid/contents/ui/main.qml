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
    readonly property string costCommand: "python3 '" + Qt.resolvedUrl("../code/costs.py").toString().replace("file://", "") + "'"
    property var costs: null
    property var bar: null
    property real now: Date.now() / 1000
    property real compactWidth: Kirigami.Units.gridUnit * 20
    property Item compactItem: null
    property bool drooped: false
    property bool showIdle: false

    readonly property real ear: Kirigami.Units.gridUnit * 0.7
    readonly property real bottomRadius: Kirigami.Units.gridUnit * 1.1

    readonly property var agents: bar && bar.agents ? bar.agents : null
    readonly property var everyAgent: agents ? agents.list.reduce((all, a) => all.concat([a], a.workers || []), []) : []
    readonly property var fleet: bar && bar.fleet ? bar.fleet : null
    readonly property var projects: fleet ? fleet.projects : []
    readonly property var quietProjects: projects.filter(p => p.status === "idle" && p.subagents.length === 0)
    readonly property var shownProjects: showIdle ? projects : projects.filter(p => !quietProjects.includes(p))
    readonly property var orchCells: projects.map(p => ({ status: p.status, ctx: p.ctx }))
    readonly property var subCells: projects.reduce((all, p) => all.concat(p.subagents.map(s => ({ status: s.status, ctx: null }))), [])
    readonly property var stateOrder: ["waiting", "error", "working", "delegating", "done", "idle"]
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
    readonly property color dim: Kirigami.Theme.disabledTextColor
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

    function bucket(cells, states) {
        return cells.filter(c => states.includes(c.status)).sort((a, b) => stateOrder.indexOf(a.status) - stateOrder.indexOf(b.status))
    }

    function worstOf(project) {
        return [project.status].concat(project.subagents.map(s => s.status)).sort((a, b) => stateOrder.indexOf(a) - stateOrder.indexOf(b))[0]
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

    function project(path) {
        const parts = (path || "").split("/").filter(p => p)
        return parts.length ? parts[parts.length - 1] : "~"
    }

    function focusAgent(terminalId) {
        if (String(terminalId).startsWith("ext:"))
            return
        executable.connectSource("\"$HOME/.local/bin/herdr\" agent focus " + terminalId)
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

    function modelName(model) {
        return model.replace(/^claude-/, "").replace(/-\d{8}$/, "").replace(/-(\d+)-(\d+)$/, " $1.$2").replace(/-(\d+)$/, " $1")
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
        readonly property real period: Math.max(2, Kirigami.Units.smallSpacing) / Math.SQRT2
        ShapePath {
            strokeWidth: -1
            fillGradient: LinearGradient {
                x2: stripes.period
                y2: stripes.period
                spread: ShapeGradient.RepeatSpread
                GradientStop { position: 0; color: root.active }
                GradientStop { position: 0.5; color: root.active }
                GradientStop { position: 0.5; color: Qt.alpha(root.active, 0.45) }
                GradientStop { position: 1; color: Qt.alpha(root.active, 0.45) }
            }
            PathLine { x: stripes.width; y: 0 }
            PathLine { x: stripes.width; y: stripes.height }
            PathLine { x: 0; y: stripes.height }
            PathLine { x: 0; y: 0 }
        }
    }

    component Throb: QtObject {
        id: throbber
        property bool beating: false
        property real value: 1
        SequentialAnimation on value {
            running: throbber.beating && Kirigami.Units.longDuration > 0
            loops: Animation.Infinite
            NumberAnimation { to: 0.25; duration: 700; easing.type: Easing.InOutQuad }
            NumberAnimation { to: 1; duration: 700; easing.type: Easing.InOutQuad }
        }
    }

    component StateMark: Rectangle {
        id: mark
        property string status
        readonly property real dpr: Screen.devicePixelRatio || 1
        color: status === "delegating" || status === "done" ? "transparent" : root.stateColor(status)
        border.width: status === "done" ? Math.max(1, Math.round(dpr)) / dpr : 0
        border.color: root.active
        opacity: status === "waiting" ? throb.value : 1
        Stripes {
            anchors.fill: parent
            visible: mark.status === "delegating"
        }
        Throb {
            id: throb
            beating: mark.status === "waiting" && mark.visible
        }
    }

    component Stack: Item {
        id: stack
        property var cells: []
        property color tint
        property int columns: 2
        property int rows: 2
        property real share: 0.2
        readonly property real dpr: Screen.devicePixelRatio || 1
        readonly property real cell: Math.max(2, Math.round(Kirigami.Units.gridUnit * share * dpr)) / dpr
        readonly property real gap: Math.max(1, Math.round(dpr)) / dpr
        readonly property int overflow: Math.max(0, cells.length - columns * rows)
        implicitWidth: grid.width + (more.visible ? gap * 2 + more.implicitWidth : 0)
        implicitHeight: rows * cell + rows * gap + tab.height
        Layout.alignment: Qt.AlignVCenter

        Grid {
            id: grid
            columns: stack.columns
            spacing: stack.gap
            Repeater {
                model: stack.columns * stack.rows
                Rectangle {
                    id: slotCell
                    readonly property int slot: (stack.rows - 1 - Math.floor(index / stack.columns)) * stack.columns + index % stack.columns
                    readonly property var entry: slot < stack.cells.length ? stack.cells[slot] : null
                    readonly property string status: entry ? entry.status : ""
                    width: stack.cell
                    height: stack.cell
                    color: !entry ? Qt.alpha(stack.tint, 0.18)
                        : status === "delegating" ? "transparent"
                        : root.levelColor(root.ctxLevel(entry.ctx), root.stateColor(status))
                    opacity: status === "waiting" ? throb.value : 1
                    Stripes {
                        anchors.fill: parent
                        visible: slotCell.status === "delegating"
                    }
                    Throb {
                        id: throb
                        beating: slotCell.status === "waiting" && stack.visible
                    }
                }
            }
        }
        Rectangle {
            id: tab
            anchors.bottom: parent.bottom
            width: grid.width
            height: Math.max(2, Math.round(Kirigami.Units.smallSpacing / 2 * stack.dpr)) / stack.dpr
            color: stack.tint
        }
        PlasmaComponents.Label {
            id: more
            visible: stack.overflow > 0
            x: grid.width + stack.gap * 2
            anchors.verticalCenter: grid.verticalCenter
            text: "+" + stack.overflow
            color: root.dim
            font.pointSize: Kirigami.Theme.smallFont.pointSize * 0.85
        }
    }

    component Tier: RowLayout {
        id: tier
        property var cells: []
        property int columns: 2
        property int rows: 2
        property real share: 0.2
        readonly property var attention: root.bucket(cells, ["waiting", "error"])
        spacing: Kirigami.Units.smallSpacing
        Stack { cells: root.bucket(tier.cells, ["working", "delegating"]); tint: root.ok; columns: tier.columns; rows: tier.rows; share: tier.share }
        Stack { cells: tier.attention; tint: tier.attention.length && tier.attention[0].status === "error" ? root.critical : root.blocked; columns: tier.columns; rows: tier.rows; share: tier.share }
        Stack { cells: root.bucket(tier.cells, ["done", "idle"]); tint: root.dim; columns: tier.columns; rows: tier.rows; share: tier.share }
    }

    component Costs: ColumnLayout {
        spacing: Kirigami.Units.smallSpacing
        readonly property var daily: root.costs ? root.costs.daily : []
        readonly property real peak: Math.max(1, ...daily.map(d => d.cost))

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
                    { label: "Today", value: root.costs ? root.costs.today : null },
                    { label: "7 days", value: root.costs ? root.costs.week : null },
                    { label: "30 days", value: root.costs ? root.costs.month : null }
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

            Item { Layout.fillWidth: true }

            Row {
                id: week
                readonly property real dpr: Screen.devicePixelRatio || 1
                readonly property real cell: Math.max(2, Math.round(Kirigami.Units.gridUnit * 0.2 * dpr)) / dpr
                readonly property real gap: Math.max(1, Math.round(dpr)) / dpr
                readonly property int levels: 8
                Layout.alignment: Qt.AlignBottom
                spacing: gap * 2
                Repeater {
                    model: daily
                    Column {
                        readonly property int lit: modelData.cost > 0 ? Math.max(1, Math.round(modelData.cost / peak * week.levels)) : 0
                        readonly property bool isToday: index === daily.length - 1
                        spacing: week.gap
                        Repeater {
                            model: week.levels
                            Rectangle {
                                width: week.cell * 2 + week.gap
                                height: week.cell
                                color: week.levels - index <= lit
                                    ? (isToday ? Kirigami.Theme.highlightColor : Qt.alpha(Kirigami.Theme.textColor, 0.55))
                                    : Qt.alpha(Kirigami.Theme.textColor, 0.08)
                            }
                        }
                        PlasmaComponents.Label {
                            anchors.horizontalCenter: parent.horizontalCenter
                            text: new Date(modelData.day + "T12:00:00").toLocaleString(Qt.locale(), "ddd").slice(0, 1)
                            color: root.dim
                            font.pointSize: Kirigami.Theme.smallFont.pointSize * 0.85
                        }
                    }
                }
            }
        }

        Flow {
            Layout.fillWidth: true
            spacing: Kirigami.Units.largeSpacing
            Repeater {
                model: root.costs ? root.costs.models.filter(m => m.cost >= 0.5).slice(0, 4) : []
                PlasmaComponents.Label {
                    text: root.modelName(modelData.model) + " " + root.money(modelData.cost)
                    color: root.dim
                    font.pointSize: Kirigami.Theme.smallFont.pointSize
                }
            }
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

    component Limit: ColumnLayout {
        id: limit
        property string title
        property var win
        readonly property real pct: win ? win.pct : 0
        readonly property color accent: win ? root.pctColor(pct) : root.dim
        Layout.fillWidth: true
        Layout.preferredWidth: 1
        spacing: Kirigami.Units.smallSpacing
        opacity: root.bar && root.bar.stale ? 0.5 : 1

        RowLayout {
            Layout.fillWidth: true
            PlasmaComponents.Label {
                Layout.fillWidth: true
                text: limit.title
                color: root.dim
                font.pointSize: Kirigami.Theme.smallFont.pointSize
                font.capitalization: Font.AllUppercase
                font.letterSpacing: 1
            }
            PlasmaComponents.Label {
                text: limit.win ? Math.round(limit.pct) + "%" : "--"
                color: limit.accent
                font.weight: Font.DemiBold
            }
        }
        Bar {
            Layout.fillWidth: true
            pct: limit.pct
            fill: limit.accent
        }
        PlasmaComponents.Label {
            Layout.fillWidth: true
            elide: Text.ElideRight
            text: limit.win && limit.win.resets_at
                ? root.timeLeft(limit.win.resets_at) + " · " + root.resetClock(limit.win.resets_at)
                : " "
            color: root.dim
            font.pointSize: Kirigami.Theme.smallFont.pointSize
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

    component Totals: GridLayout {
        id: totals
        readonly property var orch: root.fleet ? root.fleet.orchestrators : ({ working: 0, delegating: 0, waiting: 0, idle: 0, total: 0 })
        readonly property var subs: root.fleet ? root.fleet.subagents : ({ working: 0, waiting: 0, error: 0, done: 0, total: 0 })
        readonly property real glyph: Kirigami.Units.gridUnit * 0.4
        columns: 5
        rowSpacing: Kirigami.Units.smallSpacing
        columnSpacing: Kirigami.Units.gridUnit

        Item { Layout.fillWidth: true }
        Heading { Layout.alignment: Qt.AlignRight; text: "running" }
        Heading { Layout.alignment: Qt.AlignRight; text: "needs you" }
        Heading { Layout.alignment: Qt.AlignRight; text: "idle" }
        Heading { Layout.alignment: Qt.AlignRight; text: "total" }

        RowLayout {
            Layout.fillWidth: true
            spacing: Kirigami.Units.smallSpacing * 1.5
            Item {
                Layout.preferredWidth: totals.glyph
                Layout.preferredHeight: totals.glyph
                Rectangle {
                    anchors.centerIn: parent
                    width: parent.width * 0.75
                    height: width
                    rotation: 45
                    color: totals.orch.total - totals.orch.idle > 0 ? Kirigami.Theme.textColor : "transparent"
                    border.width: 1
                    border.color: totals.orch.total - totals.orch.idle > 0 ? Kirigami.Theme.textColor : root.dim
                }
            }
            PlasmaComponents.Label { text: "orchestrators" }
        }
        RowLayout {
            Layout.alignment: Qt.AlignRight
            spacing: Kirigami.Units.smallSpacing
            PlasmaComponents.Label {
                visible: totals.orch.delegating > 0
                text: totals.orch.delegating + " delegating"
                color: root.active
                font.pointSize: Kirigami.Theme.smallFont.pointSize
            }
            Tally { value: totals.orch.working + totals.orch.delegating; tone: root.ok }
        }
        Tally { value: totals.orch.waiting; tone: root.blocked }
        Tally { value: totals.orch.idle; tone: root.dim }
        Tally { value: totals.orch.total; font.weight: Font.DemiBold }

        RowLayout {
            Layout.fillWidth: true
            spacing: Kirigami.Units.smallSpacing * 1.5
            Grid {
                columns: 2
                spacing: 1
                Repeater {
                    model: 4
                    Rectangle {
                        width: Kirigami.Units.gridUnit * 0.17
                        height: width
                        color: root.ok
                    }
                }
            }
            PlasmaComponents.Label { text: "subagents" }
        }
        Tally { value: totals.subs.working; tone: root.ok }
        Tally { value: totals.subs.waiting + totals.subs.error; tone: totals.subs.waiting ? root.blocked : root.critical }
        Tally { value: totals.subs.done; tone: root.dim }
        Tally { value: totals.subs.total; font.weight: Font.DemiBold }
    }

    component SubRow: Rectangle {
        id: subRow
        property var sub
        readonly property string need: sub.status === "waiting" ? (sub.need === "question" ? "asks you" : "wants " + (sub.tool || "permission"))
            : sub.status === "error" ? "failed"
            : sub.status === "done" ? "done"
            : ""
        Layout.fillWidth: true
        implicitHeight: Kirigami.Units.gridUnit * 1.25
        radius: Kirigami.Units.cornerRadius
        color: sub.status === "waiting" ? Qt.alpha(root.blocked, 0.14) : sub.status === "error" ? Qt.alpha(root.critical, 0.12) : "transparent"

        RowLayout {
            anchors.fill: parent
            anchors.leftMargin: Kirigami.Units.smallSpacing
            anchors.rightMargin: Kirigami.Units.smallSpacing
            spacing: Kirigami.Units.smallSpacing * 1.5

            StateMark {
                status: subRow.sub.status
                Layout.preferredWidth: Kirigami.Units.gridUnit * 0.4
                Layout.preferredHeight: Kirigami.Units.gridUnit * 0.4
            }
            PlasmaComponents.Label {
                Layout.fillWidth: true
                text: subRow.sub.description
                elide: Text.ElideRight
                font.pointSize: Kirigami.Theme.smallFont.pointSize
            }
            PlasmaComponents.Label {
                visible: subRow.need !== ""
                text: subRow.need
                color: root.stateColor(subRow.sub.status)
                font.pointSize: Kirigami.Theme.smallFont.pointSize
            }
            Rectangle {
                Layout.preferredWidth: tag.implicitWidth + Kirigami.Units.smallSpacing * 2
                Layout.preferredHeight: tag.implicitHeight
                radius: Kirigami.Units.cornerRadius
                color: "transparent"
                border.width: 1
                border.color: root.hairline
                PlasmaComponents.Label {
                    id: tag
                    anchors.centerIn: parent
                    text: (subRow.sub.type === "general-purpose" ? "agent" : subRow.sub.type || "agent") + (subRow.sub.model ? " · " + subRow.sub.model : "")
                    color: root.dim
                    font.pointSize: Kirigami.Theme.smallFont.pointSize * 0.85
                }
            }
            PlasmaComponents.Label {
                text: root.minutes(subRow.sub.started_at)
                color: root.dim
                horizontalAlignment: Text.AlignRight
                font.pointSize: Kirigami.Theme.smallFont.pointSize
                Layout.minimumWidth: Kirigami.Units.gridUnit * 1.4
            }
        }
    }

    component ProjectCard: Rectangle {
        id: card
        property var project
        readonly property string worst: root.worstOf(project)
        readonly property int running: project.subagents.filter(s => s.status === "working" || s.status === "waiting").length
        readonly property string level: root.ctxLevel(project.ctx)
        Layout.fillWidth: true
        implicitHeight: body.implicitHeight + Kirigami.Units.smallSpacing * 4
        radius: Kirigami.Units.cornerRadius * 2
        color: hover.containsMouse ? Qt.alpha(Kirigami.Theme.highlightColor, 0.2) : Qt.alpha(Kirigami.Theme.textColor, 0.06)
        border.width: worst === "waiting" || worst === "error" ? 1 : 0
        border.color: Qt.alpha(worst === "error" ? root.critical : root.blocked, 0.55)

        MouseArea {
            id: hover
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: root.focusAgent(card.project.terminal_id)
        }

        ColumnLayout {
            id: body
            anchors.fill: parent
            anchors.margins: Kirigami.Units.smallSpacing * 2
            spacing: Kirigami.Units.smallSpacing

            RowLayout {
                Layout.fillWidth: true
                spacing: Kirigami.Units.smallSpacing * 1.5
                StateMark {
                    status: card.project.status
                    radius: 1
                    Layout.preferredWidth: Kirigami.Units.gridUnit * 0.3
                    Layout.preferredHeight: Kirigami.Units.gridUnit * 0.75
                }
                PlasmaComponents.Label {
                    text: card.project.name
                    font.weight: Font.Bold
                    elide: Text.ElideRight
                    Layout.maximumWidth: card.width * 0.4
                }
                PlasmaComponents.Label {
                    text: card.project.status === "waiting" ? "asks you"
                        : card.project.status === "delegating" ? "delegating · " + card.running + (card.running === 1 ? " subagent" : " subagents")
                        : card.project.status
                    color: card.project.status === "idle" ? root.dim : root.stateColor(card.project.status)
                    font.pointSize: Kirigami.Theme.smallFont.pointSize
                }
                PlasmaComponents.Label {
                    Layout.fillWidth: true
                    text: card.project.session
                    color: root.dim
                    elide: Text.ElideRight
                    font.pointSize: Kirigami.Theme.smallFont.pointSize
                }
                PlasmaComponents.Label {
                    visible: card.project.ctx !== null && card.project.ctx !== undefined
                    text: Math.round(card.project.ctx) + "%"
                    color: root.levelColor(card.level, root.dim)
                    font.family: "monospace"
                    font.weight: card.level ? Font.DemiBold : Font.Normal
                    font.pointSize: Kirigami.Theme.smallFont.pointSize
                }
                PlasmaComponents.Label {
                    visible: card.project.subagents.length > 0
                    text: card.project.subagents.length + " sub"
                    color: root.dim
                    font.pointSize: Kirigami.Theme.smallFont.pointSize
                }
            }

            RowLayout {
                visible: card.project.subagents.length > 0
                Layout.fillWidth: true
                Layout.leftMargin: Kirigami.Units.smallSpacing / 2
                spacing: Kirigami.Units.smallSpacing * 1.5
                Rectangle {
                    Layout.fillHeight: true
                    Layout.preferredWidth: 1
                    color: root.hairline
                }
                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 0
                    Repeater {
                        model: card.project.subagents
                        SubRow { sub: modelData }
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
                    spacing: Kirigami.Units.largeSpacing
                    Tier { cells: root.orchCells; columns: 2; rows: 2; share: 0.2 }
                    Rectangle {
                        Layout.preferredWidth: 1
                        Layout.preferredHeight: Kirigami.Units.gridUnit * 0.9
                        Layout.alignment: Qt.AlignVCenter
                        color: Qt.alpha(Kirigami.Theme.textColor, 0.2)
                    }
                    Tier { cells: root.subCells; columns: 4; rows: 4; share: 0.15 }
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
            readonly property real bodyWidth: Math.max(root.compactWidth, Kirigami.Units.gridUnit * 22) + Kirigami.Units.gridUnit
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
                        Layout.fillWidth: true
                        spacing: Kirigami.Units.gridUnit
                        Limit { title: "Session"; win: root.bar ? root.bar.five_hour : null }
                        Limit { title: "Weekly"; win: root.bar ? root.bar.seven_day : null }
                    }

                    Rectangle {
                        Layout.fillWidth: true
                        Layout.preferredHeight: 1
                        color: root.hairline
                    }

                    Costs {
                        Layout.fillWidth: true
                        visible: !!root.costs
                    }

                    Rectangle {
                        visible: !!root.costs
                        Layout.fillWidth: true
                        Layout.preferredHeight: 1
                        color: root.hairline
                    }

                    PlasmaComponents.Label {
                        visible: !root.agents && root.projects.length === 0
                        text: "herdr not reachable"
                        color: root.dim
                    }
                    PlasmaComponents.Label {
                        visible: root.projects.length > 0 && root.projects.length === root.quietProjects.length && !root.showIdle
                        text: "No agents running"
                        color: root.dim
                    }

                    Totals {
                        visible: root.projects.length > 0
                        Layout.fillWidth: true
                    }

                    Heading {
                        visible: root.shownProjects.length > 0
                        text: "Per project"
                    }

                    ColumnLayout {
                        visible: root.shownProjects.length > 0
                        Layout.fillWidth: true
                        spacing: Kirigami.Units.smallSpacing
                        Repeater {
                            model: root.shownProjects
                            ProjectCard { project: modelData }
                        }
                    }

                    RowLayout {
                        Layout.fillWidth: true
                        PlasmaComponents.Label {
                            visible: root.quietProjects.length > 0
                            text: (root.showIdle ? "Hide " : "Show ") + root.quietProjects.length + " idle"
                            color: idleHover.containsMouse ? Kirigami.Theme.textColor : root.dim
                            font.pointSize: Kirigami.Theme.smallFont.pointSize
                            MouseArea {
                                id: idleHover
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: root.showIdle = !root.showIdle
                            }
                        }
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
