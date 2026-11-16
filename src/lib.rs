//! The data behind the Bubble monitor (`shell/Popup.qml`): the `bubble` topic,
//! one snapshot of the machine a second, made only while the shell shows it.
//!
//! Ported from `bubble-feed.py` in lukpednoi's Anserin
//! (https://github.com/lukpednoi/Anserin, AGPL-3.0-or-later), which read the
//! same through psutil; here it is read from /proc and /sys directly. Anserin
//! descends from ilyamiro's Serpantinum (https://github.com/ilyamiro/serpantinum).
//!
//! Read-only: nothing here ever signals or changes a process.
//!
//! The snapshot, as the Python printed it:
//! `{ t, host, uptimeSec, cpu: { model, threads, freqGHz, load, cores, procCount },
//!    mem: { totalGB, totalExactGB, appsGB, cacheGB, freeGB, swapGB, swapTotalGB },
//!    tempC, sensors: [{ label, c }], battery: { pct, plugged } | null,
//!    net: { iface, upMBs, downMBs, sentGB, recvGB },
//!    disk: { readMBs, writeMBs, readGB, writtenGB, drives: [{ mount, usedGB, totalGB }] },
//!    procs: [the busiest 16], apps: [one per open window class] }`

mod machine;
mod procs;

use fable_plugin::tokio::time::{sleep, Duration, Instant};
use fable_plugin::*;

pub fn plugin() -> Plugin {
    Plugin::new().run(run)
}

async fn run(ctx: Ctx) -> Result<()> {
    loop {
        while !ctx.wanted() {
            ctx.wanted_change().await;
        }
        let mut machine = machine::Machine::new().await;
        let mut table = procs::Table::new().await;
        // The first rates need something to compare with.
        sleep(Duration::from_millis(500)).await;
        while ctx.wanted() {
            let started = Instant::now();
            let windows = ctx.call("hypr.clients", json!({})).await.unwrap_or(Value::Null);
            let sample = machine.sample().await;
            let (procs, apps, count) = table.sample(&windows);
            let mut snapshot = sample;
            snapshot["cpu"]["procCount"] = json!(count);
            snapshot["procs"] = procs;
            snapshot["apps"] = apps;
            ctx.publish(snapshot);
            fable_plugin::tokio::select! {
                _ = sleep(Duration::from_secs(1).saturating_sub(started.elapsed())) => {}
                _ = ctx.wanted_change() => {}
            }
        }
    }
}
