<#
    XD 2.0 - Lucky - start.ps1
    ---------------------------------------------------------------
    1. Loads personality.txt
    2. Loads memory.json (BOM-safe)
    3. Adds current Windows date/time
    4. Builds active_system_prompt.txt (personality + memory + the
       LIVE DATA PROTOCOL that teaches Qwen how to read the
       [LOCAL TIME] / [PC_STATUS] tags lucky.ps1 injects per message)
    5. Hands off to lucky.ps1, which starts and owns the single,
       persistent llama-cli.exe process for the rest of the session.
#>
Clear-Host 
$ErrorActionPreference = "Stop"

$ProjectDir      = "F:\XD2"
$PersonalityFile = Join-Path $ProjectDir "personality.txt"
$MemoryFile      = Join-Path $ProjectDir "memory.json"
$SystemPromptOut = Join-Path $ProjectDir "active_system_prompt.txt"
$LuckyScript     = Join-Path $ProjectDir "lucky.ps1"

Set-Location $ProjectDir

Write-Host ""
Write-Host "██╗     ██╗   ██╗ ██████╗██╗  ██╗██╗   ██╗" -ForegroundColor Cyan
Write-Host "██║     ██║   ██║██╔════╝██║ ██╔╝╚██╗ ██╔╝" -ForegroundColor Cyan
Write-Host "██║     ██║   ██║██║     █████╔╝  ╚████╔╝ " -ForegroundColor Cyan
Write-Host "██║     ██║   ██║██║     ██╔═██╗   ╚██╔╝  " -ForegroundColor Cyan
Write-Host "███████╗╚██████╔╝╚██████╗██║  ██╗   ██║   " -ForegroundColor Cyan
Write-Host "╚══════╝ ╚═════╝  ╚═════╝╚═╝  ╚═╝   ╚═╝   " -ForegroundColor Cyan

Write-Host ""
Write-Host "                    XD 2.0" -ForegroundColor White
Write-Host "             Your Local AI Assistant" -ForegroundColor DarkCyan
Write-Host ""
Write-Host "              Lucky is starting..." -ForegroundColor Green
Write-Host ""


# ---- 1. personality ----
if (-not (Test-Path $PersonalityFile)) {
    throw "personality.txt not found at $PersonalityFile"
}
$personalityRaw = Get-Content -Path $PersonalityFile -Raw -Encoding UTF8

# ---- 2. memory (BOM-safe) ----
function Read-MemoryTextBomSafe {
    param([string]$Path)
    if (-not (Test-Path $Path)) {
        $seedId = -join ((48..57) + (97..122) | Get-Random -Count 6 | ForEach-Object { [char]$_ })
        $seed = [ordered]@{
            id               = $seedId
            user             = [ordered]@{ name = "Kathiravan" }
            preferences      = @()
            facts            = @()
            projects         = @()
            important_people = @()
        }
        ($seed | ConvertTo-Json -Depth 10) | Set-Content -Path $Path -Encoding UTF8
    }
    $bytes = [System.IO.File]::ReadAllBytes($Path)
    if ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF) {
        return [System.Text.Encoding]::UTF8.GetString($bytes, 3, $bytes.Length - 3)
    }
    return [System.Text.Encoding]::UTF8.GetString($bytes)
}

$memoryText = Read-MemoryTextBomSafe -Path $MemoryFile
try {
    $memoryObj = $memoryText | ConvertFrom-Json

    # IMPORTANT: only ever serialize the lightweight categories the bridge
    # actually uses (same ones /memory and [CURRENT MEMORY] show). Never
    # dump the raw parsed object - if memory.json ever grows extra fields
    # (like a big reference profile), blindly serializing it here would
    # bloat the system prompt and can blow past the context window before
    # the conversation even starts.
    $userObj = $memoryObj.user
    if (-not $userObj) { $userObj = [ordered]@{ name = "Kathiravan" } }

    $memoryLite = [ordered]@{
        user              = $userObj
        preferences       = @($memoryObj.preferences)
        facts             = @($memoryObj.facts)
        projects          = @($memoryObj.projects)
        important_people  = @($memoryObj.important_people)
    }
    $memoryPretty = $memoryLite | ConvertTo-Json -Depth 6
}
catch {
    Write-Host "[Lucky] memory.json could not be parsed as JSON - using raw file text instead." -ForegroundColor DarkYellow
    $memoryPretty = $memoryText
}

# ---- 3. current date/time ----
$now      = Get-Date
$dateLine = $now.ToString("dddd, dd MMMM yyyy")
$timeLine = $now.ToString("hh:mm tt")

# ---- 4. build active_system_prompt.txt ----
$protocol = @"
=== LIVE DATA PROTOCOL (this is not part of your personality - it is how real-time facts reach you) ===
Some user messages will contain machine-generated tags, inserted by the PowerShell bridge, not typed by
Kathiravan. Treat them as ground truth and never contradict them:

[LOCAL TIME: <weekday, date, time>]
  - The REAL current date/time, refreshed on every single message. Always trust this over any guess.

[PC_STATUS: field | field | field ...]
  - Present ONLY when Kathiravan asked something PC/hardware/storage/battery/network related.
  - Contains REAL, read-only data measured from his PC seconds before this message was sent.
  - Use ONLY the exact numbers given here. Never invent, guess, or round dramatically, and never state
    a hardware detail that is not present in this block.
  - If he asks a PC/hardware question and there is NO [PC_STATUS] block in the message, say you don't
    have fresh data for that right now instead of making something up.

[CURRENT MEMORY: name=... | preferences: ... | facts: ... | projects: ... | people: ...]
  - Present on every ordinary chat message. This is a LIVE snapshot read straight from disk at the
    moment the message was sent - it is always more current than the PERSISTENT MEMORY section below
    (which was only a snapshot taken when this session started). If the two ever disagree, trust
    [CURRENT MEMORY], since it reflects anything remembered or forgotten since then.
  - Answer naturally using this information (e.g. "You prefer dark themes"). Do not say things like
    "according to CURRENT MEMORY" or mention the tag itself, unless Kathiravan explicitly asks how you
    know something.

[FILE_STATUS: ...]
  - Present ONLY when Kathiravan asked about files or folders (listing a folder, finding files by
    type, file size/dates, reading a file, or searching inside a file).
  - Contains REAL, read-only output from a PowerShell tool restricted to F:\XD2 and its subfolders.
    Entries are separated by " ¦ " where the original tool output had a line break.
  - Use ONLY the exact names, sizes, dates, paths, and content shown here. Never invent a file, a
    size, a date, or file content that is not present in this block.
  - If the block starts with ACCESS_DENIED, NOT_FOUND, UNSUPPORTED_TYPE, or NO_MATCHES, say so plainly
    instead of guessing what might be there.
  - Kathiravan's file tools are READ-ONLY. You have no ability to create, edit, delete, rename, move,
    or run any file, and no ability to change system settings. If asked to do any of that, say clearly
    that you can only look at files right now, not change them.
  - If Kathiravan asks a file/folder question and there is NO [FILE_STATUS] block in the message, say
    you don't have that information right now instead of making something up.

Never mention any of these tags to Kathiravan directly - just use the information naturally in your reply.
"@

$systemPrompt = @"
$personalityRaw

=== PERSISTENT MEMORY (facts you already know about Kathiravan; use naturally, don't recite as a raw list unless asked) ===
$memoryPretty

$protocol

=== SESSION START ===
Date: $dateLine
Time: $timeLine
"@

Set-Content -Path $SystemPromptOut -Value $systemPrompt -Encoding UTF8

$sizeKb = [math]::Round((Get-Item $SystemPromptOut).Length / 1KB, 1)
Write-Host "System prompt built ($sizeKb KB) -> $SystemPromptOut" -ForegroundColor DarkGray
Write-Host ""

# ---- 5. hand off to the persistent bridge ----
if (-not (Test-Path $LuckyScript)) {
    throw "lucky.ps1 not found at $LuckyScript"
}
& $LuckyScript