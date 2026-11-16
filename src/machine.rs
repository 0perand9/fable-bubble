//! Machine-wide numbers: processors, memory, temperatures, battery, network
//! and disks. Rates are worked out between two calls of [`Machine::sample`].
//!
//! A rewrite of the `Sampler` in `bubble-feed.py` from lukpednoi's Anserin
//! (https://github.com/lukpednoi/Anserin, AGPL-3.0), which used psutil.

use fable_plugin::*;
use std::fs::read_to_string;
use std::path::Path;
use std::time::Instant;

const GB: f64 = 1024.0 * 1024.0 * 1024.0;
/// Temperature chips whose first reading is the processor's, best first.
const CPU_CHIPS: [&str; 5] = ["k10temp", "coretemp", "zenpower", "cpu_thermal", "acpitz"];
/// How often the drives' usage is asked again (it hardly moves, and asking runs `df`).
const DRIVES_EVERY: u32 = 10;

pub struct Machine {
    model: String,
    cores: Vec<(u64, u64)>,
    net: (u64, u64),
    disk: (u64, u64),
    at: Instant,
    drives: Value,
    tick: u32,
}

impl Machine {
    pub async fn new() -> Self {
        let model = read("/proc/cpuinfo").lines().find(|l| l.starts_with("model name")).and_then(|l| l.split_once(':')).map(|(_, m)| m.trim().to_string());
        Machine { model: model.unwrap_or_else(|| "CPU".into()), cores: core_times(), net: net_bytes().1, disk: disk_bytes(), at: Instant::now(), drives: drives().await, tick: 0 }
    }

    pub async fn sample(&mut self) -> Value {
        let now = Instant::now();
        let dt = now.duration_since(self.at).as_secs_f64().max(0.001);
        let (cores, net, disk) = (core_times(), net_bytes(), disk_bytes());
        let busy: Vec<f64> = cores
            .iter()
            .zip(self.cores.iter().chain(std::iter::repeat(&(0, 0))))
            .map(|(&(b1, t1), &(b0, t0))| (b1.saturating_sub(b0) as f64 / t1.saturating_sub(t0).max(1) as f64 * 100.0).clamp(0.0, 100.0))
            .collect();
        let rate = |a: u64, b: u64| a.saturating_sub(b) as f64 / dt / 1e6;
        let (iface, (rx, tx)) = net;
        let (up, down) = (rate(tx, self.net.1), rate(rx, self.net.0));
        let (read_mbs, write_mbs) = (rate(disk.0, self.disk.0), rate(disk.1, self.disk.1));
        (self.cores, self.net, self.disk, self.at) = (cores, (rx, tx), disk, now);
        self.tick += 1;
        if self.tick.is_multiple_of(DRIVES_EVERY) {
            self.drives = drives().await;
        }
        let sensors = sensors();
        let temp = cpu_temp(&sensors).unwrap_or(30.0 + busy.iter().sum::<f64>() / busy.len().max(1) as f64 * 0.5);
        json!({
            "t": util::now_ms(),
            "host": read("/proc/sys/kernel/hostname").trim(),
            "uptimeSec": read("/proc/uptime").split_whitespace().next().and_then(|u| u.parse::<f64>().ok()).unwrap_or(0.0) as u64,
            "cpu": { "model": self.model, "threads": busy.len(), "freqGHz": freq_ghz(), "load": load(), "cores": busy },
            "mem": memory(),
            "tempC": temp,
            "sensors": sensors.iter().map(|(_, label, c)| json!({ "label": label, "c": c })).collect::<Vec<_>>(),
            "battery": battery(),
            "net": { "iface": iface, "upMBs": up, "downMBs": down, "sentGB": tx as f64 / GB, "recvGB": rx as f64 / GB },
            "disk": { "readMBs": read_mbs, "writeMBs": write_mbs, "readGB": disk.0 as f64 / GB, "writtenGB": disk.1 as f64 / GB, "drives": self.drives },
        })
    }
}

fn read(path: impl AsRef<Path>) -> String {
    read_to_string(path).unwrap_or_default()
}

/// (busy, total) jiffies of every processor, in order.
fn core_times() -> Vec<(u64, u64)> {
    read("/proc/stat")
        .lines()
        .filter(|l| l.starts_with("cpu") && l.as_bytes().get(3).is_some_and(u8::is_ascii_digit))
        .map(|l| {
            let f: Vec<u64> = l.split_whitespace().skip(1).filter_map(|v| v.parse().ok()).collect();
            let total: u64 = f.iter().take(8).sum();
            let idle = f.get(3).unwrap_or(&0) + f.get(4).unwrap_or(&0);
            (total.saturating_sub(idle), total)
        })
        .collect()
}

/// The average current clock of all processors.
fn freq_ghz() -> f64 {
    let khz: Vec<f64> = std::fs::read_dir("/sys/devices/system/cpu")
        .into_iter()
        .flatten()
        .flatten()
        .filter_map(|e| read(e.path().join("cpufreq/scaling_cur_freq")).trim().parse().ok())
        .collect();
    if khz.is_empty() { 0.0 } else { khz.iter().sum::<f64>() / khz.len() as f64 / 1e6 }
}

fn load() -> Vec<f64> {
    read("/proc/loadavg").split_whitespace().take(3).filter_map(|v| v.parse().ok()).collect()
}

/// Apps (what programs hold), Free (nothing in it) and Cache (the rest: files
/// kept in memory, given back when needed) add up to the whole.
fn memory() -> Value {
    let info = read("/proc/meminfo");
    let kb = |key: &str| info.lines().find(|l| l.starts_with(key)).and_then(|l| l.split_whitespace().nth(1)).and_then(|v| v.parse::<f64>().ok()).unwrap_or(0.0) * 1024.0 / GB;
    let (total, available, free) = (kb("MemTotal:"), kb("MemAvailable:"), kb("MemFree:"));
    let apps = total - available;
    json!({
        "totalGB": total.round(), "totalExactGB": total, "appsGB": apps, "freeGB": free, "cacheGB": (total - apps - free).max(0.0),
        "swapGB": kb("SwapTotal:") - kb("SwapFree:"), "swapTotalGB": kb("SwapTotal:"),
    })
}

/// Every temperature the machine reports, as (chip, label for people, °C).
fn sensors() -> Vec<(String, String, f64)> {
    let mut out = Vec::new();
    let mut hwmons: Vec<_> = std::fs::read_dir("/sys/class/hwmon").into_iter().flatten().flatten().map(|e| e.path()).collect();
    hwmons.sort();
    for dir in hwmons {
        let chip = read(dir.join("name")).trim().to_string();
        let mut inputs: Vec<_> = std::fs::read_dir(&dir).into_iter().flatten().flatten().map(|e| e.file_name().to_string_lossy().into_owned()).filter(|n| n.starts_with("temp") && n.ends_with("_input")).collect();
        inputs.sort();
        for input in inputs {
            let Ok(milli) = read(dir.join(&input)).trim().parse::<f64>() else { continue };
            if milli == 0.0 {
                continue;
            }
            let raw = read(dir.join(input.replace("_input", "_label"))).trim().to_string();
            let label = match chip.as_str() {
                "coretemp" | "k10temp" if raw.starts_with("Package") || raw == "Tctl" || raw == "Tdie" => "Package".to_string(),
                "coretemp" | "k10temp" => raw,
                "nvme" if raw.is_empty() || raw == "Composite" => "SSD".into(),
                "nvme" => format!("SSD {raw}"),
                "acpitz" => "Board".into(),
                "iwlwifi_1" => "Wi-Fi".into(),
                _ => format!("{chip} {raw}").trim().to_string(),
            };
            out.push((chip.clone(), if label.is_empty() { chip.clone() } else { label }, milli / 1000.0));
        }
    }
    out
}

fn cpu_temp(sensors: &[(String, String, f64)]) -> Option<f64> {
    CPU_CHIPS.iter().find_map(|chip| sensors.iter().find(|(c, _, _)| c == chip)).or(sensors.first()).map(|(_, _, c)| *c)
}

/// The machine's own battery (not a mouse's or a headset's), if it has one.
fn battery() -> Value {
    let supplies: Vec<_> = std::fs::read_dir("/sys/class/power_supply").into_iter().flatten().flatten().map(|e| e.path()).collect();
    let own = supplies.iter().find(|p| read(p.join("type")).trim() == "Battery" && read(p.join("scope")).trim() != "Device");
    let Some(bat) = own else { return Value::Null };
    let Ok(pct) = read(bat.join("capacity")).trim().parse::<f64>() else { return Value::Null };
    let plugged = supplies.iter().any(|p| read(p.join("type")).trim() == "Mains" && read(p.join("online")).trim() == "1") || read(bat.join("status")).trim() != "Discharging";
    json!({ "pct": pct.min(100.0), "plugged": plugged })
}

/// The busiest interface's name, and (received, sent) bytes over all but loopback.
fn net_bytes() -> (String, (u64, u64)) {
    let (mut best, mut most, mut rx, mut tx) = ("net".to_string(), 0, 0, 0);
    for line in read("/proc/net/dev").lines().skip(2) {
        let Some((name, rest)) = line.split_once(':') else { continue };
        let name = name.trim();
        if name == "lo" {
            continue;
        }
        let f: Vec<u64> = rest.split_whitespace().filter_map(|v| v.parse().ok()).collect();
        let (r, t) = (f.first().copied().unwrap_or(0), f.get(8).copied().unwrap_or(0));
        (rx, tx) = (rx + r, tx + t);
        if r + t >= most {
            (best, most) = (name.to_string(), r + t);
        }
    }
    (best, (rx, tx))
}

/// (read, written) bytes over the real disks (loop, RAM and mapper devices
/// would count the same bytes twice, or none that touch a disk).
fn disk_bytes() -> (u64, u64) {
    let disks: Vec<String> = std::fs::read_dir("/sys/block").into_iter().flatten().flatten().map(|e| e.file_name().to_string_lossy().into_owned()).filter(|n| !["loop", "ram", "zram", "dm-"].iter().any(|p| n.starts_with(p))).collect();
    read("/proc/diskstats").lines().fold((0, 0), |(r, w), line| {
        let f: Vec<&str> = line.split_whitespace().collect();
        if f.len() < 10 || !disks.iter().any(|d| d == f[2]) {
            return (r, w);
        }
        let sectors = |i: usize| f[i].parse::<u64>().unwrap_or(0) * 512;
        (r + sectors(5), w + sectors(9))
    })
}

/// The mounted drives, each device once: `[{ mount, usedGB, totalGB }]`.
async fn drives() -> Value {
    let out = tokio::process::Command::new("df")
        .args(["-B1", "--output=source,target,used,size", "-x", "tmpfs", "-x", "devtmpfs", "-x", "squashfs", "-x", "efivarfs", "-x", "overlay", "-x", "ramfs"])
        .output()
        .await;
    let text = out.map(|o| String::from_utf8_lossy(&o.stdout).into_owned()).unwrap_or_default();
    let mut seen = Vec::new();
    let mut drives = Vec::new();
    for line in text.lines().skip(1) {
        let f: Vec<&str> = line.split_whitespace().collect();
        let [source, mount, used, size] = f[..] else { continue };
        if !source.starts_with("/dev/") || seen.contains(&source) || mount.starts_with("/boot") || mount.starts_with("/nix/store") {
            continue;
        }
        seen.push(source);
        let gb = |v: &str| v.parse::<f64>().unwrap_or(0.0) / GB;
        drives.push(json!({ "mount": mount, "usedGB": gb(used), "totalGB": gb(size) }));
    }
    Value::Array(drives)
}
