//! Headless Quick Share receiver that speaks the plugin's JSON-lines protocol.
//!
//! Outgoing events: status, ask, progress, received, result, decision.
//! Incoming commands on stdin: {"cmd":"accept"|"decline","id":"..."}

use rqs_lib::channel::{ChannelMessage, Message, TransferAction, TransferKind};
use rqs_lib::hdl::info::TransferPayload;
use rqs_lib::{RQS, TransferState, Visibility};
use serde_json::{Value, json};
use std::collections::HashSet;
use std::io::Write;
use std::path::PathBuf;
use tokio::io::{AsyncBufReadExt, BufReader};

fn emit(value: Value) {
    let mut out = std::io::stdout().lock();
    let _ = writeln!(out, "{}", value);
    let _ = out.flush();
}

fn file_list(md: &rqs_lib::hdl::info::TransferMetadata) -> Vec<String> {
    match &md.payload {
        Some(TransferPayload::Files(files)) => files.clone(),
        Some(TransferPayload::Text(text)) | Some(TransferPayload::Url(text)) => vec![text.clone()],
        Some(TransferPayload::Wifi { ssid, .. }) => vec![ssid.clone()],
        None => Vec::new(),
    }
}

#[tokio::main]
async fn main() -> anyhow::Result<()> {
    if std::env::var("RUST_LOG").is_ok() {
        tracing_subscriber::fmt()
            .with_env_filter(
                tracing_subscriber::EnvFilter::builder().from_env_lossy(),
            )
            .with_writer(std::io::stderr)
            .init();
    }

    let download_dir = PathBuf::from(
        std::env::var("RQS_DOWNLOAD_DIR")
            .unwrap_or_else(|_| format!("{}/Downloads/Quick Share", std::env::var("HOME").unwrap_or_default())),
    );
    std::fs::create_dir_all(&download_dir).ok();
    let name = std::env::var("RQS_DEVICE_NAME").unwrap_or_else(|_| "Omarchy PC".to_string());

    let mut rqs = RQS::new(
        Visibility::Visible,
        Some(53318),
        Some(download_dir.clone()),
        Some(name.clone()),
    );
    rqs.run().await?;
    emit(json!({
        "t": "status",
        "backend": "quickshare-rx",
        "state": "ready",
        "port": 53318,
        "name": name
    }));

    // Decision channel: the Python bridge writes commands to our stdin.
    let sender = rqs.message_sender.clone();
    tokio::spawn(async move {
        let mut lines = BufReader::new(tokio::io::stdin()).lines();
        while let Ok(Some(line)) = lines.next_line().await {
            let cmd: Value = match serde_json::from_str(&line) {
                Ok(v) => v,
                Err(_) => continue,
            };
            let action = match cmd["cmd"].as_str() {
                Some("accept") => Some(TransferAction::ConsentAccept),
                Some("decline") => Some(TransferAction::ConsentDecline),
                _ => None,
            };
            let id = match cmd["id"].as_str() {
                Some(id) => id.to_string(),
                None => continue,
            };
            if let Some(action) = action {
                let accepted = action == TransferAction::ConsentAccept;
                let _ = sender.send(ChannelMessage {
                    id: id.clone(),
                    msg: Message::Lib { action },
                });
                emit(json!({"t": "decision", "id": id, "accepted": accepted}));
            }
        }
    });

    let mut receiver = rqs.message_sender.subscribe();
    let mut announced = HashSet::new();

    while let Ok(message) = receiver.recv().await {
        let client = match &message.msg {
            Message::Client(client) => client,
            Message::Lib { .. } => continue,
        };
        if client.kind != TransferKind::Inbound {
            continue;
        }
        let metadata = match &client.metadata {
            Some(metadata) => metadata,
            None => continue,
        };

        match client.state {
            Some(TransferState::WaitingForUserConsent) => {
                if announced.insert(message.id.clone()) {
                    emit(json!({
                        "t": "ask",
                        "id": message.id,
                        "from": metadata.source.as_ref().map(|s| s.name.clone()).unwrap_or_default(),
                        "pin": metadata.pin_code.clone().unwrap_or_default(),
                        "files": file_list(metadata),
                        "bytes": metadata.total_bytes
                    }));
                }
            }
            Some(TransferState::ReceivingFiles) => {
                emit(json!({
                    "t": "progress",
                    "id": message.id,
                    "done": metadata.ack_bytes,
                    "total": metadata.total_bytes
                }));
            }
            Some(TransferState::Finished) => {
                let saved = metadata.saved_paths.clone().unwrap_or_default();
                emit(json!({
                    "t": "received",
                    "id": message.id,
                    "from": metadata.source.as_ref().map(|s| s.name.clone()).unwrap_or_default(),
                    "files": file_list(metadata),
                    "dir": metadata.destination.clone().unwrap_or_else(|| saved.join(", ")),
                    "bytes": metadata.total_bytes
                }));
            }
            Some(TransferState::Rejected) => {
                emit(json!({"t": "result", "id": message.id, "code": "declined"}));
            }
            Some(TransferState::Cancelled) => {
                emit(json!({"t": "result", "id": message.id, "code": "cancelled"}));
            }
            _ => {}
        }
    }

    Ok(())
}
