pragma Singleton
import QtQuick
import QtMultimedia
import Quickshell
import qs.core
import qs.widgets
import "BubbleLogic.js" as B

// What the Bubble monitor shows and how it moves: the snapshots of the
// `bubble` topic (src/lib.rs), the world of bubbles and its physics, the
// camera, the open bubble and the facts of its page. The page (Page.qml) only
// draws this. It lives outside the popup, so reopening it finds the bubbles
// where they were; it samples and moves only while `active`.
//
// From lukpednoi's Anserin (https://github.com/lukpednoi/Anserin,
// AGPL-3.0-or-later): the script of src/quickshell/blankpanel/pages/
// BubbleMonitor.qml at 1909479, itself descended from ilyamiro's Serpantinum.
// Changed for Fableland: the data comes from the daemon instead of a Python
// feed; the state moved out of the page into this singleton; the camera's zoom
// is measured in Fableland's UI scale.
Singleton {
    id: root

    // ---------- the popup and its page tell ----------
    property bool active: false        // the popup is open
    property real viewW: 1             // the field's size, real pixels
    property real viewH: 1
    property real cardW: 1             // the width of an open bubble's page, on the left
    // Full screen (FullScreen.qml): the bubbles have the whole screen at 50 %,
    // processes and apps together.
    property bool full: false

    // ---------- config (as the design's main.js) ----------
    readonly property int tickMs: 1000
    readonly property var worldSize: ({ w: 1265, h: 1080 })
    // The camera's zoom is in real pixels per world unit, so 100 % is the UI scale.
    readonly property real zoomMin: 0.3 * Theme.scale
    readonly property real zoomMax: Theme.scale
    readonly property real smoothTau: 0.3
    readonly property real hotCpu: 45
    readonly property int maxProcs: 12
    readonly property int linger: 8000          // ms a process stays after leaving the busiest
    readonly property var kindLabel: ({ app: "App", dev: "Dev", sys: "System" })
    function procR(cpu) { return 24 + Math.sqrt(Math.max(0, cpu)) * 7.5; }

    // ---------- state ----------
    property var world: new B.World(worldSize.w, worldSize.h, { attract: 0 })     // they drift, nothing pulls
    property real worldW: worldSize.w      // the world's size, for bindings
    property real worldH: worldSize.h
    property real bumpAt: 0
    property var ms: ({
        snap: null, lastTick: Date.now(),
        cores: B.fill(16, () => ({ t: 0, v: 0 })),
        hist: B.fill(62, () => 0), tempHist: B.fill(62, () => 50), up: B.fill(44, () => 0), down: B.fill(44, () => 0),
        temp: { t: 50, v: 50 }, apps: { t: 0, v: 0 }, cache: { t: 0, v: 0 }, netU: { t: 0, v: 0 }, netD: { t: 0, v: 0 },
        maxU: 10, maxD: 40, camT: null, camBack: null, press: null, pan: null, open: null, period: 1000,
        dR: { t: 0, v: 0 }, dW: { t: 0, v: 0 }, dRh: B.fill(44, () => 0), dWh: B.fill(44, () => 0), maxDR: 5, maxDW: 5
    })
    property real camX: 0
    property real camY: 0
    property real camZ: 0.7 * Theme.scale
    property bool camReady: false
    property var camHome: null           // the camera in the popup, kept while full screen
    property int tick: 0                 // bumped every frame; what the bubbles redraw by
    property real clock: 0
    // what the dials and the pages show (set each frame)
    property real vAvg: 0
    property real vTemp: 50
    property real vMem: 0
    property real vTotal: 8
    property real vDisk: 0                   // the drives' used share
    property var battery: null               // { pct, plugged } (none without a battery)
    // What the field shows besides the dials: in the popup either the busiest
    // processes or the open apps (the switch top left); full screen, both.
    property string mode: "procs"
    readonly property bool showProcs: mode === "procs" || full
    readonly property bool showApps: mode === "apps" || full
    onShowProcsChanged: refill()
    onShowAppsChanged: refill()
    // The open bubble's page (details()), worked out again four times a second
    // or when another bubble opens; what moves every frame reads `phase`.
    property var info: null
    property string infoId: ""
    property real infoAt: 0
    property real phase: 0
    // where the scan dot is: it moves on at the samples' real pace, and each
    // sample takes one run off, so it never jumps
    property real sweep: 0
    property int swapDir: 1                  // which way the next page change moves: 1 up, -1 down
    property var ov: null                    // the open bubble's page: where it is and all it shows
    readonly property color fg: Look.text
    readonly property color fgAccent: ov ? ov.color : Look.accent

    // { nid } of every bubble on the field, in the world's order; each Bubble registers itself
    property ListModel bubbles: ListModel {}
    property var bubbleItems: ({})

    function dialFrac(k) {
        return B.clamp(k === "cpu" ? vAvg / 100 : k === "mem" ? vMem / vTotal : k === "temp" ? (vTemp - 30) / 70
                     : k === "disk" ? vDisk : ms.netD.v / 120, 0.01, 1);
    }
    function dialText(k) {
        return k === "cpu" ? Math.round(vAvg) + "%" : k === "mem" ? vMem.toFixed(1) + "G" : k === "temp" ? Math.round(vTemp) + "°"
             : k === "disk" ? Math.round(vDisk * 100) + "%" : ms.netD.v.toFixed(0) + "M";
    }

    // ---------- data in ----------
    Want {
        topic: "bubble"
        active: root.active
    }
    readonly property var snapshot: Daemon.topic("bubble", null)
    onSnapshotChanged: if (active && snapshot) onSnapshot(snapshot)

    function onSnapshot(snap) {
        const st = ms;
        const n = snap.cpu.cores.length;
        if (!n) return;
        if (st.cores.length !== n) st.cores = B.fill(n, () => ({ t: 0, v: 0 }));
        if (!st.snap) {           // first sample: start graphs and dials at real values instead of zero
            const a0 = snap.cpu.cores.reduce((a, b) => a + b, 0) / n;
            st.hist.fill(a0); st.tempHist.fill(snap.tempC); st.up.fill(snap.net.upMBs); st.down.fill(snap.net.downMBs);
            snap.cpu.cores.forEach((v, i) => { st.cores[i].v = v; });
            st.temp.v = snap.tempC; st.apps.v = snap.mem.appsGB; st.cache.v = snap.mem.cacheGB;
        }
        st.snap = snap;
        snap.cpu.cores.forEach((v, i) => { st.cores[i].t = v; });
        const avg = snap.cpu.cores.reduce((a, b) => a + b, 0) / n;
        const push = (arr, v) => { arr.push(v); arr.shift(); };
        push(st.hist, avg); push(st.tempHist, snap.tempC); push(st.up, snap.net.upMBs); push(st.down, snap.net.downMBs);
        st.temp.t = snap.tempC; st.apps.t = snap.mem.appsGB; st.cache.t = snap.mem.cacheGB; st.netU.t = snap.net.upMBs; st.netD.t = snap.net.downMBs;
        st.dR.t = snap.disk.readMBs; st.dW.t = snap.disk.writeMBs;
        push(st.dRh, snap.disk.readMBs); push(st.dWh, snap.disk.writeMBs);
        const used = snap.disk.drives.reduce((a, d) => a + d.usedGB, 0), total = snap.disk.drives.reduce((a, d) => a + d.totalGB, 0);
        vDisk = total > 0 ? used / total : 0;
        battery = snap.battery || null;
        reconcileProcs(snap.procs);
        reconcileApps(snap.apps || []);
        sweep = Math.max(-0.3, sweep - 1);
        const gap = Date.now() - st.lastTick;
        if (gap > 300 && gap < 3000) st.period += (gap - st.period) * 0.3;
        st.lastTick = Date.now();
    }

    function refill() {
        closeNow();
        if (ms.snap) {
            reconcileProcs(ms.snap.procs);
            reconcileApps(ms.snap.apps || []);
        }
    }

    function addNode(props) {
        const n = world.add(props);
        bubbles.append({ nid: n.id });
        return n;
    }
    function seedMetrics() {
        [{ id: "cpu", name: "CPU", r0: 70 }, { id: "mem", name: "Memory", r0: 60 }, { id: "temp", name: "Thermal", r0: 54 },
         { id: "net", name: "Network", r0: 54 }, { id: "disk", name: "Disk", r0: 52 }]
            .forEach((m, i) => {
                const cell = (i * 7) % 16;
                addNode({ id: m.id, type: "metric", key: m.id, name: m.name, rT: m.r0,
                          x: ((cell % 4) + 0.5) * world.w / 4, y: (Math.floor(cell / 4) + 0.5) * world.h / 4 });
            });
    }
    // somewhere on a 4 × 4 grid, a little off its centre, drifting
    function placed(slot, offset) {
        const cell = (slot * 7 + offset) % 16;
        return { x: ((cell % 4) + 0.5) * world.w / 4 + (Math.random() - 0.5) * 140,
                 y: (Math.floor(cell / 4) + 0.5) * world.h / 4 + (Math.random() - 0.5) * 120,
                 vx: (Math.random() - 0.5) * 80, vy: (Math.random() - 0.5) * 80 };
    }
    // keep the process bubbles in step with the latest snapshot (keyed by pid)
    function reconcileProcs(procs) {
        const now = Date.now();
        if (!showProcs) {
            for (const n of world.nodes) if (n.type === "proc" && !n.dying) n.dying = now;
            return;
        }
        const top = procs.slice().sort((a, b) => b.cpu - a.cpu).slice(0, maxProcs);
        const seen = {};
        let slot = world.nodes.length;
        for (const p of top) {
            const id = "p" + p.pid; seen[id] = true;
            let n = world.find(id);
            if (!n || n.dying) {
                if (n) world.nodes = world.nodes.filter(x => x !== n);
                n = addNode(Object.assign({ id: id, type: "proc", pid: p.pid, cpu: p.cpu, rT: procR(p.cpu) }, placed(slot++, 0)));
            }
            Object.assign(n, { name: p.name, cmd: p.cmd, user: p.user, memMB: p.memMB, state: p.state, kind: B.classify(p.name, p.user),
                               cpuT: p.cpu, paused: p.state === "T", h: (n.h || B.fill(32, () => p.cpu)), outSince: 0,
                               threads: p.threads, started: p.started, cpuSec: p.cpuSec, readMB: p.readMB, writeMB: p.writeMB });
            n.h.push(p.cpu); n.h.shift();
        }
        // Dropped out of the busiest: it stays, easing down, until it has been
        // out for `linger` (a process near the cut would otherwise pop in and out
        // every second); the open bubble stays while its page is open.
        const byPid = {};
        for (const p of procs) byPid["p" + p.pid] = p;
        for (const n of world.nodes) {
            if (n.type !== "proc" || seen[n.id] || n.dying) continue;
            const p = byPid[n.id];
            if (p) Object.assign(n, { cpuT: p.cpu, memMB: p.memMB, state: p.state, paused: p.state === "T",
                                      threads: p.threads, cpuSec: p.cpuSec, readMB: p.readMB, writeMB: p.writeMB });
            else n.cpuT *= 0.7;
            n.h.push(n.cpuT); n.h.shift();
            if (!n.outSince) n.outSince = now;
            if (now - n.outSince > linger && !(ms.open && ms.open.id === n.id)) n.dying = now;
        }
        // and the field never holds more than a few over maxProcs: the quietest lingering ones go first
        const procNodes = world.nodes.filter(x => x.type === "proc" && !x.dying);
        const extra = procNodes.length - (maxProcs + 4);
        if (extra > 0) procNodes.filter(x => !seen[x.id] && !(ms.open && ms.open.id === x.id))
                               .sort((a, b) => a.cpuT - b.cpuT).slice(0, extra).forEach(x => x.dying = now);
    }
    // one bubble per open app (its windows' class), white, sized by all its processes' CPU together
    function reconcileApps(apps) {
        const now = Date.now(), seen = {};
        let slot = world.nodes.length;
        if (showApps) for (const a of apps) {
            const id = "a" + a.cls; seen[id] = true;
            let n = world.find(id);
            if (!n || n.dying) {
                if (n) world.nodes = world.nodes.filter(x => x !== n);
                n = addNode(Object.assign({ id: id, type: "group", cpu: a.cpu, rT: procR(a.cpu) }, placed(slot++, 3)));
            }
            Object.assign(n, { name: a.name, cls: a.cls, cpuT: a.cpu, memMB: a.memMB, windows: a.windows, ws: a.ws, titles: a.titles,
                               procCount: a.procCount, procs: a.procs, h: (n.h || B.fill(32, () => a.cpu)) });
            n.h.push(a.cpu); n.h.shift();
        }
        // a closed app goes (its page stays open until closed)
        for (const n of world.nodes)
            if (n.type === "group" && !seen[n.id] && !n.dying && !(ms.open && ms.open.id === n.id)) n.dying = now;
    }

    // ---------- the camera ----------
    function toWorld(p) { return { x: (p.x - camX) / camZ, y: (p.y - camY) / camZ }; }
    // the world centred in the view, as the design opens it (70 %)
    function placeCamera() {
        const z = B.clamp(0.7 * Theme.scale, zoomMin, zoomMax);
        camX = viewW / 2 - world.w / 2 * z; camY = viewH / 2 - world.h / 2 * z; camZ = z;
        camReady = true;
    }
    // one step of 10 % in (dir 1) or out (-1) around p, eased toward (steps add up while it moves)
    function zoomStep(p, dir) {
        const base = ms.camT ? ms.camT : { x: camX, y: camY, z: camZ };
        const s = Theme.scale;
        const z1 = B.clamp(Math.round((base.z / s + dir * 0.1) * 10) / 10 * s, zoomMin, zoomMax);
        if (Math.abs(z1 - base.z) < 1e-6) return;
        const wx = (p.x - base.x) / base.z, wy = (p.y - base.y) / base.z;
        ms.camT = { x: p.x - wx * z1, y: p.y - wy * z1, z: z1 };
    }

    // ---------- full screen ----------
    // The world's size. Growing, the bubbles keep their places round the
    // middle; shrinking, their places scale down with it (none is cut off at a
    // wall), and a few quick steps part the ones that came too close.
    function resizeWorld(w, h) {
        const w0 = world.w, h0 = world.h, grow = w >= w0;
        for (const n of world.nodes) {
            if (grow) { n.x += (w - w0) / 2; n.y += (h - h0) / 2; }
            else { n.x *= w / w0; n.y *= h / h0; }
        }
        worldW = w; worldH = h;
        world.w = w; world.h = h;
        ms.camT = null; ms.camBack = null; ms.press = null; ms.pan = null; world.dragTarget = null;
        if (!grow) for (let i = 0; i < 8; i++) world.step(0.016, Date.now());
    }
    // Full screen begins: processes and apps both show from now on.
    function goFull() {
        camHome = { x: camX, y: camY, z: camZ };
        full = true;
    }
    // The page has a whole screen of w × h: the world grows to fill it at 50 %.
    function spread(w, h) {
        const z = 0.5 * Theme.scale;
        resizeWorld(w / z, h / z);
        camX = 0; camY = 0; camZ = z;
    }
    // The page is the popup's size again: the world's own size, the camera where it was.
    function gather() {
        resizeWorld(worldSize.w, worldSize.h);
        camX = camHome.x; camY = camHome.y; camZ = camHome.z;
    }
    // Full screen is over, wherever it had got to.
    function quitFull() {
        if (!full) return;
        if (worldW !== worldSize.w || worldH !== worldSize.h) gather();
        full = false;
    }

    // ---------- holding and opening ----------
    function grab() {
        const p = ms.press; if (!p) return;
        const n = world.find(p.id); p.drag = true;
        if (n) { n.grab = true; n.w = Math.min(0.22, n.w + 0.12); world.dragTarget = { x: p.wx, y: p.wy }; }
    }
    function release() {
        for (const n of world.nodes) if (n.grab) { n.grab = false; n.vx = B.clamp(n.vx, -1400, 1400); n.vy = B.clamp(n.vy, -1400, 1400); }
        ms.press = null; world.dragTarget = null;
    }
    function kindOf(n) { return n.type === "metric" ? n.key : n.type === "group" ? "group" : "app"; }
    function openNode(n) {
        release();
        ms.open = { id: n.id, node: n, prog: 0, dir: 1, x: 0, y: 0, r: 30, kind: kindOf(n) };
    }
    function closeOverlay() { if (ms.open) ms.open.dir = -1; }
    function closeNow() { ms.open = null; ov = null; }
    // another bubble's page in place of the open one's (a process in a list is a bubble)
    function openId(id) {
        const n = world.find(id);
        if (!n || n.dying) return;
        if (ms.open && ms.open.dir > 0) {
            if (ms.open.id !== id) Object.assign(ms.open, { id: n.id, node: n, kind: kindOf(n) });
            return;
        }
        ms.open = null;
        openNode(n);
    }

    // ---------- the knock: four players taken in turn, so knocks close together can overlap ----------
    property int nextBump: 0
    readonly property list<SoundEffect> bumps: [
        SoundEffect { source: Qt.resolvedUrl("bloop.wav") },
        SoundEffect { source: Qt.resolvedUrl("bloop.wav") },
        SoundEffect { source: Qt.resolvedUrl("bloop.wav") },
        SoundEffect { source: Qt.resolvedUrl("bloop.wav") }
    ]
    function knock(volume) {
        const fx = bumps[nextBump];
        nextBump = (nextBump + 1) % bumps.length;
        fx.volume = volume;
        fx.play();
    }

    // ---------- frame loop ----------
    FrameAnimation {
        running: root.active
        onTriggered: root.frame(Math.min(0.033, frameTime))
    }
    function frame(dt) {
        const st = ms, now = Date.now(), k = B.smoothK(dt, smoothTau);
        for (const c of st.cores) c.v += (c.t - c.v) * k;
        for (const o of [st.temp, st.apps, st.cache, st.netU, st.netD, st.dR, st.dW]) o.v += (o.t - o.v) * k;
        for (const n of world.nodes) if (n.type === "proc" || n.type === "group") n.cpu += ((n.paused ? 0 : n.cpuT) - n.cpu) * k;
        st.maxDR += (Math.max(5, ...st.dRh) - st.maxDR) * k;
        st.maxDW += (Math.max(5, ...st.dWh) - st.maxDW) * k;
        st.maxU += (Math.max(10, ...st.up) - st.maxU) * k;
        st.maxD += (Math.max(40, ...st.down) - st.maxD) * k;
        if (st.press && !st.press.drag && now - st.press.t0 > 220) grab();
        // An open bubble: the camera comes close (100 %) and keeps it in the
        // middle of what its page leaves; closing, it goes back to where it was.
        if (st.open) {
            if (!st.camBack) st.camBack = { x: camX, y: camY, z: camZ };
            const n = world.find(st.open.id);
            if (n && st.open.dir > 0) {
                const z = zoomMax, cx = cardW + (viewW - cardW) / 2;
                st.camT = { x: cx - n.x * z, y: viewH / 2 - n.y * z, z: z };
            } else if (st.camBack) { st.camT = st.camBack; }
        } else if (st.camBack) { st.camT = st.camBack; st.camBack = null; }
        if (st.camT) {
            const kc = B.smoothK(dt, 0.12), t = st.camT;
            camX += (t.x - camX) * kc; camY += (t.y - camY) * kc; camZ += (t.z - camZ) * kc;
            if (Math.abs(t.z - camZ) < 0.001 && Math.abs(t.x - camX) < 0.3 && !st.open) st.camT = null;
        }
        if (st.open) {
            st.open.prog = B.clamp(st.open.prog + st.open.dir * dt / 0.5, 0, 1);
            if (st.open.dir < 0 && st.open.prog === 0) st.open = null;
        }
        for (const n of world.nodes) if (n.type === "proc" || n.type === "group") n.rT = procR(n.cpu);
        world.step(dt, now);
        // the hardest bump of this step, if it is a real knock and the last sound has had a moment
        if (world.hits.length && Daemon.setting("sounds", true)) {
            const hit = Math.max(...world.hits);
            if (hit > 5 && now - bumpAt > 60) { bumpAt = now; knock(B.clamp(0.22 + hit / 420, 0.22, 0.85)); }
        }

        // the field's bubbles follow the world (removed ones shrank out already)
        for (let i = bubbles.count - 1; i >= 0; i--) if (!world.find(bubbles.get(i).nid)) bubbles.remove(i);
        for (const n of world.nodes) { const it = bubbleItems[n.id]; if (it) it.sync(n); }

        // the numbers everything shows
        vAvg = st.cores.reduce((a, x) => a + x.v, 0) / st.cores.length;
        vTemp = st.temp.v;
        vMem = st.apps.v + st.cache.v * 0.25;
        vTotal = st.snap ? (st.snap.mem.totalExactGB || st.snap.mem.totalGB) : 8;
        phase = B.clamp((now - st.lastTick) / tickMs, 0, 1);
        sweep = Math.min(1.2, sweep + dt * 1000 / st.period);
        if (st.open) {
            if (st.open.id !== infoId || now - infoAt > 250) {
                info = Object.assign(details(world.find(st.open.id) || st.open.node, now), { id: st.open.id });
                infoId = st.open.id; infoAt = now;
            }
        } else if (info) { info = null; infoId = ""; }
        ov = st.open ? overlay() : null;
        clock = now / 1000;
        tick++;
    }

    // the open page: where its colour spreads from, how far it is open, and all it shows
    function overlay() {
        const o = ms.open, n = world.find(o.id) || o.node;
        if (world.nodes.indexOf(n) >= 0) { o.x = camX + n.x * camZ; o.y = camY + n.y * camZ; o.r = n.ef * camZ; }
        return Object.assign({}, info, {
            id: o.id, x: o.x, y: o.y, r: o.r, R: B.lerp(o.r, Math.hypot(viewW, viewH) * 1.05, B.easeIO(o.prog)),
            co: B.clamp((o.prog - 0.5) / 0.35, 0, 1), opening: o.dir > 0, prog: o.prog, e: B.easeIO(o.prog)
        });
    }

    // Everything a bubble's page shows, the same order for each: title and a
    // line under it, the number, how it looks (a chart, bars or a gauge), facts
    // in two columns and lists (`panel`: how many rows fit the popup's page;
    // full screen shows them all).
    function details(n, now) {
        const st = ms, kind = kindOf(n);
        const phase = B.clamp((now - st.lastTick) / tickMs, 0, 1);
        const snap = st.snap || { cpu: { threads: st.cores.length, model: "", freqGHz: 0, load: [0, 0, 0], procCount: 0 },
                                  mem: { swapGB: 0, swapTotalGB: 0, freeGB: 0 }, net: { iface: "", sentGB: 0, recvGB: 0 }, sensors: [] };
        const sensors = snap.sensors || [];
        const coreTemps = sensors.filter(x => x.label.startsWith("Core") || x.label.startsWith("Tccd"));
        const hottest = coreTemps.length ? Math.max(...coreTemps.map(x => x.c)) : vTemp;
        const liveProcs = world.nodes.filter(x => x.type === "proc" && !x.dying);
        const disk = snap.disk || { readGB: 0, writtenGB: 0, drives: [] };
        const one = v => v.toFixed(v < 10 ? 1 : 0);
        const mb = v => v.toFixed(v < 10 ? 1 : 0) + " MB/s";
        const known = v => v === undefined || v === null ? "—" : v;
        const color = n.type === "metric" ? Look.metricColor(n.key) : n.type === "group" ? Look.white : Look.kindColor(n.kind);
        const procRow = (p, val, frac) => ({ id: world.find(p.id || ("p" + p.pid)) ? (p.id || "p" + p.pid) : "", name: p.name, val: val, frac: frac });
        const memFree = snap.mem.freeGB !== undefined ? snap.mem.freeGB : Math.max(0, vTotal - st.apps.v - st.cache.v);
        const rank = n.type === "proc" ? liveProcs.slice().sort((a, b) => b.cpuT - a.cpuT).indexOf(n) + 1 : 0;
        const d = {
            kind: kind, color: color, phase: phase, title: n.name || "", sub: "", num: "", unit: "", note: "",
            facts: [], list: null, list2: null,
            peak: Math.max(...st.hist), hist: st.hist, cores: st.cores.map(x => x.v),
            memApps: st.apps.v, memCache: st.cache.v, memFree: memFree,
            topMem: liveProcs.slice().sort((a, b) => b.memMB - a.memMB).slice(0, 10).map(p => ({ id: p.id, name: p.name, memMB: p.memMB })),
            tempPeak: Math.max(...st.tempHist), tempAvg: st.tempHist.reduce((a, b) => a + b, 0) / st.tempHist.length,
            netPeak: Math.max(...st.down)
        };
        if (kind === "cpu") {
            d.sub = snap.cpu.model.replace(/\(R\)|\(TM\)|CPU |@.*$/g, "").replace(/\s+/g, " ").trim() + " · " + snap.cpu.threads + " threads";
            d.num = String(Math.round(vAvg)); d.unit = "%";
            d.facts = [{ lbl: "Clock", val: snap.cpu.freqGHz.toFixed(2) + " GHz" }, { lbl: "Peak (1 min)", val: Math.round(d.peak) + "%" },
                       { lbl: "Processes", val: String(snap.cpu.procCount || 0) },
                       { lbl: "Busy threads", val: st.cores.filter(x => x.v > 50).length + " of " + st.cores.length }];
            d.list = { title: "Top processes", panel: 5, rows: liveProcs.slice().sort((a, b) => b.cpu - a.cpu).slice(0, 8)
                           .map(p => procRow(p, one(p.cpu) + "%", p.cpu / 100)) };
        } else if (kind === "mem") {
            d.sub = vTotal.toFixed(1) + " GB installed"; d.num = vMem.toFixed(1); d.unit = "GB";
            d.facts = [{ lbl: "In use", val: Math.round(vMem / vTotal * 100) + "%" },
                       { lbl: "Swap", val: snap.mem.swapGB.toFixed(1) + " / " + (snap.mem.swapTotalGB || 0).toFixed(1) + " GB" }];
            const top = d.topMem, max = top.length ? Math.max(1, top[0].memMB) : 1;
            d.list = { title: "Top processes", panel: 6, rows: top.map(p => procRow(p, B.fmtMem(p.memMB), p.memMB / max)) };
        } else if (kind === "temp") {
            d.sub = vTemp > 80 ? "Hot" : vTemp > 65 ? "Warm" : "Cool"; d.num = String(Math.round(vTemp)); d.unit = "°C";
            const ssd = sensors.find(x => x.label === "SSD");
            d.facts = [{ lbl: "Peak (1 min)", val: Math.round(d.tempPeak) + "°C" }, { lbl: "Average (1 min)", val: Math.round(d.tempAvg) + "°C" },
                       { lbl: "Hottest core", val: Math.round(hottest) + "°C" }, { lbl: "SSD", val: ssd ? Math.round(ssd.c) + "°C" : "—" }];
            d.list = { title: "Sensors", panel: 6, rows: sensors.map(x => ({ name: x.label, val: Math.round(x.c) + "°C", frac: (x.c - 20) / 80 })) };
        } else if (kind === "net") {
            d.sub = snap.net.iface; d.num = one(st.netD.v); d.unit = "MB/s down";
            d.legend = ["Up", "Down"]; d.io = { up: st.up, down: st.down, maxUp: st.maxU, maxDown: st.maxD };
            d.facts = [{ lbl: "Down", val: mb(st.netD.v) }, { lbl: "Up", val: mb(st.netU.v) },
                       { lbl: "Peak down (1 min)", val: mb(d.netPeak) }, { lbl: "Peak up (1 min)", val: mb(Math.max(...st.up)) },
                       { lbl: "Received in all", val: (snap.net.recvGB || 0).toFixed(2) + " GB" },
                       { lbl: "Sent in all", val: (snap.net.sentGB || 0).toFixed(2) + " GB" }];
        } else if (kind === "disk") {
            const used = disk.drives.reduce((a, x) => a + x.usedGB, 0), total = disk.drives.reduce((a, x) => a + x.totalGB, 0);
            d.sub = Math.round(used) + " of " + Math.round(total) + " GB"; d.num = String(Math.round(vDisk * 100)); d.unit = "% used";
            d.legend = ["Read", "Write"]; d.io = { up: st.dRh, down: st.dWh, maxUp: st.maxDR, maxDown: st.maxDW };
            d.facts = [{ lbl: "Read", val: mb(st.dR.v) }, { lbl: "Write", val: mb(st.dW.v) },
                       { lbl: "Read in all", val: (disk.readGB || 0).toFixed(1) + " GB" },
                       { lbl: "Written in all", val: (disk.writtenGB || 0).toFixed(1) + " GB" }];
            d.list = { title: "Drives", rows: disk.drives.map(x => ({ name: x.mount, val: Math.round(x.usedGB) + " / " + Math.round(x.totalGB) + " GB",
                                                                      frac: x.usedGB / Math.max(1, x.totalGB) })) };
        } else if (kind === "app") {
            d.sub = "PID " + n.pid + " · " + kindLabel[n.kind] + " · " + n.user;
            d.num = n.paused ? "0" : one(n.cpu); d.unit = "% CPU"; d.hist = n.h.slice(-30);
            d.facts = [{ lbl: "Memory", val: B.fmtMem(n.memMB) }, { lbl: "State", val: n.dying ? "Ended" : n.paused ? "Paused" : n.cpu > 5 ? "Running" : "Sleeping" },
                       { lbl: "Rank by CPU", val: rank + " of " + liveProcs.length }, { lbl: "Threads", val: String(known(n.threads)) },
                       { lbl: "Started", val: n.started ? B.fmtAgo(Date.now() / 1000 - n.started) : "—" },
                       { lbl: "CPU time", val: n.cpuSec === undefined || n.cpuSec === null ? "—" : B.fmtSpan(n.cpuSec, true) },
                       { lbl: "Disk read", val: n.readMB === undefined || n.readMB === null ? "—" : B.fmtMem(n.readMB) },
                       { lbl: "Disk written", val: n.writeMB === undefined || n.writeMB === null ? "—" : B.fmtMem(n.writeMB) }];
        } else if (kind === "group") {
            d.sub = n.windows + (n.windows === 1 ? " window" : " windows") + (n.ws && n.ws.length ? " · workspace " + n.ws.join(", ") : "");
            d.num = one(n.cpu); d.unit = "% CPU"; d.hist = (n.h || []).slice(-30);
            d.facts = [{ lbl: "Memory", val: B.fmtMem(n.memMB) }, { lbl: "Processes", val: String(n.procCount) }];
            const procs = n.procs || [], max = Math.max(1, ...procs.map(p => p.memMB));
            d.list2 = { title: "Windows", rows: (n.titles || []).map(t => ({ name: t || "Untitled" })) };
            d.list = { title: "Processes", panel: 4, rows: procs.map(p => procRow(p, B.fmtMem(p.memMB) + " · " + one(p.cpu) + "%", p.memMB / max)) };
        }
        return d;
    }

    Component.onCompleted: seedMetrics()
}
