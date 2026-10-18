mod service;
mod share_selection;

use anyhow::{bail, Context, Result};
use clap::{Parser, Subcommand};
use futures_util::StreamExt;
use std::io::{self, Read, Write};
use std::path::PathBuf;

const BUS: &str = "io.github.rifle.QuickShare";
const PATH: &str = "/io/github/rifle/QuickShare";
const INTERFACE: &str = "io.github.rifle.QuickShare1";

#[derive(Parser)]
#[command(version, about = "Android Quick Share")]
struct Cli {
    #[command(subcommand)]
    command: Command,
}

#[derive(Subcommand)]
enum Command {
    Serve {
        #[arg(long, default_value_t = 47593, value_parser = clap::value_parser!(u16).range(1..))]
        port: u16,
        #[arg(long)]
        download_dir: Option<PathBuf>,
        #[arg(long)]
        no_bluetooth: bool,
        #[arg(long)]
        no_lan: bool,
        #[arg(long)]
        no_hotspot: bool,
    },
    Status,
    Watch,
    Browse,
    Visible {
        seconds: u32,
    },
    NetworkConsent {
        #[arg(value_parser = ["on", "off"])]
        value: String,
    },
    Send {
        peer: String,
    },
    Share,
    ShareFiles { files: Vec<String> },
    TakeShare {
        token: String,
    },
    Accept {
        id: String,
    },
    Reject {
        id: String,
    },
    Cancel {
        id: String,
    },
    DownloadDir,
    PickFiles,
    Doctor,
}

fn print_json_line(value: &str) -> Result<()> {
    let mut out = io::stdout().lock();
    writeln!(out, "{value}")?;
    out.flush()?;
    Ok(())
}

const MAX_PRIVATE_INPUT_BYTES: u64 = 32 * 1024 * 1024;

fn read_private_json<T: serde::de::DeserializeOwned>(reader: impl Read) -> Result<T> {
    let mut bytes = Vec::new();
    reader
        .take(MAX_PRIVATE_INPUT_BYTES + 1)
        .read_to_end(&mut bytes)
        .context("Cannot read the private selection from stdin")?;
    if bytes.len() as u64 > MAX_PRIVATE_INPUT_BYTES {
        bail!("The private selection exceeds the 32 MiB limit");
    }
    serde_json::from_slice(&bytes).context("Expected a valid JSON selection on stdin")
}

fn read_files(reader: impl Read) -> Result<Vec<String>> {
    let files: Vec<String> = read_private_json(reader)?;
    if files.is_empty() || files.len() > share_selection::MAX_FILES {
        bail!("Select between 1 and 1000 files");
    }
    Ok(files)
}

fn canonical_files(files: &[String]) -> Result<Vec<String>> {
    files
        .iter()
        .map(|p| {
            let path =
                std::fs::canonicalize(p).with_context(|| format!("File not accessible: {p}"))?;
            path.into_os_string()
                .into_string()
                .map_err(|_| anyhow::anyhow!("The path cannot be represented in D-Bus"))
        })
        .collect()
}

async fn share(files: &[String]) -> Result<()> {
    let paths = canonical_files(files)?;
    for path in &paths {
        let metadata =
            std::fs::metadata(path).with_context(|| format!("File not accessible: {path}"))?;
        if !metadata.is_file() {
            bail!("Only regular files can be sent: {path}");
        }
        std::fs::File::open(path).with_context(|| format!("File not readable: {path}"))?;
    }
    let connection = zbus::Connection::session().await?;
    let proxy = zbus::Proxy::new(&connection, BUS, PATH, INTERFACE).await?;
    let token: String = proxy.call("PrepareShare", &(paths,)).await?;
    let summon_result = async {
        let output = tokio::process::Command::new("quickshell")
            .args(["ipc", "call", "quickshare", "share", &token])
            .output()
            .await
            .context("Cannot run quickshell to open Quick Share")?;
        if !output.status.success() {
            bail!(
                "Cannot open the Quick Share panel: {}",
                String::from_utf8_lossy(&output.stderr).trim()
            );
        }
        Ok(())
    }
    .await;
    if summon_result.is_err() {
        let _: zbus::Result<Vec<String>> = proxy.call("TakeShare", &(token,)).await;
    }
    summon_result
}

#[derive(serde::Deserialize)]
struct SnapshotOrder<'a> {
    #[serde(borrow)]
    instance_id: &'a str,
    revision: u64,
}

#[tokio::main]
async fn main() -> Result<()> {
    let cli = Cli::parse();
    if let Command::Serve {
        port,
        download_dir,
        no_bluetooth,
        no_lan,
        no_hotspot,
    } = cli.command
    {
        tracing_subscriber::fmt()
            .with_env_filter(
                tracing_subscriber::EnvFilter::try_from_default_env()
                    .unwrap_or_else(|_| "warn".into()),
            )
            .with_writer(io::stderr)
            .init();
        return service::serve(
            port,
            download_dir,
            rqs_lib::EngineOptions {
                bluetooth: !no_bluetooth,
                lan: !no_lan,
                hotspot: !no_hotspot,
            },
        )
        .await;
    }
    match cli.command {
        Command::Share => share(&read_files(io::stdin().lock())?).await?,
        Command::ShareFiles { files } => share(&files).await?,
        Command::PickFiles => {
            let selection = ashpd::desktop::file_chooser::SelectedFiles::open_file()
                .title("Share with Quick Share")
                .multiple(true)
                .modal(false)
                .send()
                .await
                .and_then(|request| request.response());
            let response = match selection {
                Ok(response) => response,
                Err(ashpd::Error::Response(ashpd::desktop::ResponseError::Cancelled)) => {
                    print_json_line("[]")?;
                    return Ok(());
                }
                Err(error) => return Err(error.into()),
            };
            let paths: Vec<PathBuf> = response
                .uris()
                .iter()
                .map(|uri| {
                    url::Url::parse(uri.as_str())?
                        .to_file_path()
                        .map_err(|_| anyhow::anyhow!("The portal returned a non-local URI"))
                })
                .collect::<Result<_>>()?;
            print_json_line(&serde_json::to_string(&paths)?)?;
        }
        Command::Doctor => service::doctor().await?,
        other => {
            let connection = zbus::Connection::session().await?;
            let proxy = zbus::Proxy::new(&connection, BUS, PATH, INTERFACE).await?;
            match other {
                Command::Status => {
                    let snapshot: String = proxy
                        .call("Snapshot", &())
                        .await
                        .context("The Quick Share service is not available")?;
                    print_json_line(&snapshot)?;
                }
                Command::Watch => {
                    let mut signals = proxy.receive_signal("Changed").await?;
                    let mut owners = proxy.receive_owner_changed().await?;
                    let snapshot: String = proxy.call("Snapshot", &()).await?;
                    let order: SnapshotOrder<'_> = serde_json::from_str(&snapshot)?;
                    let mut instance = order.instance_id.to_owned();
                    let mut revision = order.revision;
                    print_json_line(&snapshot)?;
                    loop {
                        tokio::select! {
                            signal = signals.next() => {
                                let signal = signal.context("The connection to the service ended")?;
                                let (snapshot,): (String,) = signal.body().deserialize()?;
                                let order: SnapshotOrder<'_> = serde_json::from_str(&snapshot)?;
                                if order.instance_id != instance { continue; }
                                if order.revision > revision {
                                    revision = order.revision;
                                    print_json_line(&snapshot)?;
                                }
                            }
                            owner = owners.next() => {
                                owner.context("The D-Bus connection ended")?;
                                match proxy.call::<_, _, String>("Snapshot", &()).await {
                                    Ok(snapshot) => {
                                        let order: SnapshotOrder<'_> = serde_json::from_str(&snapshot)?;
                                        instance = order.instance_id.to_owned();
                                        revision = order.revision;
                                        print_json_line(&snapshot)?;
                                    }
                                    Err(error) => print_json_line(&serde_json::json!({"online": false, "error": error.to_string()}).to_string())?,
                                }
                            },
                        }
                    }
                }
                Command::Browse => {
                    let _: () = proxy.call("Browse", &()).await?;
                    tokio::task::spawn_blocking(|| io::copy(&mut io::stdin().lock(), &mut io::sink())).await??;
                }
                Command::Visible { seconds } => {
                    let _: () = proxy.call("SetVisibility", &(seconds,)).await?;
                }
                Command::NetworkConsent { value } => {
                    let _: () = proxy.call("SetNetworkConsent", &(value == "on",)).await?;
                }
                Command::Send { peer } => {
                    let paths = canonical_files(&read_files(io::stdin().lock())?)?;
                    let id: String = proxy.call("Send", &(peer, paths)).await?;
                    println!("{id}");
                }
                Command::TakeShare { token } => {
                    let paths: Vec<String> = proxy.call("TakeShare", &(token,)).await?;
                    print_json_line(&serde_json::to_string(&paths)?)?;
                }
                Command::Accept { id } => {
                    let _: () = proxy.call("Respond", &(id, true)).await?;
                }
                Command::Reject { id } => {
                    let _: () = proxy.call("Respond", &(id, false)).await?;
                }
                Command::Cancel { id } => {
                    let _: () = proxy.call("Cancel", &(id,)).await?;
                }
                Command::DownloadDir => {
                    let path: String = read_private_json(io::stdin().lock())?;
                    let path = std::fs::canonicalize(path)?;
                    let path = path.to_str().context("Path not representable in D-Bus")?;
                    let _: () = proxy.call("SetDownloadDirectory", &(path,)).await?;
                }
                _ => unreachable!(),
            }
        }
    }
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn private_file_input_preserves_json_paths_and_enforces_count_and_type() {
        let files = vec![
            "/private/quote\" and ü".to_owned(),
            "/private/new\nline".to_owned(),
        ];
        let json = serde_json::to_vec(&files).unwrap();
        assert_eq!(read_files(json.as_slice()).unwrap(), files);
        for input in [
            "",
            "[]",
            "null",
            "{}",
            "[1]",
            "[\"file\"",
            "\"/private/file\"",
        ] {
            assert!(read_files(input.as_bytes()).is_err(), "{input:?}");
        }
        let maximum = vec!["/private/file"; share_selection::MAX_FILES];
        assert_eq!(
            read_files(serde_json::to_vec(&maximum).unwrap().as_slice())
                .unwrap()
                .len(),
            share_selection::MAX_FILES
        );
        let excessive = vec!["/private/file"; share_selection::MAX_FILES + 1];
        assert!(read_files(serde_json::to_vec(&excessive).unwrap().as_slice()).is_err());
    }

    #[test]
    fn private_input_has_an_exact_byte_limit_without_truncating_json() {
        let padding = io::repeat(b' ').take(MAX_PRIVATE_INPUT_BYTES - 2);
        let exact = io::Cursor::new(b"[]").chain(padding);
        assert!(read_private_json::<Vec<String>>(exact).unwrap().is_empty());
        let oversized =
            io::Cursor::new(b"[]").chain(io::repeat(b' ').take(MAX_PRIVATE_INPUT_BYTES - 1));
        assert!(read_private_json::<Vec<String>>(oversized).is_err());
        assert!(read_private_json::<String>(io::Cursor::new(b"\"/private/dir\"")).is_ok());
        assert!(read_private_json::<String>(io::Cursor::new(b"[\"/private/dir\"]")).is_err());
        assert!(read_private_json::<Vec<String>>(io::Cursor::new(b"[\"\xff\"]")).is_err());
    }

    #[test]
    fn private_paths_are_not_accepted_as_cli_arguments() {
        for arguments in [
            vec!["quickshare", "share", "/private/file"],
            vec!["quickshare", "send", "peer", "/private/file"],
            vec!["quickshare", "download-dir", "/private/directory"],
        ] {
            assert!(Cli::try_parse_from(arguments).is_err());
        }
        assert!(Cli::try_parse_from(["quickshare", "share"]).is_ok());
        assert!(Cli::try_parse_from(["quickshare", "send", "peer"]).is_ok());
        assert!(Cli::try_parse_from(["quickshare", "download-dir"]).is_ok());
        assert!(Cli::try_parse_from(["quickshare", "take-share", "opaque-token"]).is_ok());
    }
}
