# anki-sync

One-command self-hosted Anki sync server, exposed privately over Tailscale.

this setup is hyperfocused on my usecase of using [amgi](https://github.com/antigluten/amgi), hence why tailscale is needed to serve,
as amgi only accepts a https connections for syncing
## Setup

```bash
python3 -m venv venv
venv/bin/pip install anki
cp .env.example .env   # then edit credentials
chmod +x start.sh
```

Enable Tailscale Serve once for your tailnet (the first run prints a link).

## Usage

```bash
./start.sh
```

I reccomend having a alias in ~/.zshrc (or ~/.bashrc):
```bash
alias ankisync='~/anki-sync/start.sh'
```

Prints your sync URL. In Anki: Preferences → Syncing → custom sync server,
and paste that URL. Ctrl+C stops everything cleanly.
