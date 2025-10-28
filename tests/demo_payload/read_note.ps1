param(
    [string]$FileName = "smoke_note.txt"
)

$ErrorActionPreference = 'Stop'
$notePath = Join-Path -Path $PSScriptRoot -ChildPath $FileName

if (-not (Test-Path -Path $notePath)) {
    throw "Missing note file: $notePath"
}

$content = Get-Content -Path $notePath -Raw
Write-Output "Note file content:"
Write-Output $content
