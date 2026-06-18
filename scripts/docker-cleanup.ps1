# Free Docker disk space and restart local Supabase (Windows).
# Run from repo root: powershell -ExecutionPolicy Bypass -File scripts/docker-cleanup.ps1

Write-Host "Stopping Supabase..."
supabase stop 2>$null

Write-Host "Pruning unused Docker data (images, build cache, stopped containers)..."
docker system prune -af --volumes

Write-Host ""
Write-Host "Disk usage after cleanup:"
docker system df

Write-Host ""
Write-Host "Restart Supabase and apply migrations:"
Write-Host "  supabase start"
Write-Host "  supabase db reset"
