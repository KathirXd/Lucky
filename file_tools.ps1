<#
    XD 2.0 - Lucky - file_tools.ps1
    ---------------------------------------------------------------
    READ-ONLY filesystem tools.

    Allowed:
        D:\
        F:\

    Blocked:
        C:\
        E:\
        G:\
        Network/UNC paths

    No delete, create, rename, move, execute, or write capability.

    Meant to be dot-sourced by lucky.ps1:
        . "F:\XD2\file_tools.ps1"
#>

# =====================================================================
# Configuration
# =====================================================================

$AllowedRoots = @(
    "D:\",
    "F:\"
)

# Relative paths default to the XD 2.0 project
$DefaultRoot = "F:\XD2"

$MaxListEntries        = 30
$MaxReadChars          = 4000
$MaxSearchMatches      = 15
$AllowedTextExtensions = @(
    '.txt',
    '.ps1',
    '.json',
    '.js',
    '.jsx',
    '.ts',
    '.tsx',
    '.html',
    '.css',
    '.md',
    '.csv',
    '.xml'
)

# =====================================================================
# Path safety
# Every filesystem function goes through this gate.
# Only D:\ and F:\ are allowed.
# =====================================================================

function Resolve-SafePath {
    param(
        [string]$InputPath
    )

    if ([string]::IsNullOrWhiteSpace($InputPath)) {
        return $null
    }

    $candidate = $InputPath.Trim().Trim('"').Trim("'")

    # Relative path -> default to F:\XD2
    if (
        $candidate -notmatch '^[A-Za-z]:\\' -and
        $candidate -notmatch '^\\\\'
    ) {
        $candidate = Join-Path $DefaultRoot $candidate
    }

    try {
        $resolved = [System.IO.Path]::GetFullPath($candidate)
    }
    catch {
        return $null
    }

    # Explicitly reject UNC/network paths
    if ($resolved -match '^\\\\') {
        return $null
    }

    # Check whether the path belongs to D:\ or F:\
    foreach ($root in $AllowedRoots) {
        $rootFull = [System.IO.Path]::GetFullPath($root)

        $isRoot = $resolved.Equals(
            $rootFull,
            [System.StringComparison]::OrdinalIgnoreCase
        )

        $isChild = $resolved.StartsWith(
            $rootFull,
            [System.StringComparison]::OrdinalIgnoreCase
        )

        if ($isRoot -or $isChild) {
            return $resolved
        }
    }

    return $null
}

# =====================================================================
# Helper
# =====================================================================

function Format-FileSize {
    param(
        [long]$Bytes
    )

    if ($Bytes -ge 1MB) {
        return "{0:N1} MB" -f ($Bytes / 1MB)
    }
    elseif ($Bytes -ge 1KB) {
        return "{0:N1} KB" -f ($Bytes / 1KB)
    }
    else {
        return "$Bytes B"
    }
}

# =====================================================================
# TOOL 1 - List directory
# =====================================================================

function Get-DirectoryListing {
    param(
        [string]$Path
    )

    $safe = Resolve-SafePath $Path

    if (-not $safe) {
        return "ACCESS_DENIED: only D:\ and F:\ paths are allowed."
    }

    if (-not (Test-Path -LiteralPath $safe -PathType Container)) {
        return "NOT_FOUND: '$safe' is not a folder."
    }

    $items = Get-ChildItem `
        -LiteralPath $safe `
        -Force `
        -ErrorAction SilentlyContinue |
        Where-Object {
            $_.Name -notmatch '^\.'
        } |
        Sort-Object `
            @{ Expression = { $_.PSIsContainer }; Descending = $true },
            Name

    $total = @($items).Count
    $shown = $items | Select-Object -First $MaxListEntries

    $lines = New-Object System.Collections.Generic.List[string]

    $lines.Add("PATH: $safe")

    foreach ($it in $shown) {

        if ($it.PSIsContainer) {
            $lines.Add("[DIR] $($it.Name)")
        }
        else {
            $lines.Add(
                "[FILE] $($it.Name) | $(Format-FileSize $it.Length) | modified $($it.LastWriteTime.ToString('yyyy-MM-dd HH:mm'))"
            )
        }
    }

    if ($total -gt $MaxListEntries) {
        $lines.Add(
            "... and $($total - $MaxListEntries) more item(s) not shown"
        )
    }

    $lines.Add("TOTAL_ITEMS: $total")

    return ($lines -join "`n")
}

# =====================================================================
# TOOL 2 - Find files by pattern
# =====================================================================

function Find-ProjectFiles {
    param(
        [string]$Pattern = '*.*',
        [string]$Path
    )

    $safe = Resolve-SafePath $Path

    # If no valid path was supplied, search F:\XD2
    if (-not $safe) {
        $safe = Resolve-SafePath $DefaultRoot
    }

    if (-not $safe) {
        return "ACCESS_DENIED: only D:\ and F:\ paths are allowed."
    }

    if (-not (Test-Path -LiteralPath $safe -PathType Container)) {
        return "NOT_FOUND: '$safe' is not a folder."
    }

    $patterns = $Pattern -split ',' |
        ForEach-Object {
            $_.Trim()
        } |
        Where-Object {
            $_ -ne ''
        }

    if (@($patterns).Count -eq 0) {
        $patterns = @('*.*')
    }

    $results = New-Object System.Collections.Generic.List[System.IO.FileInfo]

    foreach ($p in $patterns) {

        Get-ChildItem `
            -LiteralPath $safe `
            -Recurse `
            -File `
            -Filter $p `
            -Depth 6 `
            -ErrorAction SilentlyContinue |
            ForEach-Object {
                $results.Add($_)
            }
    }

    $unique = $results | Sort-Object FullName -Unique

    $total = @($unique).Count
    $shown = $unique | Select-Object -First $MaxListEntries

    $lines = New-Object System.Collections.Generic.List[string]

    $lines.Add("SEARCH_ROOT: $safe")
    $lines.Add("PATTERN: $($patterns -join ', ')")

    foreach ($f in $shown) {

        # Show relative path when inside F:\XD2
        if ($f.FullName.StartsWith(
            $DefaultRoot,
            [System.StringComparison]::OrdinalIgnoreCase
        )) {
            $rel = $f.FullName.Substring($DefaultRoot.Length).TrimStart('\')
        }
        else {
            $rel = $f.FullName
        }

        $lines.Add(
            "$rel | $(Format-FileSize $f.Length)"
        )
    }

    if ($total -gt $MaxListEntries) {
        $lines.Add(
            "... and $($total - $MaxListEntries) more not shown"
        )
    }

    $lines.Add("TOTAL_MATCHES: $total")

    return ($lines -join "`n")
}

# =====================================================================
# TOOL 3 - File info
# =====================================================================

function Get-ProjectFileInfo {
    param(
        [string]$Path
    )

    $safe = Resolve-SafePath $Path

    if (-not $safe) {
        return "ACCESS_DENIED: only D:\ and F:\ paths are allowed."
    }

    if (-not (Test-Path -LiteralPath $safe -PathType Leaf)) {
        return "NOT_FOUND: '$safe' is not a file."
    }

    $fi = Get-Item -LiteralPath $safe

    $lines = @(
        "FULL_PATH: $($fi.FullName)",
        "NAME: $($fi.Name)",
        "EXTENSION: $($fi.Extension)",
        "SIZE: $(Format-FileSize $fi.Length) ($($fi.Length) bytes)",
        "CREATED: $($fi.CreationTime.ToString('yyyy-MM-dd HH:mm'))",
        "MODIFIED: $($fi.LastWriteTime.ToString('yyyy-MM-dd HH:mm'))"
    )

    return ($lines -join "`n")
}

# =====================================================================
# TOOL 4 - Read text file
# =====================================================================

function Read-ProjectTextFile {
    param(
        [string]$Path
    )

    $safe = Resolve-SafePath $Path

    if (-not $safe) {
        return "ACCESS_DENIED: only D:\ and F:\ paths are allowed."
    }

    if (-not (Test-Path -LiteralPath $safe -PathType Leaf)) {
        return "NOT_FOUND: '$safe' is not a file."
    }

    $ext = [System.IO.Path]::GetExtension($safe).ToLower()

    if ($AllowedTextExtensions -notcontains $ext) {
        return "UNSUPPORTED_TYPE: '$ext' files are not readable by this tool (text files only)."
    }

    $bytes = [System.IO.File]::ReadAllBytes($safe)

    # UTF-8 BOM
    if (
        $bytes.Length -ge 3 -and
        $bytes[0] -eq 0xEF -and
        $bytes[1] -eq 0xBB -and
        $bytes[2] -eq 0xBF
    ) {
        $text = [System.Text.Encoding]::UTF8.GetString(
            $bytes,
            3,
            $bytes.Length - 3
        )
    }
    else {
        $text = [System.Text.Encoding]::UTF8.GetString($bytes)
    }

    $truncated = $false

    if ($text.Length -gt $MaxReadChars) {
        $text = $text.Substring(0, $MaxReadChars)
        $truncated = $true
    }

    $out = "FILE: $safe`nCONTENT:`n$text"

    if ($truncated) {
        $out += "`n[TRUNCATED - file is longer than $MaxReadChars characters shown]"
    }

    return $out
}

# =====================================================================
# TOOL 5 - Search inside a text file
# =====================================================================

function Search-ProjectTextFile {
    param(
        [string]$Path,
        [string]$Term
    )

    $safe = Resolve-SafePath $Path

    if (-not $safe) {
        return "ACCESS_DENIED: only D:\ and F:\ paths are allowed."
    }

    if (-not (Test-Path -LiteralPath $safe -PathType Leaf)) {
        return "NOT_FOUND: '$safe' is not a file."
    }

    $ext = [System.IO.Path]::GetExtension($safe).ToLower()

    if ($AllowedTextExtensions -notcontains $ext) {
        return "UNSUPPORTED_TYPE: '$ext' files are not searchable by this tool (text files only)."
    }

    if ([string]::IsNullOrWhiteSpace($Term)) {
        return "NO_SEARCH_TERM: no search term was given."
    }

    $fileLines = Get-Content `
        -LiteralPath $safe `
        -ErrorAction SilentlyContinue

    $foundLines = New-Object System.Collections.Generic.List[string]

    for ($i = 0; $i -lt $fileLines.Count; $i++) {

        if ($fileLines[$i] -imatch [regex]::Escape($Term)) {

            $foundLines.Add(
                "L$($i + 1): $($fileLines[$i].Trim())"
            )

            if ($foundLines.Count -ge $MaxSearchMatches) {
                break
            }
        }
    }

    if ($foundLines.Count -eq 0) {
        return "NO_MATCHES: '$Term' was not found in $safe"
    }

    $out =
        "FILE: $safe`n" +
        "TERM: $Term`n" +
        "MATCHES:`n" +
        ($foundLines -join "`n")

    if ($foundLines.Count -ge $MaxSearchMatches) {
        $out += "`n[showing first $MaxSearchMatches matches]"
    }

    return $out
}