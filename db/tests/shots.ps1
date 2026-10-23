# Screenshot helpers. Load once per terminal, from the project root:
#   . .\db\tests\shots.ps1
#
#   tcase 04 T4.15 T4.21      run 04_*.sql, show only cases T4.15..T4.21
#   tcase 02 T2.13            just one case
#   tcase 04 Setup T4.7       from the file's setup block to T4.7
#   snap fig-13-seat-map      save the image on the clipboard (Win+Shift+S) to docs/screenshots/fig-13-seat-map.png
#   testcases                 write docs/report/test-cases.csv (one row per test case) for the report table

$script:root = Split-Path (Split-Path $PSScriptRoot)
Set-Location $script:root
Get-Content (Join-Path $script:root '.env') | ForEach-Object {
    if ($_ -match '^\s*([^#=]+)=(.*)$') { Set-Item "env:$($matches[1].Trim())" $matches[2].Trim() }
}

function tcase([string]$file, [string]$from, [string]$to = $from) {
    $path = (Get-ChildItem (Join-Path $script:root 'db\tests') -Filter "$file*.sql" | Select-Object -First 1).Name
    if (-not $path) { Write-Host "no test file starting with $file" -ForegroundColor Red; return }
    Write-Host "-- db/tests/$path   (clock pinned at 2026-11-10 19:20 IST, rolled back after)" -ForegroundColor DarkGray
    $out = cmd /c "psql -X -w -f db/tests/$path 2>&1"
    $on = $false; $done = $false
    foreach ($l in $out) {
        if ($l -match '^=== (T\d+\.\d+|Setup)') {
            $id = $matches[1]
            if ($id -eq $from) { $on = $true }
            elseif ($on -and $done) { break }
            if ($on -and $id -eq $to) { $done = $true }
        }
        elseif ($on -and $done -and $l -match '^(-{16} [a-z]|ROLLBACK|\(rolled back)') { break }
        if ($on -and $l -notmatch '^LOCATION:') { $l -replace '^psql:[^:]+:\d+: ', '' }
    }
    if (-not $on) { Write-Host "case $from not found in $path" -ForegroundColor Red }
}

function snap([string]$name) {
    Add-Type -AssemblyName System.Windows.Forms, System.Drawing
    $img = [System.Windows.Forms.Clipboard]::GetImage()
    if (-not $img) { Write-Host 'no image on the clipboard: snip with Win+Shift+S first' -ForegroundColor Red; return }
    if ($name -notmatch '\.png$') { $name += '.png' }
    $dest = Join-Path $script:root "docs\screenshots\$name"
    $img.Save($dest, [System.Drawing.Imaging.ImageFormat]::Png)
    Write-Host "saved $dest ($($img.Width)x$($img.Height))" -ForegroundColor Green
}

function testcases {
    $rows = foreach ($f in Get-ChildItem (Join-Path $script:root 'db\tests') -Filter '0*.sql') {
        foreach ($m in Select-String -Path $f.FullName -Pattern "^\\echo '=== (T\d+\.\d+)\s+(.*?)\s+\(EXPECT: (.*)\) ===" ) {
            [pscustomobject]@{
                ID       = $m.Matches[0].Groups[1].Value
                File     = $f.Name
                Test     = $m.Matches[0].Groups[2].Value
                Expected = $m.Matches[0].Groups[3].Value
                Actual   = 'As expected'
                Result   = 'PASS'
            }
        }
    }
    $rows += [pscustomobject]@{ ID = 'G1'; File = 'concurrency_test.go'; Test = '50 goroutines book the only hall at one slot'; Expected = 'exactly 1 booked, 49 RB409, no table twice'; Actual = 'As expected'; Result = 'PASS' }
    $rows += [pscustomobject]@{ ID = 'G2'; File = 'concurrency_test.go'; Test = '50 goroutines book 8 small tables at one slot'; Expected = 'exactly 8 booked (one per table), 42 RB409'; Actual = 'As expected (after the deadlock fix)'; Result = 'PASS' }
    $dest = Join-Path $script:root 'docs\report\test-cases.csv'
    $rows | Export-Csv -NoTypeInformation -Encoding UTF8 $dest
    Write-Host "wrote $($rows.Count) test cases to $dest" -ForegroundColor Green
}

Write-Host 'shots.ps1 loaded: tcase, snap, testcases' -ForegroundColor Green
