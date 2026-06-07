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
Set-Location "D:\JVM-SERVER"
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
Write-Host "  Admin : https://santu.tail05c74b.ts.net:443"
Write-Host "  API   : https://santu.tail05c74b.ts.net:8443"