# estimate_tokens.ps1 — token count for one or more files (Windows / PowerShell).
#
# Mirrors the bash version. Uses tiktoken via python3 if importable; otherwise
# falls back to chars/4. Outputs one line per file as "<count>`t<path>", or a
# single sum with -Total, or JSON with -Json.

param(
    [switch]$Total,
    [switch]$Json,
    [Parameter(ValueFromRemainingArguments = $true)]
    [string[]]$Files
)

if (-not $Files -or $Files.Count -eq 0) {
    Write-Error "usage: estimate_tokens.ps1 [-Total] [-Json] <file>..."
    exit 2
}

$haveTiktoken = $false
try {
    $null = & python3 -c "import tiktoken" 2>$null
    if ($LASTEXITCODE -eq 0) { $haveTiktoken = $true }
} catch { $haveTiktoken = $false }

function Count-One {
    param([string]$Path)
    if (-not (Test-Path $Path)) { return 0 }
    if ($haveTiktoken) {
        $py = @"
import sys, tiktoken
enc = tiktoken.get_encoding("cl100k_base")
with open(sys.argv[1], "rb") as fh:
    data = fh.read().decode("utf-8", errors="replace")
print(len(enc.encode(data)))
"@
        $n = & python3 -c $py $Path
        return [int]$n
    } else {
        $chars = (Get-Content -Raw -LiteralPath $Path).Length
        return [int][Math]::Ceiling($chars / 4.0)
    }
}

function Bytes-One {
    param([string]$Path)
    if (-not (Test-Path $Path)) { return 0 }
    return (Get-Item -LiteralPath $Path).Length
}

if ($Total) {
    $sum = 0
    foreach ($f in $Files) { $sum += (Count-One $f) }
    Write-Output $sum
} elseif ($Json) {
    $items = foreach ($f in $Files) {
        [pscustomobject]@{ path = $f; tokens = (Count-One $f); bytes = (Bytes-One $f) }
    }
    $items | ConvertTo-Json -Compress
} else {
    foreach ($f in $Files) {
        $n = Count-One $f
        Write-Output ("{0}`t{1}" -f $n, $f)
    }
}
