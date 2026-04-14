use portable_pty::{native_pty_system, CommandBuilder, PtySize};
use rust_embed::Embed;
use std::collections::HashMap;
use std::fs;
use std::io::{Read, Write};
use std::path::PathBuf;
use std::sync::{Arc, atomic::{AtomicBool, Ordering}};
use tokio::sync::{Mutex, RwLock};
use warp::ws::{Message, WebSocket};
use warp::Filter;
use futures_util::{SinkExt, StreamExt};

const SCROLLBACK_LIMIT: usize = 50_000;

// Embed the public/ directory into the binary at compile time
#[derive(Embed)]
#[folder = "../public/"]
struct PublicAssets;

// ── PTY Session ─────────────────────────────────────────────────────

struct PtySession {
    writer: Box<dyn Write + Send>,
    master: Box<dyn portable_pty::MasterPty + Send>,
    scrollback: String,
    alive: Arc<AtomicBool>,
    clients: Vec<tokio::sync::mpsc::UnboundedSender<Message>>,
}

type Sessions = Arc<RwLock<HashMap<String, Arc<Mutex<PtySession>>>>>;

fn make_pty_env() -> Vec<(String, String)> {
    let mut env: Vec<(String, String)> = Vec::new();
    for (key, val) in std::env::vars() {
        // Strip terminal integration vars
        if key.starts_with("ITERM_") || key.starts_with("KITTY_") ||
           key.starts_with("KONSOLE_") || key.starts_with("WEZTERM_") ||
           key.starts_with("WT_") || key.starts_with("ALACRITTY_") ||
           key.starts_with("TERM_") || key.starts_with("LC_TERMINAL") ||
           key == "__CFBundleIdentifier" || key == "SECURITYSESSIONID" ||
           key == "TERMINFO_DIRS" || key == "VTE_VERSION" || key == "WINDOWID" {
            continue;
        }
        env.push((key, val));
    }
    env.push(("TERM".into(), "xterm-256color".into()));
    env.push(("COLORTERM".into(), "truecolor".into()));
    env.push(("TERM_PROGRAM".into(), "floaterm".into()));
    env
}

fn get_or_create_session(
    sessions: &mut HashMap<String, Arc<Mutex<PtySession>>>,
    id: &str,
    cols: u16,
    rows: u16,
    command: Option<&str>,
) -> Arc<Mutex<PtySession>> {
    // Check existing — use try_lock to avoid blocking in async context
    if let Some(session) = sessions.get(id) {
        if let Ok(mut s) = session.try_lock() {
            if s.alive.load(Ordering::Relaxed) {
                let _ = s.master.resize(PtySize { rows, cols, pixel_width: 0, pixel_height: 0 });
                return session.clone();
            }
        }
        sessions.remove(id);
    }

    let pty_system = native_pty_system();
    let pair = pty_system
        .openpty(PtySize { rows, cols, pixel_width: 0, pixel_height: 0 })
        .expect("Failed to open PTY");

    let shell = std::env::var("SHELL").unwrap_or_else(|_| "/bin/zsh".into());
    let mut cmd = if let Some(c) = command {
        let mut cb = CommandBuilder::new(&shell);
        cb.args(["-l", "-c", c]);
        cb
    } else {
        let mut cb = CommandBuilder::new(&shell);
        cb.arg("-l");
        cb
    };

    // Set environment
    for (key, val) in make_pty_env() {
        cmd.env(key, val);
    }
    if let Some(home) = dirs::home_dir() {
        cmd.cwd(home);
    }

    let _child = pair.slave.spawn_command(cmd).expect("Failed to spawn shell");
    drop(pair.slave); // close slave side in parent

    let writer = pair.master.take_writer().expect("Failed to take PTY writer");

    let alive = Arc::new(AtomicBool::new(true));
    let session = Arc::new(Mutex::new(PtySession {
        writer,
        master: pair.master,
        scrollback: String::new(),
        alive: alive.clone(),
        clients: Vec::new(),
    }));

    sessions.insert(id.to_string(), session.clone());
    session
}

// ── State persistence ───────────────────────────────────────────────

fn state_dir() -> PathBuf {
    dirs::home_dir().unwrap_or_default().join(".floaterm")
}

fn state_file() -> PathBuf {
    state_dir().join("state.json")
}

fn load_state() -> serde_json::Value {
    fs::read_to_string(state_file())
        .ok()
        .and_then(|s| serde_json::from_str(&s).ok())
        .unwrap_or(serde_json::json!({}))
}

fn save_state(state: &serde_json::Value) {
    let _ = fs::create_dir_all(state_dir());
    let _ = fs::write(state_file(), serde_json::to_string_pretty(state).unwrap_or_default());
}

// ── SSH config parser ───────────────────────────────────────────────

fn ssh_hosts() -> Vec<String> {
    let config_path = dirs::home_dir().unwrap_or_default().join(".ssh/config");
    let content = fs::read_to_string(config_path).unwrap_or_default();
    content
        .lines()
        .filter_map(|line| {
            let trimmed = line.trim();
            if trimmed.to_lowercase().starts_with("host ") {
                let name = trimmed[5..].trim().to_string();
                if !name.contains('*') && !name.contains('?') && !name.is_empty() {
                    return Some(name);
                }
            }
            None
        })
        .collect()
}

// ── WebSocket handler ───────────────────────────────────────────────

async fn handle_ws(
    ws: WebSocket,
    id: String,
    cols: u16,
    rows: u16,
    command: Option<String>,
    sessions: Sessions,
) {
    let session = {
        let mut sess = sessions.write().await;
        get_or_create_session(&mut sess, &id, cols, rows, command.as_deref())
    };

    let (mut ws_tx, mut ws_rx) = ws.split();

    // Create channel for sending PTY output to this client
    let (tx, mut rx) = tokio::sync::mpsc::unbounded_channel::<Message>();

    // Register client
    {
        let mut s = session.lock().await;
        // Send scrollback
        if !s.scrollback.is_empty() {
            let _ = tx.send(Message::text(s.scrollback.clone()));
        }
        s.clients.push(tx.clone());
    }

    // Task: forward channel messages to WebSocket
    let send_task = tokio::spawn(async move {
        while let Some(msg) = rx.recv().await {
            if ws_tx.send(msg).await.is_err() {
                break;
            }
        }
    });

    // Task: read PTY output and broadcast to all clients
    let session_for_reader = session.clone();
    let sessions_for_reader = sessions.clone();
    let id_for_reader = id.clone();
    tokio::spawn(async move {
        let mut reader = {
            let s = session_for_reader.lock().await;
            match s.master.try_clone_reader() {
                Ok(r) => r,
                Err(_) => return,
            }
        };

        let mut buf = [0u8; 8192];
        loop {
            match reader.read(&mut buf) {
                Ok(0) | Err(_) => {
                    let mut s = session_for_reader.lock().await;
                    s.alive.store(false, Ordering::Relaxed);
                    for client in &s.clients {
                        let _ = client.send(Message::text("\r\n\x1b[90m[session ended]\x1b[0m\r\n"));
                    }
                    s.clients.clear();
                    break;
                }
                Ok(n) => {
                    let data = String::from_utf8_lossy(&buf[..n]).to_string();
                    let mut s = session_for_reader.lock().await;
                    s.scrollback.push_str(&data);
                    if s.scrollback.len() > SCROLLBACK_LIMIT {
                        let excess = s.scrollback.len() - SCROLLBACK_LIMIT;
                        s.scrollback = s.scrollback[excess..].to_string();
                    }
                    s.clients.retain(|client| {
                        client.send(Message::text(data.clone())).is_ok()
                    });
                }
            }
        }
    });

    // Receive from WebSocket (user input + resize)
    while let Some(Ok(msg)) = ws_rx.next().await {
        if let Ok(text) = msg.to_str() {
            if text.as_bytes().first() == Some(&0x01) {
                // Resize control message
                if let Ok(size) = serde_json::from_str::<serde_json::Value>(&text[1..]) {
                    let cols = size["cols"].as_u64().unwrap_or(80) as u16;
                    let rows = size["rows"].as_u64().unwrap_or(24) as u16;
                    let s = session.lock().await;
                    let _ = s.master.resize(PtySize { rows, cols, pixel_width: 0, pixel_height: 0 });
                }
            } else {
                // Regular input
                let mut s = session.lock().await;
                let _ = s.writer.write_all(text.as_bytes());
            }
        } else if msg.is_binary() {
            let data = msg.as_bytes();
            if data.first() == Some(&0x01) {
                if let Ok(size) = serde_json::from_str::<serde_json::Value>(&String::from_utf8_lossy(&data[1..])) {
                    let cols = size["cols"].as_u64().unwrap_or(80) as u16;
                    let rows = size["rows"].as_u64().unwrap_or(24) as u16;
                    let s = session.lock().await;
                    let _ = s.master.resize(PtySize { rows, cols, pixel_width: 0, pixel_height: 0 });
                }
            } else {
                let mut s = session.lock().await;
                let _ = s.writer.write_all(data);
            }
        }
    }

    // Client disconnected — remove from clients list but keep session alive
    {
        let mut s = session.lock().await;
        s.clients.retain(|c| !c.is_closed());
    }

    send_task.abort();
}

// ── Start the server ────────────────────────────────────────────────

pub async fn start_server() {
    let sessions: Sessions = Arc::new(RwLock::new(HashMap::new()));

    // Serve embedded static files (compiled into binary)
    let static_files = warp::path::tail().and_then(|tail: warp::path::Tail| async move {
        let path = tail.as_str();
        let path = if path.is_empty() { "index.html" } else { path };
        match PublicAssets::get(path) {
            Some(content) => {
                let mime = mime_guess::from_path(path).first_or_octet_stream();
                Ok(warp::reply::with_header(
                    warp::reply::with_header(
                        warp::reply::with_status(content.data.to_vec(), warp::http::StatusCode::OK),
                        "Content-Type", mime.as_ref(),
                    ),
                    "Cache-Control", "no-cache, no-store, must-revalidate",
                ))
            }
            None => Err(warp::reject::not_found()),
        }
    });
    let index = warp::path::end().and_then(|| async {
        match PublicAssets::get("index.html") {
            Some(content) => Ok(warp::reply::with_header(
                warp::reply::with_header(
                    warp::reply::with_status(content.data.to_vec(), warp::http::StatusCode::OK),
                    "Content-Type", "text/html",
                ),
                "Cache-Control", "no-cache, no-store, must-revalidate",
            )),
            None => Err(warp::reject::not_found()),
        }
    });

    // REST API: state
    let sessions_state = sessions.clone();
    let get_state = warp::path!("api" / "state")
        .and(warp::get())
        .map(|| {
            let state = load_state();
            warp::reply::json(&state)
        });

    let post_state = warp::path!("api" / "state")
        .and(warp::post())
        .and(warp::body::json())
        .map(|body: serde_json::Value| {
            save_state(&body);
            warp::reply::with_status("ok", warp::http::StatusCode::OK)
        });

    // REST API: sessions list
    let sessions_list = sessions.clone();
    let get_sessions = warp::path!("api" / "sessions")
        .and(warp::get())
        .and_then(move || {
            let sessions = sessions_list.clone();
            async move {
                let sess = sessions.read().await;
                let alive: Vec<String> = sess
                    .iter()
                    .filter(|(_, s)| {
                        s.try_lock().map(|s| s.alive.load(Ordering::Relaxed)).unwrap_or(false)
                    })
                    .map(|(id, _)| id.clone())
                    .collect();
                Ok::<_, warp::Rejection>(warp::reply::json(&alive))
            }
        });

    // REST API: delete session
    let sessions_del = sessions.clone();
    let delete_session = warp::path!("api" / "session" / String)
        .and(warp::delete())
        .and_then(move |id: String| {
            let sessions = sessions_del.clone();
            async move {
                let mut sess = sessions.write().await;
                if let Some(s) = sess.remove(&id) {
                    let mut s = s.lock().await;
                    s.alive.store(false, Ordering::Relaxed);
                    s.clients.clear();
                }
                Ok::<_, warp::Rejection>(warp::reply::with_status("ok", warp::http::StatusCode::OK))
            }
        });

    // REST API: SSH hosts
    let get_ssh_hosts = warp::path!("api" / "ssh-hosts")
        .and(warp::get())
        .map(|| warp::reply::json(&ssh_hosts()));

    // WebSocket: terminal
    let sessions_ws = sessions.clone();
    let ws_route = warp::path!("ws" / "terminal" / String)
        .and(warp::ws())
        .and(warp::query::<HashMap<String, String>>())
        .map(move |id: String, ws: warp::ws::Ws, params: HashMap<String, String>| {
            let sessions = sessions_ws.clone();
            let cols: u16 = params.get("cols").and_then(|c| c.parse().ok()).unwrap_or(80);
            let rows: u16 = params.get("rows").and_then(|r| r.parse().ok()).unwrap_or(24);
            let command = params.get("cmd").cloned();
            ws.on_upgrade(move |socket| handle_ws(socket, id, cols, rows, command, sessions))
        });

    let routes = ws_route
        .or(get_state)
        .or(post_state)
        .or(get_sessions)
        .or(delete_session)
        .or(get_ssh_hosts)
        .or(index)
        .or(static_files);

    eprintln!("floaterm running at http://localhost:2323");

    warp::serve(routes).run(([127, 0, 0, 1], 2323)).await;
}
