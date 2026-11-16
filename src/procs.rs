//! The process table: the busiest processes, and the open apps — each window
//! class with every process its windows started.
//!
//! A rewrite of the `Sampler` in `bubble-feed.py` from lukpednoi's Anserin
//! (https://github.com/lukpednoi/Anserin, AGPL-3.0), which used psutil.

use fable_plugin::*;
use std::collections::HashMap;
use std::fs::read_to_string;
use std::time::Instant;

/// How many of the busiest processes are sent, with their details.
const TOP: usize = 16;
const MB: f64 = 1024.0 * 1024.0;

/// An open app as its windows are gathered.
#[derive(Default)]
struct App {
    class: String,
    windows: usize,
    workspaces: Vec<String>,
    titles: Vec<String>,
    pids: Vec<u32>,
}

/// One process as one sample reads it.
struct Row {
    pid: u32,
    ppid: u32,
    name: String,
    uid: u32,
    cpu: f64,
    mem_mb: f64,
    stopped: bool,
    threads: u64,
    started: f64,
    cpu_sec: f64,
}

pub struct Table {
    /// Clock ticks a second, and the boot time: what /proc/<pid>/stat counts in.
    ticks: f64,
    boot: f64,
    /// Each process's CPU ticks at the last sample.
    last: HashMap<u32, u64>,
    at: Instant,
    users: HashMap<u32, String>,
}

impl Table {
    pub async fn new() -> Self {
        let ticks = getconf("CLK_TCK").await.unwrap_or(100.0);
        let uptime: f64 = read("/proc/uptime").split_whitespace().next().and_then(|u| u.parse().ok()).unwrap_or(0.0);
        let mut table = Table { ticks, boot: util::now_s() as f64 - uptime, last: HashMap::new(), at: Instant::now(), users: users() };
        table.read_all();
        table
    }

    /// (the busiest processes, the open apps, how many processes there are).
    pub fn sample(&mut self, windows: &Value) -> (Value, Value, usize) {
        let mut rows = self.read_all();
        let count = rows.len();
        rows.sort_by(|a, b| b.cpu.total_cmp(&a.cpu));
        let apps = self.apps(&rows, windows);
        let top: Vec<Value> = rows.iter().take(TOP).map(|r| self.detail(r)).collect();
        (Value::Array(top), apps, count)
    }

    /// Every process, with its CPU share since the last call (100 = one whole processor).
    fn read_all(&mut self) -> Vec<Row> {
        let now = Instant::now();
        let dt = now.duration_since(self.at).as_secs_f64().max(0.001);
        self.at = now;
        let mut seen = HashMap::new();
        let mut rows = Vec::new();
        for entry in std::fs::read_dir("/proc").into_iter().flatten().flatten() {
            let Some(pid) = entry.file_name().to_str().and_then(|n| n.parse::<u32>().ok()) else { continue };
            let Some((row, ticks)) = self.read_one(pid, dt) else { continue };
            seen.insert(pid, ticks);
            rows.push(row);
        }
        self.last = seen;
        rows
    }

    fn read_one(&self, pid: u32, dt: f64) -> Option<(Row, u64)> {
        let stat = read_to_string(format!("/proc/{pid}/stat")).ok()?;
        // The name is in parentheses and may hold spaces or parentheses itself.
        let (open, close) = (stat.find('(')?, stat.rfind(')')?);
        let name = stat[open + 1..close].to_string();
        let f: Vec<&str> = stat[close + 2..].split_whitespace().collect();
        let num = |i: usize| f.get(i).and_then(|v| v.parse::<u64>().ok()).unwrap_or(0);
        // Fields after the name, counted from `state` (field 3 of proc(5)) as 0.
        let ticks = num(11) + num(12);
        let cpu = match self.last.get(&pid) {
            Some(&before) => (ticks.saturating_sub(before) as f64 / self.ticks / dt * 100.0).min(100.0),
            None => 0.0,
        };
        let status = read(&format!("/proc/{pid}/status"));
        let field = |key: &str| status.lines().find(|l| l.starts_with(key)).and_then(|l| l.split_whitespace().nth(1)).and_then(|v| v.parse::<u64>().ok()).unwrap_or(0);
        let row = Row {
            pid,
            ppid: num(1) as u32,
            name,
            uid: field("Uid:") as u32,
            cpu,
            mem_mb: field("VmRSS:") as f64 / 1024.0,
            stopped: f.first() == Some(&"T"),
            threads: num(17),
            started: self.boot + num(19) as f64 / self.ticks,
            cpu_sec: ticks as f64 / self.ticks,
        };
        Some((row, ticks))
    }

    /// One of the busiest, with the facts its page shows.
    fn detail(&self, r: &Row) -> Value {
        let cmd = read(&format!("/proc/{}/cmdline", r.pid)).replace('\0', " ").trim().to_string();
        let io = read(&format!("/proc/{}/io", r.pid));
        let bytes = |key: &str| io.lines().find(|l| l.starts_with(key)).and_then(|l| l.split_whitespace().nth(1)).and_then(|v| v.parse::<f64>().ok()).map(|b| b / MB);
        json!({
            "pid": r.pid, "name": display_name(r.pid, &r.name), "cmd": if cmd.is_empty() { r.name.clone() } else { cmd },
            "user": self.users.get(&r.uid).cloned().unwrap_or_else(|| r.uid.to_string()),
            "cpu": r.cpu, "memMB": r.mem_mb, "state": if r.stopped { "T" } else if r.cpu > 5.0 { "R" } else { "S" },
            "threads": r.threads, "started": r.started as u64, "cpuSec": r.cpu_sec,
            "readMB": bytes("read_bytes:"), "writeMB": bytes("write_bytes:"),
        })
    }

    /// One entry per open app (window class): its windows' processes and everything they started.
    fn apps(&self, rows: &[Row], windows: &Value) -> Value {
        let by_pid: HashMap<u32, &Row> = rows.iter().map(|r| (r.pid, r)).collect();
        let mut children: HashMap<u32, Vec<u32>> = HashMap::new();
        for r in rows {
            children.entry(r.ppid).or_default().push(r.pid);
        }
        let mut apps: Vec<App> = Vec::new();
        for w in windows.as_array().into_iter().flatten() {
            let pid = w["pid"].as_i64().unwrap_or(-1);
            if pid <= 0 || w["mapped"] == false {
                continue;
            }
            let class = [&w["class"], &w["initialClass"]].iter().filter_map(|v| v.as_str()).find(|c| !c.is_empty()).unwrap_or("?").to_string();
            let at = apps.iter().position(|a| a.class == class).unwrap_or_else(|| {
                apps.push(App { class, ..Default::default() });
                apps.len() - 1
            });
            let app = &mut apps[at];
            app.windows += 1;
            let ws = w["workspace"]["name"].as_str().unwrap_or("").to_string();
            if !ws.is_empty() && !app.workspaces.contains(&ws) {
                app.workspaces.push(ws);
            }
            app.titles.push(w["title"].as_str().unwrap_or("").to_string());
            let mut stack = vec![pid as u32];
            while let Some(p) = stack.pop() {
                if !app.pids.contains(&p) {
                    app.pids.push(p);
                    stack.extend(children.get(&p).into_iter().flatten());
                }
            }
        }
        let mut out: Vec<Value> = apps
            .into_iter()
            .map(|App { class, windows, workspaces, titles, pids }| {
                let mut procs: Vec<&Row> = pids.iter().filter_map(|p| by_pid.get(p).copied()).collect();
                procs.sort_by(|a, b| (b.cpu, b.mem_mb).partial_cmp(&(a.cpu, a.mem_mb)).unwrap_or(std::cmp::Ordering::Equal));
                json!({
                    "cls": class, "name": app_name(&class), "windows": windows, "ws": workspaces, "titles": titles.into_iter().take(4).collect::<Vec<_>>(),
                    "cpu": procs.iter().map(|r| r.cpu).sum::<f64>().min(100.0), "memMB": procs.iter().map(|r| r.mem_mb).sum::<f64>(),
                    "procCount": procs.len(),
                    "procs": procs.iter().take(8).map(|r| json!({ "pid": r.pid, "name": display_name(r.pid, &r.name), "cpu": r.cpu, "memMB": r.mem_mb })).collect::<Vec<_>>(),
                })
            })
            .collect();
        out.sort_by(|a, b| b["cpu"].as_f64().unwrap_or(0.0).total_cmp(&a["cpu"].as_f64().unwrap_or(0.0)));
        Value::Array(out)
    }
}

/// A /proc file as text; a command line need not be valid UTF-8.
fn read(path: &str) -> String {
    std::fs::read(path).map(|bytes| String::from_utf8_lossy(&bytes).into_owned()).unwrap_or_default()
}

/// A process's name as people know it. The kernel cuts names at 15
/// characters, and Nix wraps programs as `.name-wrapped`: the command line's
/// program has the real one.
fn display_name(pid: u32, comm: &str) -> String {
    let wrapped = comm.starts_with('.');
    if comm.len() < 15 && !wrapped {
        return comm.to_string();
    }
    let cmdline = read(&format!("/proc/{pid}/cmdline"));
    let program = cmdline.split('\0').next().unwrap_or("").rsplit('/').next().unwrap_or("");
    let name = if !program.is_empty() && (wrapped || program.starts_with(comm)) { program } else { comm };
    name.strip_prefix('.').and_then(|n| n.strip_suffix("-wrapped")).unwrap_or(name).to_string()
}

/// A window class as people say it: "brave-browser" → "Brave Browser", "org.kde.dolphin" → "Dolphin".
fn app_name(class: &str) -> String {
    let last = class.rsplit('.').next().unwrap_or(class);
    let capital = |w: &str| {
        let mut chars = w.chars();
        chars.next().map(|first| first.to_uppercase().collect::<String>() + chars.as_str()).unwrap_or_default()
    };
    let words: Vec<String> = last.replace('_', "-").split('-').filter(|w| !w.is_empty()).map(capital).collect();
    if words.is_empty() { class.to_string() } else { words.join(" ") }
}

/// User names by id, from /etc/passwd.
fn users() -> HashMap<u32, String> {
    read("/etc/passwd")
        .lines()
        .filter_map(|line| {
            let f: Vec<&str> = line.split(':').collect();
            Some((f.get(2)?.parse().ok()?, f[0].to_string()))
        })
        .collect()
}

async fn getconf(name: &str) -> Option<f64> {
    let out = tokio::process::Command::new("getconf").arg(name).output().await.ok()?;
    String::from_utf8_lossy(&out.stdout).trim().parse().ok()
}
