# statusline-command.ps1
# Reads JSON from stdin and renders a status line showing:
#   [CAVEMAN badge if active] | cwd | model | context usage

param()

$Esc = [char]27

# Force UTF-8 stdout so non-ASCII badges (e.g. 系統/藍圖 role) reach Claude Code
# intact. PS 5.1 default OutputEncoding is the OEM codepage (CP950 on zh-TW),
# which mangles multibyte chars written via [Console]::Write.
try { [Console]::OutputEncoding = [System.Text.Encoding]::UTF8 } catch {}

# ── Read stdin JSON ──────────────────────────────────────────────────────────
# Read stdin as explicit UTF-8. PS 5.1 default InputEncoding is the OEM codepage
# (CP950 on zh-TW): UTF-8 Chinese in session_name gets misdecoded as double-byte,
# its trailing byte swallows the next char (e.g. a closing quote) → invalid JSON →
# ConvertFrom-Json throws → empty $data → blank "? | ?" statusline.
$raw = ""
try {
    $stdin  = [System.Console]::OpenStandardInput()
    $reader = New-Object System.IO.StreamReader($stdin, [System.Text.Encoding]::UTF8)
    $raw    = $reader.ReadToEnd()
    $reader.Dispose()
} catch {}
if ([string]::IsNullOrWhiteSpace($raw)) { $raw = $input | Out-String }
if ([string]::IsNullOrWhiteSpace($raw)) { $raw = "{}" }

# Claude Code can emit a corrupt "session_name" for non-ASCII titles on this locale
# (replacement chars + a swallowed closing quote → unterminated string), which breaks
# the whole ConvertFrom-Json. We never render session_name, so neutralize it: replace
# its value with "" up to the next ,"key" — repairs the JSON for every field we use.
$raw = $raw -replace '"session_name"\s*:\s*".*?(?=,"\w)', '"session_name":""'

try {
    $data = $raw | ConvertFrom-Json
} catch {
    $data = [PSCustomObject]@{}
}

# ── Helper: safely pull a property ──────────────────────────────────────────
function Get-Prop($obj, [string]$path) {
    $parts = $path -split '\.'
    $cur = $obj
    foreach ($p in $parts) {
        if ($null -eq $cur) { return $null }
        $cur = $cur.$p
    }
    return $cur
}

# ── 1. Caveman badge (reuse existing logic without re-reading stdin) ─────────
$ClaudeDir = if ($env:CLAUDE_CONFIG_DIR) { $env:CLAUDE_CONFIG_DIR } else { Join-Path $HOME ".claude" }
$Flag = Join-Path $ClaudeDir ".caveman-active"
$cavemanBadge = ""

if (Test-Path $Flag) {
    try {
        $Item = Get-Item -LiteralPath $Flag -Force -ErrorAction Stop
        if (-not ($Item.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -and $Item.Length -le 64) {
            $Mode = (Get-Content -LiteralPath $Flag -TotalCount 1 -ErrorAction Stop)
            if ($null -ne $Mode) {
                $Mode = ([string]$Mode).Trim().ToLowerInvariant() -replace '[^a-z0-9-]', ''
                $Valid = @('off','lite','full','ultra','wenyan-lite','wenyan','wenyan-full','wenyan-ultra','commit','review','compress')
                if ($Valid -contains $Mode) {
                    if ([string]::IsNullOrEmpty($Mode) -or $Mode -eq "full") {
                        $cavemanBadge = "${Esc}[38;5;172m[CAVEMAN]${Esc}[0m"
                    } else {
                        $Suffix = $Mode.ToUpperInvariant()
                        $cavemanBadge = "${Esc}[38;5;172m[CAVEMAN:$Suffix]${Esc}[0m"
                    }
                }
            }
        }
    } catch {}
}

# Caveman savings suffix
if ($env:CAVEMAN_STATUSLINE_SAVINGS -ne "0" -and $cavemanBadge -ne "") {
    $SavingsFile = Join-Path $ClaudeDir ".caveman-statusline-suffix"
    if (Test-Path $SavingsFile) {
        try {
            $SavingsItem = Get-Item -LiteralPath $SavingsFile -Force -ErrorAction Stop
            if (-not ($SavingsItem.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -and $SavingsItem.Length -le 64) {
                $Savings = (Get-Content -LiteralPath $SavingsFile -Raw -ErrorAction Stop).TrimEnd()
                $Savings = ($Savings -replace '[\x00-\x1F]', '')
                if ($Savings.Length -gt 0) {
                    $cavemanBadge += " ${Esc}[38;5;172m$Savings${Esc}[0m"
                }
            }
        } catch {}
    }
}

# ── 1b. Session role badge (dual-brain workflow: 藍圖 WHAT / 系統 HOW) ─────────
# Set per-window via $env:SESSION_ROLE before launching claude. Unset → no badge.
$roleBadge = ""
switch -Regex ($env:SESSION_ROLE) {
    '^(systems|系統)$'      { $roleBadge = "${Esc}[38;5;39m[系統 HOW]${Esc}[0m" }
    '^(blueprint|藍圖)$'    { $roleBadge = "${Esc}[38;5;213m[藍圖 WHAT]${Esc}[0m" }
    '^(qa|驗收)$'           { $roleBadge = "${Esc}[38;5;82m[QA 驗收]${Esc}[0m" }
    '^(reviewer|審查)$'     { $roleBadge = "${Esc}[38;5;196m[審查 REVIEW]${Esc}[0m" }
    '^(implementer|實作)$'  { $roleBadge = "${Esc}[38;5;208m[實作 DO]${Esc}[0m" }
    '^(measurer|量測)$'     { $roleBadge = "${Esc}[38;5;51m[量測 MEASURE]${Esc}[0m" }
}

# ── 2. Current working directory ─────────────────────────────────────────────
$cwd = Get-Prop $data "workspace.current_dir"
if ([string]::IsNullOrWhiteSpace($cwd)) { $cwd = Get-Prop $data "cwd" }
if ([string]::IsNullOrWhiteSpace($cwd)) { $cwd = (Get-Location).Path }   # fallback: launch dir
if ([string]::IsNullOrWhiteSpace($cwd)) { $cwd = "?" }
# Shorten home directory to ~
$homePath = $HOME -replace '\\', '/'
$cwdDisplay = ($cwd -replace '\\', '/') -replace [regex]::Escape($homePath), '~'

# worktree 兜底：子 session 常不帶 $env:SESSION_ROLE，靠 cwd path 判實作
if ($roleBadge -eq "" -and $cwdDisplay -match 'worktrees') {
    $roleBadge = "${Esc}[38;5;208m[實作 DO]${Esc}[0m"
}

# ── 3. Model display name ─────────────────────────────────────────────────────
$modelName = Get-Prop $data "model.display_name"
if ([string]::IsNullOrWhiteSpace($modelName)) { $modelName = Get-Prop $data "model.id" }
if ([string]::IsNullOrWhiteSpace($modelName)) { $modelName = "?" }

# ── 4. Context usage ──────────────────────────────────────────────────────────
$usedPct = Get-Prop $data "context_window.used_percentage"
$remainPct = Get-Prop $data "context_window.remaining_percentage"

$contextStr = ""
if ($null -ne $usedPct) {
    $usedInt = [int][Math]::Round($usedPct)
    $remInt  = if ($null -ne $remainPct) { [int][Math]::Round($remainPct) } else { 100 - $usedInt }

    # Color: green < 50%, yellow 50-79%, red >= 80%
    if ($usedInt -lt 50) {
        $ctxColor = "${Esc}[32m"   # green
    } elseif ($usedInt -lt 80) {
        $ctxColor = "${Esc}[33m"   # yellow
    } else {
        $ctxColor = "${Esc}[31m"   # red
    }
    $contextStr = "${ctxColor}ctx:${usedInt}%${Esc}[0m"
}

# ── 5. Git branch / status badge ──────────────────────────────────────────────
$repoName = Get-Prop $data "workspace.repo.name"
$branch = ""
try {
    $branchRaw = (& git -C $cwd rev-parse --abbrev-ref HEAD 2>$null)
    if ($LASTEXITCODE -eq 0 -and -not [string]::IsNullOrWhiteSpace($branchRaw)) {
        $branch = ([string]$branchRaw).Trim()
        $dirty = (& git -C $cwd status --porcelain 2>$null)
        if (-not [string]::IsNullOrWhiteSpace(($dirty | Out-String))) { $branch = "$branch*" }
    }
} catch {}

$repoBadge = ""
if ($branch -ne "") {
    if (-not [string]::IsNullOrWhiteSpace($repoName)) {
        $repoBadge = "${Esc}[36m${repoName}${Esc}[0m ${Esc}[33m${branch}${Esc}[0m"
    } else {
        $repoBadge = "${Esc}[33m${branch}${Esc}[0m"
    }
} elseif (-not [string]::IsNullOrWhiteSpace($repoName)) {
    $repoBadge = "${Esc}[36m${repoName}${Esc}[0m"
}

# ── 5b. Subscription rate-limit usage (5-hour / 7-day) ────────────────────────
# Native fields: rate_limits.{five_hour,seven_day}.used_percentage
# Present only for Claude.ai Pro/Max, after the first API response of a session.
function Format-Limit($pct, [string]$label) {
    if ($null -eq $pct) { return $null }
    $p = [int][Math]::Round([double]$pct)
    if     ($p -lt 50) { $c = "${Esc}[32m" }   # green
    elseif ($p -lt 80) { $c = "${Esc}[33m" }   # yellow
    else               { $c = "${Esc}[31m" }   # red
    return "${c}${label}:${p}%${Esc}[0m"
}
$usageStr = ""
$fiveH  = Get-Prop $data "rate_limits.five_hour.used_percentage"
$sevenD = Get-Prop $data "rate_limits.seven_day.used_percentage"
$limSegs = @()
$s1 = Format-Limit $fiveH  "5h"; if ($s1) { $limSegs += $s1 }
$s2 = Format-Limit $sevenD "7d"; if ($s2) { $limSegs += $s2 }
if ($limSegs.Count -gt 0) { $usageStr = $limSegs -join " " }

# ── 6. Assemble output ────────────────────────────────────────────────────────
$parts = [System.Collections.Generic.List[string]]::new()

if ($roleBadge -ne "") { $parts.Add($roleBadge) }
if ($contextStr -ne "") { $parts.Add($contextStr) }
if ($usageStr -ne "") { $parts.Add($usageStr) }
$parts.Add("${Esc}[35m${modelName}${Esc}[0m")
if ($cavemanBadge -ne "") { $parts.Add($cavemanBadge) }
$parts.Add("${Esc}[34m${cwdDisplay}${Esc}[0m")
if ($repoBadge -ne "") { $parts.Add($repoBadge) }

$separator = " ${Esc}[2m|${Esc}[0m "
[Console]::Write($parts -join $separator)
