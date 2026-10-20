$ErrorActionPreference = 'Stop'
$bdkWorkspace = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$bdkMetadata = Join-Path $bdkWorkspace '.flutter-plugins-dependencies'
$bdkPlugins = Get-Content -LiteralPath $bdkMetadata -Raw | ConvertFrom-Json
foreach ($bdkPlatform in @('windows', 'linux')) {
$bdkLinksRoot = Join-Path $bdkWorkspace "$bdkPlatform\flutter\ephemeral\.plugin_symlinks"
New-Item -ItemType Directory -Path $bdkLinksRoot -Force | Out-Null
foreach ($bdkPlugin in $bdkPlugins.plugins.$bdkPlatform) {
  if ($bdkPlugin.name -notmatch '^[a-z0-9_]+$') { throw 'Invalid plugin name.' }
  $bdkLink = Join-Path $bdkLinksRoot $bdkPlugin.name
  $bdkTarget = [IO.Path]::GetFullPath($bdkPlugin.path).TrimEnd('\')
  if (-not $bdkLink.StartsWith($bdkWorkspace + '\', [StringComparison]::OrdinalIgnoreCase)) {
    throw 'Plugin link escaped the workspace.'
  }
  if (Test-Path -LiteralPath $bdkLink) {
    $bdkExisting = Get-Item -LiteralPath $bdkLink
    if ($bdkExisting.LinkType -ne 'Junction' -or
        [IO.Path]::GetFullPath($bdkExisting.Target).TrimEnd('\') -ne $bdkTarget) {
      throw "Existing plugin path does not match: $($bdkPlugin.name). No files removed."
    }
  } else {
    New-Item -ItemType Junction -Path $bdkLink -Target $bdkTarget | Out-Null
  }
}
}
Write-Output 'Project-local desktop plugin junctions are current.'
