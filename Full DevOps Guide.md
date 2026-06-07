# Full DevOps Setup Guide
# Node/Express API + Next.js Admin Panel
# Docker Hub + Tailscale + GitHub Actions CI/CD
# Windows Local Server — No Public IP Required

---

## Table of Contents

1. [Architecture Overview](#architecture)
2. [Part 1 — Docker Hub](#part-1)
3. [Part 2 — Tailscale Tunnel](#part-2)
4. [Part 3 — Local Server Setup](#part-3)
5. [Part 4 — Auto-Start on Boot](#part-4)
6. [Part 5 — GitHub Actions Runners](#part-5)
7. [Part 6 — GitHub Secrets](#part-6)
8. [Part 7 — Code Changes](#part-7)
9. [Part 8 — Dockerfiles](#part-8)
10. [Part 9 — GitHub Actions Workflows](#part-9)
11. [Part 10 — First Deploy](#part-10)
12. [Part 11 — Verify Everything](#part-11)
13. [Image Tagging & Rollbacks](#tagging)
14. [Daily Workflow](#daily)
15. [Useful Commands](#commands)
16. [Final Checklist](#checklist)

---

## Architecture Overview <a name="architecture"></a>

```
Your Dev Machine
  └── git push → GitHub
                  ├── api repo
                  │     └── GitHub Actions
                  │           ├── lint + type-check + test
                  │           ├── docker build → push to Docker Hub (yourname/api:latest)
                  │           └── self-hosted runner → restart api container only
                  │
                  └── admin repo
                        └── GitHub Actions
                              ├── lint + type-check + test
                              ├── docker build → push to Docker Hub (yourname/admin:latest)
                              └── self-hosted runner → restart admin container only

Windows Local Server (no public IP)
  ├── Docker Desktop
  │     ├── api container     → localhost:4000
  │     └── admin container   → localhost:3000
  │
  └── Tailscale (on Windows host)
        ├── https://your-pc.tail1234.ts.net        → admin (port 3000)
        └── https://your-pc.tail1234.ts.net:8443   → api   (port 4000)
```

### Repo structure

```
github/YOUR_USERNAME/
  ├── api/                          ← Express + TypeScript
  │     ├── src/
  │     ├── Dockerfile
  │     ├── .dockerignore
  │     └── .github/
  │           └── workflows/
  │                 └── ci-cd.yml
  │
  ├── admin/                        ← Next.js
  │     ├── app/
  │     ├── next.config.js
  │     ├── Dockerfile
  │     ├── .dockerignore
  │     └── .github/
  │           └── workflows/
  │                 └── ci-cd.yml
  │
  └── infra/                        ← cloned at C:\infra on server
        ├── docker-compose.yml
        └── .env                    ← never commit this
```

---

## Part 1 — Docker Hub <a name="part-1"></a>

### Step 1 — Create Docker Hub account
- Go to https://hub.docker.com and sign up
- Your username will appear in all image names: `yourname/api`, `yourname/admin`

### Step 2 — Create two private repositories
- Click **Create Repository** → Name: `api` → Visibility: **Private** → Create
- Click **Create Repository** → Name: `admin` → Visibility: **Private** → Create

### Step 3 — Create an access token
- Docker Hub → Account Settings → **Security** → **New Access Token**
- Name: `github-actions`
- Permissions: **Read & Write**
- Click **Generate** → **copy the token immediately** — shown only once
- Save it safely, you will need it in Step 16

---

## Part 2 — Tailscale Tunnel <a name="part-2"></a>

> Tailscale Funnel exposes your local services to the public internet
> with permanent HTTPS URLs. Free, no credit card, no domain needed.
> Funnel only supports ports 443, 8443, and 10000 — we use 443 for
> admin and 8443 for API.

### Step 4 — Create a Tailscale account
- Go to https://tailscale.com → click **Get started**
- Sign up with Google, GitHub, or email — no credit card required

### Step 5 — Install Tailscale on Windows
- Go to https://tailscale.com/download/windows
- Download and run the installer
- Tailscale icon appears in the system tray (bottom right, near clock)
- Click the tray icon → **Log in** → browser opens → sign in → click **Connect**
- Tray icon turns green ✓

Find your machine hostname:
```powershell
tailscale status
```
Look for your machine — something like `your-pc.tail1234.ts.net`
Note this down — it is your permanent public base URL.

### Step 6 — Enable Funnel in ACL policy
- Go to https://login.tailscale.com/admin/acls
- Click **Edit** (top right)
- Add `nodeAttrs` to the JSON before the closing `}`:

```json
{
  "acls": [
    {"action": "accept", "src": ["*"], "dst": ["*:*"]}
  ],
  "nodeAttrs": [
    {
      "target": ["*"],
      "attr":   ["funnel"]
    }
  ]
}
```

- Click **Save** → green confirmation ✓

### Step 7 — Configure Funnel
Open **PowerShell as Administrator** (right-click Start → Windows PowerShell (Admin)):

```powershell
# Reset any old config
tailscale serve reset

# Route port 443 → Admin panel (localhost:3000)
tailscale funnel --bg --https=443 http://localhost:3000

# Route port 8443 → API (localhost:4000)
tailscale funnel --bg --https=8443 http://localhost:4000

# Verify both are active
tailscale funnel status
```

Expected output:
```
https://your-pc.tail1234.ts.net (Funnel on)
|-- / proxy http://127.0.0.1:3000

https://your-pc.tail1234.ts.net:8443 (Funnel on)
|-- / proxy http://127.0.0.1:4000
```

Your permanent public URLs are:
```
https://your-pc.tail1234.ts.net        ← Admin panel
https://your-pc.tail1234.ts.net:8443   ← API
```

These URLs never change even after server restarts or reboots.

---

## Part 3 — Local Server Setup <a name="part-3"></a>

### Step 8 — Install Docker Desktop on Windows
- Go to https://docker.com/products/docker-desktop
- Download and install Docker Desktop for Windows
- After install: Settings (gear icon) → General → check **"Start Docker Desktop when you log in"** ✓
- Apply & Restart
- Verify in PowerShell:
```powershell
docker --version
docker compose version
```

### Step 9 — Create the infra folder
```powershell
mkdir C:\infra
cd C:\infra
```

### Step 10 — Create docker-compose.yml
Create `C:\infra\docker-compose.yml`:

```yaml
version: '3.9'

services:

  api:
    image: ${DOCKERHUB_USERNAME}/api:${IMAGE_TAG:-latest}
    container_name: api
    restart: unless-stopped
    ports:
      - '4000:4000'
    environment:
      - NODE_ENV=production
      - PORT=4000
      - DATABASE_URL=${DATABASE_URL}
      - JWT_SECRET=${JWT_SECRET}
    networks:
      - internal
    deploy:
      resources:
        limits:
          memory: 512m
          cpus: '0.5'
    logging:
      driver: json-file
      options:
        max-size: '10m'
        max-file: '3'
    healthcheck:
      test: ['CMD', 'wget', '-qO-', 'http://localhost:4000/health']
      interval: 30s
      timeout: 10s
      retries: 3
      start_period: 10s

  admin:
    image: ${DOCKERHUB_USERNAME}/admin:${IMAGE_TAG:-latest}
    container_name: admin
    restart: unless-stopped
    ports:
      - '3000:3000'
    environment:
      - NODE_ENV=production
      - PORT=3000
    networks:
      - internal
    depends_on:
      api:
        condition: service_healthy
    deploy:
      resources:
        limits:
          memory: 512m
          cpus: '0.5'
    logging:
      driver: json-file
      options:
        max-size: '10m'
        max-file: '3'
    healthcheck:
      test: ['CMD', 'wget', '-qO-', 'http://localhost:3000']
      interval: 30s
      timeout: 10s
      retries: 3
      start_period: 15s

networks:
  internal:
    driver: bridge
```

### Step 11 — Create the .env file
Create `C:\infra\.env`:

```env
DOCKERHUB_USERNAME=your-dockerhub-username
IMAGE_TAG=latest

DATABASE_URL=postgresql://user:password@host:5432/mydb
JWT_SECRET=your-very-long-random-secret-here
```

> Never commit .env to git. Add it to .gitignore in your infra repo.

---

## Part 4 — Auto-Start on Boot <a name="part-4"></a>

### Step 12 — Create the startup script
Create `C:\server-startup.ps1`:

```powershell
# ── Wait for Docker engine to be ready ──────────────────────────────────────
Write-Host "Waiting for Docker to be ready..."
$maxWait = 60
$waited  = 0

while ($waited -lt $maxWait) {
    try {
        docker info | Out-Null
        Write-Host "Docker is ready."
        break
    } catch {
        Start-Sleep -Seconds 3
        $waited += 3
    }
}

if ($waited -ge $maxWait) {
    Write-Host "Docker did not start in time. Exiting."
    exit 1
}

# ── Start containers ─────────────────────────────────────────────────────────
Write-Host "Starting containers..."
Set-Location "C:\infra"
docker compose up -d
Write-Host "Containers started."

# ── Wait for Tailscale to fully connect ──────────────────────────────────────
Write-Host "Waiting for Tailscale..."
Start-Sleep -Seconds 10

# ── Re-apply Funnel rules ────────────────────────────────────────────────────
Write-Host "Applying Tailscale Funnel rules..."
tailscale serve reset
tailscale funnel --bg --https=443  http://localhost:3000
tailscale funnel --bg --https=8443 http://localhost:4000

Write-Host ""
Write-Host "All services are up:"
Write-Host "  Admin : https://your-pc.tail1234.ts.net"
Write-Host "  API   : https://your-pc.tail1234.ts.net:8443"
```

### Step 13 — Register in Task Scheduler

1. Press **Win + S** → search **Task Scheduler** → open it
2. Click **"Create Task"** (not Basic Task)

**General tab:**
- Name: `Server Startup`
- Select: **"Run whether user is logged on or not"** ✓
- Check: **"Run with highest privileges"** ✓
- Configure for: your Windows version

**Triggers tab:**
- Click **New**
- Begin the task: **"At startup"**
- Delay task for: **2 minutes**
- Click OK

**Actions tab:**
- Click **New**
- Action: **"Start a program"**
- Program: `powershell.exe`
- Arguments: `-ExecutionPolicy Bypass -WindowStyle Hidden -File "C:\server-startup.ps1"`
- Click OK

**Settings tab:**
- Check: **"Run task as soon as possible after a scheduled start is missed"** ✓
- If task fails, restart every: **1 minute**, up to **3 times** ✓

Click **OK** → enter your Windows password when prompted ✓

### Step 14 — Verify Tailscale auto-starts
Tailscale installs as a Windows service and starts automatically. Verify:

```powershell
# Run in PowerShell as Admin
Get-Service -Name Tailscale | Select-Object Name, StartType, Status
```

Expected:
```
Name       StartType  Status
----       ---------  ------
Tailscale  Automatic  Running
```

If StartType is not Automatic:
```powershell
Set-Service -Name Tailscale -StartupType Automatic
```

---

## Part 5 — GitHub Actions Runners <a name="part-5"></a>

> A self-hosted runner is installed on your Windows machine.
> It polls GitHub over outbound HTTPS — no inbound port or public IP needed.
> Each repo gets its own runner so deployments are fully independent.

### Step 15 — Register runner for API repo

On GitHub: **api repo** → Settings → Actions → Runners → **New self-hosted runner**
- OS: **Windows** → Architecture: **x64**
- Copy the token shown on the page

In PowerShell as Admin on your server:

```powershell
mkdir C:\actions-runner-api
cd C:\actions-runner-api

# Download — use the exact URL from GitHub's page
Invoke-WebRequest -Uri https://github.com/actions/runner/releases/download/v2.317.0/actions-runner-win-x64-2.317.0.zip -OutFile runner.zip
Expand-Archive -Path runner.zip -DestinationPath .

# Configure (replace token and username)
.\config.cmd `
  --url https://github.com/YOUR_USERNAME/api `
  --token PASTE_TOKEN_HERE `
  --name "local-server-api" `
  --labels "self-hosted,api" `
  --unattended

# Install and start as Windows service
# Install and start as Windows service
.\config.cmd install   # registers the runner as a Windows service
net start "actions.runner.YOUR_USERNAME.api.local-server-api"

# Find the exact service name (copy it from here)
Get-Service | Where-Object { $_.Name -like "actions.runner*" }

# Set to auto-start on boot (paste exact service name from above)
Set-Service -Name "actions.runner.YOUR_USERNAME.api.local-server-api" -StartupType Automatic
```

Go back to GitHub → api repo → Settings → Actions → Runners
You should see **"local-server-api"** with status: **Idle** ✓

### Step 16 — Register runner for Admin repo

On GitHub: **admin repo** → Settings → Actions → Runners → **New self-hosted runner**
- Copy the new token shown

```powershell
mkdir C:\actions-runner-admin
cd C:\actions-runner-admin

Invoke-WebRequest -Uri https://github.com/actions/runner/releases/download/v2.317.0/actions-runner-win-x64-2.317.0.zip -OutFile runner.zip
Expand-Archive -Path runner.zip -DestinationPath .

.\config.cmd `
  --url https://github.com/YOUR_USERNAME/admin `
  --token PASTE_TOKEN_HERE `
  --name "local-server-admin" `
  --labels "self-hosted,admin" `
  --unattended

# Install and start as Windows service
.\config.cmd install   # registers the runner as a Windows service
net start "actions.runner.YOUR_USERNAME.admin.local-server-admin"

# Find the exact service name (copy it from here)
Get-Service | Where-Object { $_.Name -like "actions.runner*" }

# Set to auto-start on boot (paste exact service name from above)
Set-Service -Name "actions.runner.YOUR_USERNAME.admin.local-server-admin" -StartupType Automatic
```

Go back to GitHub → admin repo → Settings → Actions → Runners
You should see **"local-server-admin"** with status: **Idle** ✓

### Verify both runners

```powershell
Get-Service | Where-Object { $_.Name -like "actions.runner*" }
```

Expected:
```
Status   Name                                DisplayName
------   ----                                -----------
Running  actions.runner....api...            GitHub Actions Runner (api)
Running  actions.runner....admin...          GitHub Actions Runner (admin)
```

---

## Part 6 — GitHub Secrets <a name="part-6"></a>

### Step 17 — Add secrets to API repo
Go to: **api repo** → Settings → Secrets and variables → Actions → **New repository secret**

| Secret name | Value |
|-------------|-------|
| `DOCKERHUB_USERNAME` | your Docker Hub username |
| `DOCKERHUB_TOKEN` | access token from Step 3 |
| `DATABASE_URL` | your production DB connection string |
| `JWT_SECRET` | same value as in `C:\infra\.env` |

### Step 18 — Add secrets to Admin repo
Go to: **admin repo** → Settings → Secrets and variables → Actions → **New repository secret**

| Secret name | Value |
|-------------|-------|
| `DOCKERHUB_USERNAME` | your Docker Hub username |
| `DOCKERHUB_TOKEN` | access token from Step 3 |
| `NEXT_PUBLIC_API_URL` | `https://your-pc.tail1234.ts.net:8443` |

> `GITHUB_TOKEN` is provided automatically by GitHub — no setup needed.

---

## Part 7 — Code Changes <a name="part-7"></a>

### Step 19 — Add output: standalone to Next.js
Open `next.config.js` in your **admin repo**:

```js
/** @type {import('next').NextConfig} */
const nextConfig = {
  output: 'standalone',   // ← required for Docker multi-stage build
  // ...rest of your existing config
};

module.exports = nextConfig;
```

> Without this the Docker image will be ~1 GB and won't boot correctly.

### Step 20 — Add /health endpoint to Express API
In your Express entry file (e.g. `src/index.ts`), add before other routes:

```typescript
app.get('/health', (req, res) => {
  res.status(200).json({ status: 'ok' });
});
```

> Docker uses this endpoint to know when the container is ready.

---

## Part 8 — Dockerfiles <a name="part-8"></a>

### Step 21 — Dockerfile for API repo
Create `Dockerfile` in the root of your **api repo**:

```dockerfile
# ── Stage 1: build ───────────────────────────────────────────────────────────
FROM node:20-alpine AS builder
WORKDIR /app
COPY package*.json ./
RUN npm ci
COPY tsconfig.json ./
COPY src ./src
RUN npm run build
RUN npm ci --omit=dev

# ── Stage 2: production ──────────────────────────────────────────────────────
FROM node:20-alpine AS runner
ENV NODE_ENV=production
WORKDIR /app
RUN addgroup -S appgroup && adduser -S appuser -G appgroup
COPY --from=builder /app/dist ./dist
COPY --from=builder /app/node_modules ./node_modules
COPY --from=builder /app/package.json ./package.json
RUN chown -R appuser:appgroup /app
USER appuser
EXPOSE 4000
HEALTHCHECK --interval=30s --timeout=10s --start-period=10s --retries=3 \
  CMD wget -qO- http://localhost:4000/health || exit 1
CMD ["node", "dist/index.js"]
```

Create `.dockerignore` in the root of your **api repo**:
```
node_modules
dist
.env
.env.*
*.log
.git
.gitignore
README.md
```

### Step 22 — Dockerfile for Admin repo
Create `Dockerfile` in the root of your **admin repo**:

```dockerfile
# ── Stage 1: deps ────────────────────────────────────────────────────────────
FROM node:20-alpine AS deps
WORKDIR /app
COPY package*.json ./
RUN npm ci

# ── Stage 2: build ───────────────────────────────────────────────────────────
FROM node:20-alpine AS builder
WORKDIR /app
COPY --from=deps /app/node_modules ./node_modules
COPY . .
ARG NEXT_PUBLIC_API_URL
ENV NEXT_PUBLIC_API_URL=$NEXT_PUBLIC_API_URL
RUN npm run build

# ── Stage 3: production ──────────────────────────────────────────────────────
FROM node:20-alpine AS runner
ENV NODE_ENV=production
WORKDIR /app
RUN addgroup -S appgroup && adduser -S appuser -G appgroup
COPY --from=builder /app/public ./public
COPY --from=builder /app/.next/standalone ./
COPY --from=builder /app/.next/static ./.next/static
RUN chown -R appuser:appgroup /app
USER appuser
EXPOSE 3000
HEALTHCHECK --interval=30s --timeout=10s --start-period=15s --retries=3 \
  CMD wget -qO- http://localhost:3000 || exit 1
CMD ["node", "server.js"]
```

Create `.dockerignore` in the root of your **admin repo**:
```
node_modules
.next
.env
.env.*
*.log
.git
.gitignore
README.md
```

---

## Part 9 — GitHub Actions Workflows <a name="part-9"></a>

### Step 23 — Workflow for API repo
Create `.github/workflows/ci-cd.yml` in your **api repo**:

```yaml
name: CI/CD — API

on:
  push:
    branches: [main]
  pull_request:
    branches: [main]

jobs:

  # ── Lint, type-check, test ───────────────────────────────────────────────
  quality:
    name: Lint & type check
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4

      - uses: actions/setup-node@v4
        with:
          node-version: 20
          cache: npm

      - run: npm ci
      - run: npm run type-check
      - run: npm run lint
      - run: npm test -- --passWithNoTests

  # ── Build image and push to Docker Hub ──────────────────────────────────
  build:
    name: Build & push image
    runs-on: ubuntu-latest
    needs: quality
    if: github.ref == 'refs/heads/main'

    steps:
      - uses: actions/checkout@v4

      - name: Log in to Docker Hub
        uses: docker/login-action@v3
        with:
          username: ${{ secrets.DOCKERHUB_USERNAME }}
          password: ${{ secrets.DOCKERHUB_TOKEN }}

      - uses: docker/setup-buildx-action@v3

      - name: Build & push
        uses: docker/build-push-action@v5
        with:
          context: .
          push: true
          tags: |
            ${{ secrets.DOCKERHUB_USERNAME }}/api:${{ github.sha }}
            ${{ secrets.DOCKERHUB_USERNAME }}/api:latest
          cache-from: type=gha
          cache-to: type=gha,mode=max

  # ── Deploy API only — admin stays running ────────────────────────────────
  deploy:
    name: Deploy API
    runs-on: [self-hosted, api]
    needs: build
    if: github.ref == 'refs/heads/main'

    steps:
      - name: Log in to Docker Hub
        uses: docker/login-action@v3
        with:
          username: ${{ secrets.DOCKERHUB_USERNAME }}
          password: ${{ secrets.DOCKERHUB_TOKEN }}

      - name: Pull new image
        working-directory: C:\infra
        run: docker compose pull api

      - name: Restart API only
        working-directory: C:\infra
        run: docker compose up -d --no-deps api

      - name: Verify
        working-directory: C:\infra
        run: |
          Start-Sleep -Seconds 8
          docker compose ps api
          docker compose logs api --tail=20
```

### Step 24 — Workflow for Admin repo
Create `.github/workflows/ci-cd.yml` in your **admin repo**:

```yaml
name: CI/CD — Admin

on:
  push:
    branches: [main]
  pull_request:
    branches: [main]

jobs:

  # ── Lint, type-check, test ───────────────────────────────────────────────
  quality:
    name: Lint & type check
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4

      - uses: actions/setup-node@v4
        with:
          node-version: 20
          cache: npm

      - run: npm ci
      - run: npm run type-check
      - run: npm run lint
      - run: npm test -- --passWithNoTests

  # ── Build image and push to Docker Hub ──────────────────────────────────
  build:
    name: Build & push image
    runs-on: ubuntu-latest
    needs: quality
    if: github.ref == 'refs/heads/main'

    steps:
      - uses: actions/checkout@v4

      - name: Log in to Docker Hub
        uses: docker/login-action@v3
        with:
          username: ${{ secrets.DOCKERHUB_USERNAME }}
          password: ${{ secrets.DOCKERHUB_TOKEN }}

      - uses: docker/setup-buildx-action@v3

      - name: Build & push
        uses: docker/build-push-action@v5
        with:
          context: .
          push: true
          tags: |
            ${{ secrets.DOCKERHUB_USERNAME }}/admin:${{ github.sha }}
            ${{ secrets.DOCKERHUB_USERNAME }}/admin:latest
          cache-from: type=gha
          cache-to: type=gha,mode=max
          build-args: |
            NEXT_PUBLIC_API_URL=${{ secrets.NEXT_PUBLIC_API_URL }}

  # ── Deploy Admin only — api stays running ────────────────────────────────
  deploy:
    name: Deploy Admin
    runs-on: [self-hosted, admin]
    needs: build
    if: github.ref == 'refs/heads/main'

    steps:
      - name: Log in to Docker Hub
        uses: docker/login-action@v3
        with:
          username: ${{ secrets.DOCKERHUB_USERNAME }}
          password: ${{ secrets.DOCKERHUB_TOKEN }}

      - name: Pull new image
        working-directory: C:\infra
        run: docker compose pull admin

      - name: Restart Admin only
        working-directory: C:\infra
        run: docker compose up -d --no-deps admin

      - name: Verify
        working-directory: C:\infra
        run: |
          Start-Sleep -Seconds 10
          docker compose ps admin
          docker compose logs admin --tail=20
```

> `--no-deps` is the key flag — it restarts only the named service
> and leaves everything else running untouched.

---

## Part 10 — First Deploy <a name="part-10"></a>

### Step 25 — Push to trigger CI for the first time

In your **api repo** on your dev machine:
```bash
git add .
git commit -m "ci: add docker and github actions"
git push origin main
```

In your **admin repo**:
```bash
git add .
git commit -m "ci: add docker and github actions"
git push origin main
```

Watch the runs:
- GitHub → api repo → **Actions** tab → watch 3 jobs: quality → build → deploy
- GitHub → admin repo → **Actions** tab → same

### Step 26 — First manual start on server
After both CI runs successfully push images to Docker Hub:

```powershell
cd C:\infra

# Log in to Docker Hub on the server
docker login -u YOUR_DOCKERHUB_USERNAME
# enter your Docker Hub password or token

# Pull both images
docker compose pull

# Start all services
docker compose up -d

# Check status
docker compose ps
```

Both containers should show status **"healthy"** after ~30 seconds.

---

## Part 11 — Verify Everything <a name="part-11"></a>

### Step 27 — Check containers on server
```powershell
# Status of all containers
docker compose -f C:\infra\docker-compose.yml ps

# Live logs from all services
docker compose -f C:\infra\docker-compose.yml logs -f

# Logs from specific service
docker compose -f C:\infra\docker-compose.yml logs api --tail=50
docker compose -f C:\infra\docker-compose.yml logs admin --tail=50
```

### Step 28 — Test public URLs
Open these on your **phone using mobile data** (not same WiFi as server):

```
https://your-pc.tail1234.ts.net:8443/health   → should return {"status":"ok"}
https://your-pc.tail1234.ts.net               → should show your admin panel
```

### Step 29 — Test independent redeployment
Make a small change to your API (e.g. add a comment) and push:
```bash
git push origin main
```
Watch GitHub Actions → only the API container restarts → admin stays up the entire time.

Repeat for admin repo → only admin restarts → API stays up.

### Step 30 — Test full reboot
Restart your Windows machine. After **3 minutes**:

```powershell
# Should show both containers running
docker compose -f C:\infra\docker-compose.yml ps

# Should show both funnel rules active
tailscale funnel status

# Should show both runners online
Get-Service | Where-Object { $_.Name -like "actions.runner*" }
```

All should be up with zero manual intervention ✓

---

## Image Tagging & Rollbacks <a name="tagging"></a>

Every push to `main` creates two tags on Docker Hub:

| Tag | Example | Purpose |
|-----|---------|---------|
| `latest` | `yourname/api:latest` | always points to newest build |
| commit SHA | `yourname/api:a1b2c3d` | permanent snapshot, used for rollbacks |

### To rollback to a previous version

1. Find the commit SHA from GitHub → Actions → the run you want to go back to
2. On your server:

```powershell
cd C:\infra

# Open .env and change IMAGE_TAG to the commit SHA
notepad .env
# set IMAGE_TAG=a1b2c3d

# Pull that specific version
docker compose pull api

# Restart with that version
docker compose up -d --no-deps api
```

To go back to latest:
```powershell
# Set IMAGE_TAG=latest in .env, then:
docker compose pull api
docker compose up -d --no-deps api
```

---

## Daily Workflow <a name="daily"></a>

After setup is complete, your entire deploy flow is:

```
Make changes to code
  └── git push origin main
        └── GitHub Actions triggers automatically
              ├── quality: lint + type-check + test
              │     ↓ (fails here = no deploy, safe)
              ├── build: docker build → push to Docker Hub
              │     tags: yourname/api:abc1234 + yourname/api:latest
              │     ↓
              └── deploy: self-hosted runner on your Windows server
                    docker compose pull api
                    docker compose up -d --no-deps api
                    ↓
                    Only API restarts (~5 seconds downtime)
                    Admin panel stays running throughout
```

Push to admin repo does the exact same but for admin only.

---

## Useful Commands <a name="commands"></a>

```powershell
# ── Containers ───────────────────────────────────────────────────────────────

# Check status
docker compose -f C:\infra\docker-compose.yml ps

# Live logs (all services)
docker compose -f C:\infra\docker-compose.yml logs -f

# Logs for one service
docker compose -f C:\infra\docker-compose.yml logs api -f
docker compose -f C:\infra\docker-compose.yml logs admin -f

# Restart one service
docker compose -f C:\infra\docker-compose.yml restart api

# Manual deploy without CI
cd C:\infra
docker compose pull api
docker compose up -d --no-deps api

# Stop everything
docker compose -f C:\infra\docker-compose.yml down

# Start everything
docker compose -f C:\infra\docker-compose.yml up -d

# Resource usage
docker stats

# Free up disk (remove old unused images)
docker image prune -f


# ── Tailscale ────────────────────────────────────────────────────────────────

# Check tunnel status
tailscale funnel status

# Check connection
tailscale status

# Re-apply funnel rules if lost
tailscale serve reset
tailscale funnel --bg --https=443  http://localhost:3000
tailscale funnel --bg --https=8443 http://localhost:4000


# ── GitHub Runners ───────────────────────────────────────────────────────────

# Check runner services
Get-Service | Where-Object { $_.Name -like "actions.runner*" }

# Restart a runner
Restart-Service -Name "actions.runner.YOUR_USERNAME.api.local-server-api"
```

---

## Final Checklist <a name="checklist"></a>

### Part 1 — Docker Hub
- [ ] Step 1: Docker Hub account created
- [ ] Step 2: Two private repos created (api, admin)
- [ ] Step 3: Access token generated and saved

### Part 2 — Tailscale
- [ ] Step 4: Tailscale account created
- [ ] Step 5: Tailscale installed on Windows, showing green
- [ ] Step 6: Funnel enabled in ACL policy
- [ ] Step 7: Both funnel rules active — `tailscale funnel status` shows both ports

### Part 3 — Local Server
- [ ] Step 8: Docker Desktop installed, auto-start on login enabled
- [ ] Step 9: `C:\infra` folder created
- [ ] Step 10: `docker-compose.yml` created
- [ ] Step 11: `.env` file created with real values

### Part 4 — Auto-Start
- [ ] Step 12: `C:\server-startup.ps1` created
- [ ] Step 13: Task Scheduler task registered
- [ ] Step 14: Tailscale service set to Automatic

### Part 5 — GitHub Runners
- [ ] Step 15: API runner registered → shows **Idle** on GitHub
- [ ] Step 16: Admin runner registered → shows **Idle** on GitHub

### Part 6 — GitHub Secrets
- [ ] Step 17: API repo secrets added (DOCKERHUB_USERNAME, DOCKERHUB_TOKEN, DATABASE_URL, JWT_SECRET)
- [ ] Step 18: Admin repo secrets added (DOCKERHUB_USERNAME, DOCKERHUB_TOKEN, NEXT_PUBLIC_API_URL)

### Part 7 — Code Changes
- [ ] Step 19: `output: 'standalone'` added to `next.config.js`
- [ ] Step 20: `/health` endpoint added to Express app

### Part 8 — Dockerfiles
- [ ] Step 21: `Dockerfile` + `.dockerignore` added to api repo
- [ ] Step 22: `Dockerfile` + `.dockerignore` added to admin repo

### Part 9 — GitHub Actions Workflows
- [ ] Step 23: `.github/workflows/ci-cd.yml` added to api repo
- [ ] Step 24: `.github/workflows/ci-cd.yml` added to admin repo

### Part 10 — First Deploy
- [ ] Step 25: Pushed to main in both repos → CI runs green ✓
- [ ] Step 26: `docker compose up -d` on server → both containers healthy ✓

### Part 11 — Verify
- [ ] Step 27: Containers running and logs look clean
- [ ] Step 28: Public URLs work from phone on mobile data
- [ ] Step 29: Independent redeployment tested (push to one repo, only that service restarts)
- [ ] Step 30: Full reboot test passed — everything comes back automatically