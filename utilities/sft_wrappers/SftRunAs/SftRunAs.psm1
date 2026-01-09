# SftRunAs.psm1
Get-ChildItem -Path (Join-Path $PSScriptRoot "Public\*.ps1") -ErrorAction Stop | ForEach-Object {
  . $_.FullName
}
