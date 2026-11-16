# bubble

A plugin for [Fableland](https://github.com/0perand9/fableland), compiled into
its daemon and shell. Fableland's docs/PLUGINS.md explains plugins.

This machine as bubbles drifting in space: dials for CPU, memory,
temperature, network and disk, and the busiest processes or the open apps (each
app's windows and everything they started). They drift, knock with a soft
sound, flatten when packed and throw lightning at each other; a black hole
turns behind them. Tap a bubble for its page (history, threads as glasses of
water, facts, top processes, sensors, drives), hold one to carry it, drag the
space to move, scroll to zoom. `fable toggle bubble` opens it.

The button top right takes it full screen: the page is sucked like a cloth into
that button and ink spreads from it over the screen, where the bubbles have all
the room and processes and apps show together. The button again, or Escape,
brings it back.

## Credit

The Bubble monitor is **lukpednoi's**, from
[lukpednoi/Anserin](https://github.com/lukpednoi/Anserin) (commit
`1909479761d45b70757498945bb7badaf0c4be08`): the System page's Bubble style,
`src/quickshell/blankpanel/pages/BubbleMonitor.qml`, `bubble/BubbleLogic.js`,
`bubble/bubble-feed.py`, the shaders in `bubble/shaders/`, the images in
`bubble/space/`, `bubble/bloop.wav` and
`src/assets/shaders/fluid/level_wave.frag`. Anserin is a fork of
[ilyamiro's Serpantinum](https://github.com/ilyamiro/serpantinum).

Anserin is AGPL-3.0-or-later, and so is this plugin: see [LICENSE](LICENSE).

### What was changed (2026-11-16)

Everything it did, it does here. What differs is where it lives:

- **Data**: `bubble-feed.py` (Python and psutil) is replaced by the plugin's
  daemon side in Rust (`src/`), reading /proc and /sys. It publishes the same
  snapshot as the on-demand topic `bubble`, sampled once a second only while
  the popup is open. Process names undo Nix's `.name-wrapped` wrappers; the
  extra NVMe sensors are labelled `SSD Sensor 1`, …; "hottest core" also reads
  AMD's `Tccd` sensors.
- **Shape**: the page of Anserin's side panel became a Fableland popup, and
  full screen takes it out of that popup instead. Its script moved into a
  singleton (`shell/Monitor.qml`), so the bubbles keep their places between
  openings; the one 1500-line file is split into `Popup.qml`, `Page.qml`,
  `Field.qml`, `Bubble.qml`, `InfoPanel.qml`, `FullScreen.qml`, `FlowText.qml`,
  `Water.qml` and `Look.qml`.
- **Look**: colours and fonts come from Fableland's theme (`shell/Look.qml`);
  sizes follow its UI scale. The popup is roomier than the side panel was, so
  an open bubble's page takes 40 % of it (not 60 %) and shows the facts, and
  more of the rows, that the panel kept for full screen; the CPU page lays
  threads out 16 to a row, so a big processor fits.
- **Full screen**: the cloth has the popup's rounded corners (`cloth.frag`),
  so it takes over from the popup unseen.
- **Sound**: the knock follows Fableland's `sounds` setting.
- `BubbleLogic.js` (the physics, lightning and charts) and the water, cloth
  and ink shaders are otherwise unchanged but for a note at the top.

## Installing

With Fableland's Home Manager module:

```nix
# flake.nix
inputs.fable-bubble = { url = "github:0perand9/fable-bubble"; flake = false; };

# home configuration
programs.fableland.plugins = [ inputs.fable-bubble ];
```

From 1.1.0 it needs a Fableland that compiles plugins' vertex shaders (the
cloth is one): any from 2026-11-16 on.

To work on it, clone it into a Fableland checkout as `plugins/bubble` and run
`plugins/assemble`; then `dev/daemon build && dev/daemon restart` and `dev/window`.

## The topic

`bubble`, on demand (a `Want`), is the snapshot `bubble-feed.py` printed:
`{ t, host, uptimeSec, cpu: { model, threads, freqGHz, load, cores, procCount },
mem: { totalGB, totalExactGB, appsGB, cacheGB, freeGB, swapGB, swapTotalGB },
tempC, sensors: [{ label, c }], battery: { pct, plugged } | null,
net: { iface, upMBs, downMBs, sentGB, recvGB },
disk: { readMBs, writeMBs, readGB, writtenGB, drives: [{ mount, usedGB, totalGB }] },
procs: [{ pid, name, cmd, user, cpu, memMB, state, threads, started, cpuSec, readMB, writeMB }],
apps: [{ cls, name, windows, ws, titles, cpu, memMB, procCount, procs }] }`.
It is read-only: nothing here signals a process.
