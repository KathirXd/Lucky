<#
    XD 2.0 - Lucky - lucky.ps1  (Phase 3: File & Folder Awareness)
    ---------------------------------------------------------------
    - Starts llama-cli ONCE, keeps it alive for the whole chat.
    - Raw byte-level stdout/stderr pumps (immune to "no newline yet"
      false-completion bugs).
    - Injects [LOCAL TIME] and a fresh [CURRENT MEMORY] on every
      ordinary chat message.
    - Detects PC-related questions -> runs pc_status.ps1 -> [PC_STATUS].
    - Detects filesystem questions -> runs the read-only tools in
      file_tools.ps1 (list / find / info / read / search) -> [FILE_STATUS].
      Detection is pure regex/keyword matching in PowerShell, never the
      LLM - deterministic, free, and it can't be talked into running
      something it shouldn't.
    - /remember, /memory, /forget handled entirely by the bridge.
      /clear, /regen, /read, /glob pass straight through to llama-cli.
#>

$ErrorActionPreference = "Stop"

# =====================================================================
# CONFIG
# =====================================================================
$ProjectDir       = "F:\XD2"
$LlamaExe         = Join-Path $ProjectDir "llama\llama-cli.exe"
$SystemPromptFile = Join-Path $ProjectDir "active_system_prompt.txt"
$PcStatusScript   = Join-Path $ProjectDir "pc_status.ps1"
$FileToolsScript  = Join-Path $ProjectDir "file_tools.ps1"
$MemoryFile       = Join-Path $ProjectDir "memory.json"

$ModelHf          = "Qwen/Qwen3-4B-GGUF:Q4_K_M"
$NGL              = "99"
$CtxSize          = "8192"

$IdleMsTurn         = 700
$IdleMsStartup      = 1500
$MaxWaitTurnSec     = 90
$MaxWaitStartupSec  = 240

$Debug = ($env:LUCKY_DEBUG -eq "1")

if (-not (Test-Path $FileToolsScript)) { throw "file_tools.ps1 not found at $FileToolsScript" }
. $FileToolsScript   # brings in Get-DirectoryListing, Find-ProjectFiles, Get-ProjectFileInfo,
                     # Read-ProjectTextFile, Search-ProjectTextFile, Resolve-SafePath, $AllowedRoot

# =====================================================================
# Raw byte-level stream pump
# =====================================================================
$pumpSource = @"
using System;
using System.IO;
using System.Text;
using System.Threading;

public class LuckyStreamPump
{
    private readonly StringBuilder _sb = new StringBuilder();
    private readonly object _lock = new object();
    private DateTime _lastData = DateTime.UtcNow;
    private volatile bool _running = false;

    public void Start(Stream stream)
    {
        _running = true;
        Thread t = new Thread(delegate()
        {
            byte[] buffer = new byte[4096];
            try
            {
                while (_running)
                {
                    int n = stream.Read(buffer, 0, buffer.Length);
                    if (n <= 0) { break; }
                    string chunk = Encoding.UTF8.GetString(buffer, 0, n);
                    lock (_lock)
                    {
                        _sb.Append(chunk);
                        _lastData = DateTime.UtcNow;
                    }
                }
            }
            catch { }
        });
        t.IsBackground = true;
        t.Start();
    }

    public string GetAndClear()
    {
        lock (_lock)
        {
            string s = _sb.ToString();
            _sb.Length = 0;
            return s;
        }
    }

    public bool HasData()
    {
        lock (_lock) { return _sb.Length > 0; }
    }

    public double MsSinceLastData()
    {
        lock (_lock) { return (DateTime.UtcNow - _lastData).TotalMilliseconds; }
    }
}
"@
Add-Type -TypeDefinition $pumpSource -Language CSharp

# =====================================================================
# Start llama-cli.exe ONCE
# =====================================================================
function Format-Arg([string]$a) {
    if ($a -match '\s') { '"' + ($a -replace '"','\"') + '"' } else { $a }
}

$argsArray = @(
    "-hf", $ModelHf,
    "-ngl", $NGL,
    "-c", $CtxSize,
    "--reasoning", "off",
    "--reasoning-budget", "0",
    "--log-disable",
    "--simple-io",
    "--system-prompt-file", $SystemPromptFile
)

if (-not (Test-Path $LlamaExe)) { throw "llama-cli.exe not found at $LlamaExe" }
if (-not (Test-Path $PcStatusScript)) { throw "pc_status.ps1 not found at $PcStatusScript" }

$psi = New-Object System.Diagnostics.ProcessStartInfo
$psi.FileName               = $LlamaExe
$psi.Arguments              = ($argsArray | ForEach-Object { Format-Arg $_ }) -join ' '
$psi.WorkingDirectory        = Split-Path $LlamaExe -Parent
$psi.RedirectStandardInput  = $true
$psi.RedirectStandardOutput = $true
$psi.RedirectStandardError  = $true
$psi.UseShellExecute        = $false
$psi.CreateNoWindow         = $true

$proc = New-Object System.Diagnostics.Process
$proc.StartInfo = $psi
[void]$proc.Start()

$outPump = New-Object LuckyStreamPump
$errPump = New-Object LuckyStreamPump
$outPump.Start($proc.StandardOutput.BaseStream)
$errPump.Start($proc.StandardError.BaseStream)

function Send-ToLlama([string]$text) {
    $bytes = [System.Text.Encoding]::UTF8.GetBytes($text + "`n")
    $stream = $proc.StandardInput.BaseStream
    $stream.Write($bytes, 0, $bytes.Length)
    $stream.Flush()
}

function Wait-ForResponse([double]$IdleMs, [int]$MaxWaitSec) {
    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    Start-Sleep -Milliseconds 150
    while ($true) {
        Start-Sleep -Milliseconds 100
        if ($outPump.HasData() -and $outPump.MsSinceLastData() -ge $IdleMs) { break }
        if ($sw.Elapsed.TotalSeconds -ge $MaxWaitSec) { break }
        if ($proc.HasExited) { break }
    }
    Start-Sleep -Milliseconds 50
    return $outPump.GetAndClear()
}

function Format-LuckyReply([string]$raw, [string]$sentLine) {
    if ([string]::IsNullOrWhiteSpace($raw)) { return $null }
    $text = $raw -replace "`r`n","`n" -replace "`r","`n"
    $lines = $text -split "`n"
    $clean = New-Object System.Collections.Generic.List[string]
    foreach ($ln in $lines) {
        $t = $ln.TrimEnd()
        if ($t -match '^\s*\[\s*Prompt:.*Generation:.*\]\s*$') { continue }
        if ($t.Trim() -eq '>') { continue }
        if ($sentLine -and $t.Trim() -eq $sentLine.Trim()) { continue }
        $clean.Add($t)
    }
    $result = ($clean -join "`n").Trim()
    $result = $result -replace '^>\s*', ''
    return $result
}

function ConvertTo-FlatBlock([string]$multiline) {
    if ([string]::IsNullOrWhiteSpace($multiline)) { return "" }
    $norm = $multiline -replace "`r`n","`n" -replace "`r","`n"
    $parts = $norm -split "`n" | Where-Object { $_.Trim() -ne '' } | ForEach-Object { $_.Trim() }
    return ($parts -join ' ¦ ')
}

# =====================================================================
# Memory (BOM-safe read/write, deterministic categorisation)
# =====================================================================
function Read-MemoryObj {
    $bytes = [System.IO.File]::ReadAllBytes($MemoryFile)
    if ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF) {
        $text = [System.Text.Encoding]::UTF8.GetString($bytes, 3, $bytes.Length - 3)
    } else {
        $text = [System.Text.Encoding]::UTF8.GetString($bytes)
    }
    $obj = $text | ConvertFrom-Json
    foreach ($cat in @('preferences','facts','projects','important_people')) {
        if (-not (Get-Member -InputObject $obj -Name $cat -MemberType NoteProperty)) {
            $obj | Add-Member -NotePropertyName $cat -NotePropertyValue @()
        }
        elseif ($null -eq $obj.$cat) {
            $obj.$cat = @()
        }
    }
    return $obj
}

function Save-MemoryObj($obj) {
    $json = $obj | ConvertTo-Json -Depth 12
    [System.IO.File]::WriteAllText($MemoryFile, $json, (New-Object System.Text.UTF8Encoding($false)))
}

function Get-MemoryCategory([string]$text) {
    if ($text -imatch '\b(prefer|preferred|preference|like|love|favou?rite|hate|dislike)\b') { return 'preferences' }
    if ($text -imatch '\b(project|working on|building|repo|repository|app called|app named)\b') { return 'projects' }
    if ($text -imatch '\bmy (friend|brother|sister|mom|mother|dad|father|wife|husband|girlfriend|boyfriend|colleague|coworker|boss|manager|teacher|mentor|partner)\b') { return 'important_people' }
    return 'facts'
}

function Remove-MatchingMemory($mem, [string]$needle) {
    $removed = 0
    foreach ($cat in @('preferences','facts','projects','important_people')) {
        $arr = @($mem.$cat)
        $filtered = @($arr | Where-Object { $_ -notmatch [regex]::Escape($needle) })
        $removed += ($arr.Count - $filtered.Count)
        $mem.$cat = $filtered
    }
    return $removed
}

function Get-MemoryFlat {
    $mem = Read-MemoryObj
    $parts = New-Object System.Collections.Generic.List[string]
    if ($mem.user -and $mem.user.name) { $parts.Add("name=" + $mem.user.name) }
    if (@($mem.preferences).Count -gt 0)      { $parts.Add("preferences: " + ((@($mem.preferences))      -join '; ')) }
    if (@($mem.facts).Count -gt 0)            { $parts.Add("facts: "       + ((@($mem.facts))            -join '; ')) }
    if (@($mem.projects).Count -gt 0)         { $parts.Add("projects: "    + ((@($mem.projects))         -join '; ')) }
    if (@($mem.important_people).Count -gt 0) { $parts.Add("people: "      + ((@($mem.important_people)) -join '; ')) }
    if ($parts.Count -eq 0) { return "none yet" }
    return ($parts -join ' | ')
}

# =====================================================================
# PC status
# =====================================================================
function Get-PcStatusFlat {
    $lines = New-Object System.Collections.Generic.List[string]
    & $PcStatusScript 6>&1 | ForEach-Object {
        if ($_ -is [System.Management.Automation.InformationRecord]) {
            $lines.Add([string]$_.MessageData)
        } else {
            $lines.Add([string]$_)
        }
    }
    $flat = $lines |
        Where-Object { $_.Trim() -ne '' -and $_ -notmatch '^=+$' } |
        ForEach-Object { $_.Trim() }
    return ($flat -join ' | ')
}

function Test-IsPcQuery([string]$msg) {
    $patterns = @(
        'storage','disk space','free space','\bdrive\b','\bram\b','memory usage','how much memory',
        '\bcpu\b','processor load','\bgpu\b','graphics card','\bvram\b','\bbattery\b','wi-?fi',
        'internet','\buptime\b','windows version','which windows',
        'struggl','overheat','running hot','pc status','system status',
        '\bspecs\b','\bhardware\b','\bperformance\b','how.?s my pc','is my pc','check my pc'
    )
    foreach ($p in $patterns) { if ($msg -imatch $p) { return $true } }
    return $false
}

function Get-TimeBlock {
    $now = Get-Date
    return "[LOCAL TIME: " + $now.ToString("dddd, dd MMMM yyyy") + " " + $now.ToString("hh:mm tt") + "]"
}

# =====================================================================
# Approximate context tracking - auto-/clear before hitting the hard
# limit instead of crashing. This is an ESTIMATE (chars/3.5), not real
# tokenization, so the safety margin below is intentionally generous.
# =====================================================================
$CtxSizeInt            = [int]$CtxSize
$ContextSafetyFraction = 0.70                                          # auto-clear at 90% of context
$ReservedReplyTokens   = 600                                           # headroom reserved for the reply itself
$MaxSafeTokens = [math]::Floor($CtxSizeInt * $ContextSafetyFraction)

function Get-ApproxTokenCount([string]$text) {
    if ([string]::IsNullOrEmpty($text)) { return 0 }
    return [math]::Ceiling($text.Length / 3.5)
}

$systemPromptTextForEstimate = ""
if (Test-Path $SystemPromptFile) { $systemPromptTextForEstimate = Get-Content -Path $SystemPromptFile -Raw }
$ApproxBaselineTokens = Get-ApproxTokenCount $systemPromptTextForEstimate
$ApproxTokensUsed     = $ApproxBaselineTokens

# =====================================================================
# Filesystem intent detection (pure regex/keyword - never the LLM)
# =====================================================================
$ExtensionMap = @{
    'javascript' = '*.js,*.jsx'; 'js' = '*.js'; 'jsx' = '*.jsx'
    'typescript' = '*.ts,*.tsx'; 'ts' = '*.ts'; 'tsx' = '*.tsx'
    'react'      = '*.jsx,*.tsx'
    'powershell' = '*.ps1'; 'ps1' = '*.ps1'
    'json'       = '*.json'; 'html' = '*.html'; 'css' = '*.css'
    'markdown'   = '*.md';  'text' = '*.txt'; 'csv' = '*.csv'; 'xml' = '*.xml'
    'python'     = '*.py'
}

function Get-FileIntent([string]$msg) {
    $m = $msg.Trim()

    # Windows path, including bare drive roots such as D:
    $winPathM = [regex]::Match(
        $m,
        '(?i)\b([A-Za-z]:)(\\[^\s"'']*)?'
    )

    $bareFileM = [regex]::Match(
        $m,
        '\b[\w\-]+\.(txt|ps1|json|js|jsx|ts|tsx|html|css|md|csv|xml)\b'
    )

    $winPath = $null

    if ($winPathM.Success) {
        $winPath = $winPathM.Value.TrimEnd('.', ',', '?', '!', ':')
        
        # Restore bare drive colon: D: -> D:\
        if ($winPath -match '^[A-Za-z]$') {
            $winPath = "$winPath`:\"
        }
        elseif ($winPath -match '^[A-Za-z]:$') {
            $winPath = "$winPath\"
        }
    }

    $bareFile = $null

    if ($bareFileM.Success) {
        $bareFile = $bareFileM.Value
    }

    # -------------------------------------------------------------
    # Determine file target
    # -------------------------------------------------------------

    $fileTarget = $null

    if ($bareFile) {
        $fileTarget = $bareFile
    }
    elseif ($winPath -and ($winPath -match '\.\w{1,5}$')) {
        $fileTarget = $winPath
    }

    # -------------------------------------------------------------
    # Determine folder target
    # -------------------------------------------------------------

    $dirTarget = $null

    if ($winPath -and ($winPath -notmatch '\.\w{1,5}$')) {
        $dirTarget = $winPath
    }

    # -------------------------------------------------------------
    # 1) Search inside file
    # -------------------------------------------------------------

    if ($m -imatch 'search\s+(?<file>\S+)\s+for\s+"?(?<term>[^"]+?)"?\s*$') {
        return @{
            Kind   = 'search'
            Target = $Matches['file']
            Term   = $Matches['term'].Trim()
        }
    }

    if ($m -imatch 'find\s+"(?<term>[^"]+)"\s+in\s+(?<file>\S+)') {
        return @{
            Kind   = 'search'
            Target = $Matches['file']
            Term   = $Matches['term'].Trim()
        }
    }

    if ($m -imatch '(does|is)\s+(?<file>\S+)\s+(contain|have)\s+"?(?<term>[^"]+?)"?\s*$') {
        return @{
            Kind   = 'search'
            Target = $Matches['file']
            Term   = $Matches['term'].Trim()
        }
    }

    # -------------------------------------------------------------
    # 2) File info
    # -------------------------------------------------------------

    if (
        $fileTarget -and
        (
            $m -imatch '(how (big|large) is|size of|when was .*(modified|created|changed)|tell me about)'
        )
    ) {
        return @{
            Kind   = 'info'
            Target = $fileTarget
        }
    }

    # -------------------------------------------------------------
    # 3) Read file
    # -------------------------------------------------------------

    if (
        $fileTarget -and
        (
            $m -imatch '^(read|show me|display|open|cat|print)\b|what.?s inside'
        )
    ) {
        return @{
            Kind   = 'read'
            Target = $fileTarget
        }
    }

    # -------------------------------------------------------------
    # 4) Find files by pattern
    # -------------------------------------------------------------

    if (
        $m -imatch '\bfind\b.*\bfiles?\b' -or
        $m -imatch '\bfiles?\s+named\b' -or
        $m -imatch '\*\.\w+'
    ) {

        $explicitPatterns = [regex]::Matches($m, '\*\.\w+')

        if ($explicitPatterns.Count -gt 0) {

            $pattern = (
                $explicitPatterns |
                ForEach-Object { $_.Value }
            ) -join ','

            return @{
                Kind    = 'find'
                Pattern = $pattern
                Target  = $dirTarget
            }
        }

        foreach ($key in $ExtensionMap.Keys) {

            if ($m -imatch "\b$key\b") {

                return @{
                    Kind    = 'find'
                    Pattern = $ExtensionMap[$key]
                    Target  = $dirTarget
                }
            }
        }

        if ($m -imatch 'files?\s+named\s+(?<name>\S+)') {

            return @{
                Kind    = 'find'
                Pattern = "*$($Matches['name'])*"
                Target  = $dirTarget
            }
        }

        return @{
            Kind    = 'find'
            Pattern = '*.*'
            Target  = $dirTarget
        }
    }

    # -------------------------------------------------------------
    # 5) List directory
    # -------------------------------------------------------------

    if (
        $m -imatch "what.?s in\b|what.?s inside\b|^list\b|show me\b|contents of\b"
    ) {

        if ($dirTarget) {
            return @{
                Kind   = 'list'
                Target = $dirTarget
            }
        }

        if (
            $m -imatch '\bfolder\b|\bdirectory\b|\bxd2\b|\bproject\b'
        ) {
            return @{
                Kind   = 'list'
                Target = $DefaultRoot
            }
        }
    }

    # -------------------------------------------------------------
    # 6) How many files
    # -------------------------------------------------------------

    if ($m -imatch '\bhow many files\b') {

        return @{
            Kind   = 'list'
            Target = if ($dirTarget) {
                $dirTarget
            }
            else {
                $DefaultRoot
            }
        }
    }

    return $null
}

function Invoke-FileIntent($intent) {
    switch ($intent.Kind) {
        'list'   { return (Get-DirectoryListing -Path $intent.Target) }
        'find'   { return (Find-ProjectFiles -Pattern $intent.Pattern -Path $intent.Target) }
        'info'   { return (Get-ProjectFileInfo -Path $intent.Target) }
        'read'   { return (Read-ProjectTextFile -Path $intent.Target) }
        'search' { return (Search-ProjectTextFile -Path $intent.Target -Term $intent.Term) }
        default  { return $null }
    }
}

# =====================================================================
# Startup: drain llama-cli's own banner / model-load output
# =====================================================================
Write-Host "Loading model..." -ForegroundColor Yellow
$startupRaw = Wait-ForResponse -IdleMs $IdleMsStartup -MaxWaitSec $MaxWaitStartupSec
if ($Debug) { Write-Host "`n[DEBUG raw startup]`n$startupRaw`n" -ForegroundColor DarkGray }
$startupClean = Format-LuckyReply $startupRaw $null
if ($startupClean) { Write-Host $startupClean }
Write-Host ""
Write-Host "local tools: PC Status + Time/Date + Live Memory + File Awareness (read-only, D:\ + F:\)" -ForegroundColor DarkGray
Write-Host "bridge commands: /remember <text>  /memory  /forget <text>  /clear  /exit" -ForegroundColor DarkGray
Write-Host ""

# =====================================================================
# Main loop
# =====================================================================
try {
    while ($true) {
        Write-Host "You > " -NoNewline -ForegroundColor Cyan
        $userInput = Read-Host
        if ($null -eq $userInput) { continue }
        $trimmed = $userInput.Trim()
        if ($trimmed -eq '') { continue }

        # ---------- bridge-owned commands (no LLM round trip) ----------
        if ($trimmed -match '^/remember\s+(.+)$') {
            $fact = $Matches[1].Trim()
            $mem  = Read-MemoryObj
            $cat  = Get-MemoryCategory $fact
            $mem.$cat = @(@($mem.$cat) + $fact)
            Save-MemoryObj $mem
            Write-Host "[Lucky] Got it, I'll remember that." -ForegroundColor Green
            if ($Debug) { Write-Host "[DEBUG] categorised as: $cat" -ForegroundColor DarkGray }
            continue
        }
        elseif ($trimmed -match '^/forget\s+(.+)$') {
            $needle = $Matches[1].Trim()
            $mem = Read-MemoryObj
            $removed = Remove-MatchingMemory $mem $needle
            Save-MemoryObj $mem
            Write-Host "[Lucky] Forgot $removed matching item(s)." -ForegroundColor Green
            continue
        }
        elseif ($trimmed -eq '/memory') {
            $mem = Read-MemoryObj
            Write-Host "---- Lucky's memory ----" -ForegroundColor Yellow
            Write-Host ("User:       " + $mem.user.name)
            Write-Host ("Preferences:" + ((@($mem.preferences))      -join '; '))
            Write-Host ("Facts:      " + ((@($mem.facts))            -join '; '))
            Write-Host ("Projects:   " + ((@($mem.projects))         -join '; '))
            Write-Host ("People:     " + ((@($mem.important_people)) -join '; '))
            Write-Host "-------------------------" -ForegroundColor Yellow
            continue
        }
        elseif ($trimmed -eq '/exit') {
            Send-ToLlama '/exit'
            Start-Sleep -Milliseconds 300
            break
        }
        else {
            # /clear, /regen, /read <file>, /glob <pattern>, or plain chat -> goes to llama-cli below
        }

        # ---------- build the message actually sent to Qwen ----------
        $timeBlock = Get-TimeBlock

        if ($trimmed.StartsWith('/')) {
            # native llama-cli command - pass through untouched, no augmentation
            $sendLine = $trimmed
        }
        else {
            $memFlat  = Get-MemoryFlat
            $fileIntent = Get-FileIntent $trimmed
            if ($Debug -and $fileIntent) { Write-Host "[DEBUG file-intent] $($fileIntent | Out-String)" -ForegroundColor DarkGray }

            if ($fileIntent) {
                $fileRaw  = Invoke-FileIntent $fileIntent
                $fileFlat = ConvertTo-FlatBlock $fileRaw
                $sendLine = "$timeBlock [CURRENT MEMORY: $memFlat] [FILE_STATUS: $fileFlat] User: $trimmed"
            }
            elseif (Test-IsPcQuery $trimmed) {
                $pcFlat = Get-PcStatusFlat
                $sendLine = "$timeBlock [CURRENT MEMORY: $memFlat] [PC_STATUS: $pcFlat] User: $trimmed"
            }
            else {
                $sendLine = "$timeBlock [CURRENT MEMORY: $memFlat] User: $trimmed"
            }
        }

        # ---------- context safety net: auto-/clear before hitting the hard limit ----------
        $estIn = Get-ApproxTokenCount $sendLine
        if ($Debug) { Write-Host "[DEBUG context] ~$ApproxTokensUsed used + ~$estIn incoming, safe limit ~$MaxSafeTokens / $CtxSizeInt" -ForegroundColor DarkGray }
       if (($ApproxTokensUsed + $estIn + $ReservedReplyTokens) -gt $MaxSafeTokens) {
    Send-ToLlama '/clear'
    Wait-ForResponse -IdleMs $IdleMsTurn -MaxWaitSec 15 | Out-Null
    $ApproxTokensUsed = $ApproxBaselineTokens
}

        Send-ToLlama $sendLine
        $raw = Wait-ForResponse -IdleMs $IdleMsTurn -MaxWaitSec $MaxWaitTurnSec
        if ($Debug) { Write-Host "`n[DEBUG raw]`n$raw`n" -ForegroundColor DarkGray }
        $reply = Format-LuckyReply $raw $sendLine
        $ApproxTokensUsed += $estIn + (Get-ApproxTokenCount $reply)

        if ($trimmed -eq '/clear') { $ApproxTokensUsed = $ApproxBaselineTokens }

        if ($reply) {
            Write-Host "Lucky > " -NoNewline -ForegroundColor Magenta
            Write-Host $reply
        } else {
            Write-Host "[Lucky] (no output captured - try again, or run with `$env:LUCKY_DEBUG=`"1`" to see raw stream)" -ForegroundColor DarkYellow
        }
        Write-Host ""
    }
}
finally {
    if ($proc -and -not $proc.HasExited) {
        try { $proc.Kill() } catch { }
    }
    Write-Host ""
    Write-Host "Lucky signing off." -ForegroundColor Yellow
}