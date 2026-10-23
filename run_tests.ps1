# Runs every test: the database suite (psql), the Go unit tests, and the
# Go concurrency test. Run from the project root:
#   .\run_tests.ps1
#   .\run_tests.ps1 -Only db      # just the SQL suite
#   .\run_tests.ps1 -Only go      # just the Go tests
param([ValidateSet('all', 'db', 'go')][string]$Only = 'all')

$root = $PSScriptRoot
Set-Location $root

# Load .env into this session (psql reads PG*; the Go tests read the rest).
Get-Content (Join-Path $root '.env') | ForEach-Object {
    if ($_ -match '^\s*([^#=]+)=(.*)$') { Set-Item "env:$($matches[1].Trim())" $matches[2].Trim() }
}

function Banner([string]$title) {
    Write-Host ''
    Write-Host ('#' * 64) -ForegroundColor Cyan
    Write-Host "##  $title" -ForegroundColor Cyan
    Write-Host ('#' * 64) -ForegroundColor Cyan
}

if ($Only -in 'all', 'db') {
    Banner 'DATABASE TESTS  (db/tests/run_all.sql)'
    # 2>&1 through cmd keeps errors in order with the output they belong to.
    cmd /c "psql -X -w -f db/tests/run_all.sql 2>&1"
}

if ($Only -in 'all', 'go') {
    Push-Location (Join-Path $root 'backend')

    Banner 'GO UNIT TESTS  (go test -short ./...)'
    go test -short -count=1 ./...

    Banner 'GO CONCURRENCY TEST  (50 goroutines book the same slot at once)'
    go test -v -count=1 -run TestConcurrentBooking ./internal/db/

    Pop-Location
}

Banner 'DONE'
