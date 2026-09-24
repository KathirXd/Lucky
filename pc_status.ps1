# ============================================================
# XD 2.0 - Lucky Local PC Status
# READ-ONLY
# ============================================================

$now = Get-Date
$hour = $now.Hour

# ------------------------------------------------------------
# TIME PERIOD
# ------------------------------------------------------------

if ($hour -ge 5 -and $hour -lt 12) {
    $period = "morning"
}
elseif ($hour -ge 12 -and $hour -lt 17) {
    $period = "afternoon"
}
elseif ($hour -ge 17 -and $hour -lt 21) {
    $period = "evening"
}
else {
    $period = "night"
}

# ------------------------------------------------------------
# CPU
# ------------------------------------------------------------

$cpu = (Get-Counter '\Processor(_Total)\% Processor Time').CounterSamples.CookedValue
$cpu = [math]::Round($cpu, 1)

# ------------------------------------------------------------
# RAM
# ------------------------------------------------------------

$os = Get-CimInstance Win32_OperatingSystem

$totalRAM = [math]::Round(
    $os.TotalVisibleMemorySize / 1MB,
    2
)

$freeRAM = [math]::Round(
    $os.FreePhysicalMemory / 1MB,
    2
)

$usedRAM = [math]::Round(
    $totalRAM - $freeRAM,
    2
)

$ramPercent = [math]::Round(
    ($usedRAM / $totalRAM) * 100,
    1
)

# ------------------------------------------------------------
# GPU
# ------------------------------------------------------------

$gpu = Get-CimInstance Win32_VideoController |
    Where-Object {
        $_.Name -match "NVIDIA"
    } |
    Select-Object -First 1

if ($gpu) {
    $gpuName = $gpu.Name
}
else {
    $gpuName = "NVIDIA GPU not detected"
}

if ($gpu -and $gpu.AdapterRAM) {
    $vramGB = [math]::Round(
        $gpu.AdapterRAM / 1GB,
        2
    )
}
else {
    $vramGB = 0
}

# ------------------------------------------------------------
# DISKS
# ------------------------------------------------------------

$disks = Get-PSDrive -PSProvider FileSystem |
    Where-Object {
        $_.Free -ne $null
    } |
    ForEach-Object {

        $freeGB = [math]::Round(
            $_.Free / 1GB,
            1
        )

        "$($_.Name): $freeGB GB free"
    }

# ------------------------------------------------------------
# BATTERY
# ------------------------------------------------------------

$battery = Get-CimInstance Win32_Battery `
    -ErrorAction SilentlyContinue

if ($battery) {
    $batteryStatus = "$($battery.EstimatedChargeRemaining)%"
}
else {
    $batteryStatus = "AC / no battery"
}

# ------------------------------------------------------------
# WIFI
# ------------------------------------------------------------

$wifi = Get-NetAdapter `
    -ErrorAction SilentlyContinue |
    Where-Object {
        $_.Name -match "Wi-Fi|WiFi|Wireless"
    } |
    Select-Object -First 1

if ($wifi) {
    $wifiStatus = $wifi.Status
}
else {
    $wifiStatus = "Not detected"
}

# ------------------------------------------------------------
# INTERNET
# ------------------------------------------------------------

try {

    $internet = Test-Connection `
        -ComputerName "1.1.1.1" `
        -Count 1 `
        -Quiet `
        -ErrorAction Stop

    if ($internet) {
        $internetStatus = "Connected"
    }
    else {
        $internetStatus = "Offline"
    }

}
catch {

    $internetStatus = "Offline"

}

# ------------------------------------------------------------
# WINDOWS
# ------------------------------------------------------------

$windows = Get-CimInstance Win32_OperatingSystem

$windowsVersion = $windows.Caption

# ------------------------------------------------------------
# UPTIME
# ------------------------------------------------------------

$bootTime = $windows.LastBootUpTime

$uptime = (Get-Date) - $bootTime

$uptimeText = "{0}d {1}h {2}m" -f `
    $uptime.Days,
    $uptime.Hours,
    $uptime.Minutes

# ============================================================
# OUTPUT
# ============================================================

Write-Host ""

Write-Host "========================================" -ForegroundColor Cyan
Write-Host "          LUCKY - PC STATUS             " -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan

Write-Host ""

Write-Host "TIME" -ForegroundColor Yellow

Write-Host ("  Date:   {0}" -f $now.ToString("dddd, dd MMMM yyyy"))
Write-Host ("  Time:   {0}" -f $now.ToString("hh:mm:ss tt"))
Write-Host ("  Period: {0}" -f $period)

Write-Host ""

Write-Host "HARDWARE" -ForegroundColor Yellow

Write-Host ("  CPU:    {0} percent" -f $cpu)
Write-Host ("  RAM:    {0} / {1} GB ({2} percent)" -f $usedRAM, $totalRAM, $ramPercent)
Write-Host ("  GPU:    {0}" -f $gpuName)
Write-Host ("  VRAM:   {0} GB" -f $vramGB)

Write-Host ""

Write-Host "STORAGE" -ForegroundColor Yellow

foreach ($disk in $disks) {
    Write-Host ("  {0}" -f $disk)
}

Write-Host ""

Write-Host "SYSTEM" -ForegroundColor Yellow

Write-Host ("  Battery:   {0}" -f $batteryStatus)
Write-Host ("  Wi-Fi:     {0}" -f $wifiStatus)
Write-Host ("  Internet:  {0}" -f $internetStatus)
Write-Host ("  Windows:   {0}" -f $windowsVersion)
Write-Host ("  Uptime:    {0}" -f $uptimeText)

Write-Host ""

Write-Host "Read-only check complete." -ForegroundColor Green

Write-Host ""