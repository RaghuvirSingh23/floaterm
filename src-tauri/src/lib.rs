mod server;

pub fn run() {
    // Spawn the HTTP+WebSocket server in a background thread
    std::thread::spawn(|| {
        let rt = tokio::runtime::Runtime::new().expect("Failed to create tokio runtime");
        rt.block_on(server::start_server());
    });

    // Give the server a moment to start
    std::thread::sleep(std::time::Duration::from_millis(500));

    tauri::Builder::default()
        .run(tauri::generate_context!())
        .expect("error while running tauri application");
}
