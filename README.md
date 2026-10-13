# LafonTech Proxy — Fly.io Deployment

---

## What changed from the Google Cloud Run setup

| Component | Cloud Run | Fly.io (this setup) |
|---|---|---|
| **TLS** | Handled by Cloud Run | Terminated at Fly.io edge (auto HTTPS) |
| **SNI / Host** | `crashlyticsreports-pa.googleapis.com` (domain fronting) | `your-app.fly.dev` (direct) |
| **Infrastructure** | Serverless (request-scaled) | 1 VM always running |
| **Cost** | Free tier | Free tier (3 shared VMs, ~160GB/mo) |

> **Why no domain fronting?** Fly.io's edge TLS terminator routes by SNI. The cert presented is for your `.fly.dev` subdomain, so `serverName` and `Host` must match it. Domain fronting would require a custom domain + CDN layer (possible, but not on the free path).

---

## File map

| File | Purpose |
|---|---|
| `server.json` | Xray-core inbound config (VLESS + WebSocket) |
| `Dockerfile` | Builds Xray container (Alpine + official binary) |
| `fly.toml` | Fly.io app manifest (always-on, 256MB) |
| `client.json` | Updated client config pointing at Fly.io |

---

## Prerequisites

1. A Fly.io account — [https://fly.io](https://fly.io)
2. `flyctl` CLI installed — [Install guide](https://fly.io/docs/hands-on/install-flyctl/)
3. Your existing UUID (or generate a new one)

---

## Step 1: Prepare configs

1. **Generate a new UUID** (recommended instead of reusing the demo one):
   ```bash
   uuidgen
   # Linux fallback: cat /proc/sys/kernel/random/uuid
   ```

2. **Replace the placeholder UUID** in both files:
   - `server.json` → `"id": "your-new-uuid"`
   - `client.json` → `"id": "your-new-uuid"`

3. **Rename the app** in `fly.toml`:
   ```toml
   app = 'your-unique-name'
   ```
   and update the client config to match:
   ```json
   "address": "your-unique-name.fly.dev"
   "Host": "your-unique-name.fly.dev"
   "serverName": "your-unique-name.fly.dev"
   ```

---

## Step 2: Deploy to Fly.io

From this directory:

```bash
# Authenticate (opens browser)
fly auth login

# Create the app and generate a fly.toml scaffold
# When it asks, decline to deploy immediately
fly launch --no-deploy

# IMPORTANT: Overwrite the generated fly.toml with the one provided here,
# or edit it manually to ensure these values are set:
#   auto_stop_machines = 'off'
#   min_machines_running = 1

# Deploy
cp fly.toml fly.toml.bak  # optional backup
fly deploy

# Verify it's running
fly status
fly logs
```

**What the deploy does:**
- Builds the Docker image with Xray-core
- Pushes it to Fly.io's registry
- Starts a 256MB shared-CPU VM
- Exposes port 8080 internally
- Fly.io maps `https://your-app.fly.dev` → your container

---

## Step 3: Connect your client

Import `client.json` into your Xray client (v2rayN, v2rayNG, Streisand, etc.) and connect.

**Test the endpoint first:**
```bash
curl -i -N \
  -H "Upgrade: websocket" \
  -H "Connection: Upgrade" \
  -H "Host: your-app.fly.dev" \
  https://your-app.fly.dev/Telegram/@AM2_D3/@AHMAD3214
```
You should get a WebSocket upgrade response (or a 400/403 from Xray if auth fails). A connection timeout or TLS error means Fly.io isn't routing correctly yet.

---

## Critical Fly.toml settings explained

```toml
auto_stop_machines = 'off'    # Prevents the VM from sleeping
min_machines_running = 1      # Keeps 1 instance alive 24/7
memory = '256mb'              # Free-tier size
cpu_kind = 'shared'           # Free-tier CPU type
```

If you omit `auto_stop_machines = 'off'`, Fly.io will stop the VM after ~15 min of inactivity and your proxy will hang until the cold-start finishes.

---

## Security hardening (optional)

1. **Randomize the path** instead of using the Telegram promo path:
   ```json
   "path": "/ws-" + random_string
   ```
   Update both `server.json` and `client.json`.

2. **Enable fallback** in `server.json` to masquerade as a real website:
   ```json
   "fallbacks": [
     {
       "dest": "127.0.0.1:8081"
     }
   ]
   ```
   Then run a dummy Nginx/Caddy server on 8081 serving a static site.

3. **Rotate UUIDs regularly.** Xray supports multiple clients in the `clients` array.

---

## Troubleshooting

| Symptom | Fix |
|---|---|
| `Connection refused` / `timeout` | Check `fly status`; verify `internal_port` matches Xray's `port` (8080). |
| TLS handshake error | Ensure `serverName` in client matches the Fly.io app domain exactly. |
| `403 Bad Request` | WebSocket path mismatch. Check `path` is identical in client and server. |
| High latency | Change `primary_region` in `fly.toml` to a region closer to you (e.g., `ams`, `lhr`, `sin`, `syd`). |
| Out of memory | Increase `memory` in `fly.toml` (costs money if above free tier). Xray usually runs fine in 128–256MB. |

---

## Region codes (pick one close to you)

| Code | Location |
|---|---|
| `iad` | Washington DC, USA |
| `ewr` | New Jersey, USA |
| `ord` | Chicago, USA |
| `dfw` | Dallas, USA |
| `lax` | Los Angeles, USA |
| `sea` | Seattle, USA |
| `ams` | Amsterdam, NL |
| `lhr` | London, UK |
| `fra` | Frankfurt, DE |
| `sin` | Singapore |
| `nrt` | Tokyo, JP |
| `syd` | Sydney, AU |
| `bom` | Mumbai, IN |
| `gru` | Sao Paulo, BR |
| `jnb` | Johannesburg, ZA |

---

## Architecture

```
[Your Device] --wss+TLS--> [Fly.io Edge] --ws--> [Xray Container :8080] --> Internet
                    |                            (VLESS+WS inbound)
                    +---- Auto HTTPS cert (*.fly.dev)
```

Traffic inside Fly.io's network (edge → your VM) stays within their private network. The TLS termination happens at the edge, so the container sees plain WebSocket.

---

## Limits (Free Tier)

- **Machines:** Up to 3 shared-cpu-1x VMs running simultaneously
- **Bandwidth:** ~160 GB outbound/month
- **Storage:** 3 GB persistent volume (not used here)
- **Always-on:** Supported with `min_machines_running = 1`

If you exceed these, Fly.io bills per-second for usage. Monitor via `fly billing` or the dashboard.
