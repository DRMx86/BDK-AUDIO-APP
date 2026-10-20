param(
  [Parameter(Mandatory = $true)][string]$Description,
  [switch]$Prefix
)

# Only operate on this project's app on the authorized Redmagic. A fresh
# semantics dump and a second foreground check prevent taps from stale screens.
$ErrorActionPreference = 'Stop'
$bdkAdb = Join-Path $env:LOCALAPPDATA 'Android\Sdk\platform-tools\adb.exe'
$bdkSerial = '9125299103B7'
$bdkPackage = 'com.bdkaudio.controller'
$bdkToken = [guid]::NewGuid().ToString('N')
$bdkRemote = "/sdcard/bdk-ui-$bdkToken.xml"
$bdkLocal = Join-Path $PSScriptRoot "..\artifacts\phone-ui-$bdkToken.xml"

function Assert-BdkForeground {
  $bdkActivity = & $bdkAdb -s $bdkSerial shell dumpsys activity activities
  if ($LASTEXITCODE -ne 0 -or -not ($bdkActivity -match 'topResumedActivity=.*com.bdkaudio.controller/')) {
    throw 'BDK Audio is not foreground. No tap made.'
  }
}

Assert-BdkForeground
try {
  $bdkDump = & $bdkAdb -s $bdkSerial shell uiautomator dump $bdkRemote 2>&1
  if ($LASTEXITCODE -ne 0 -or -not ($bdkDump -match 'UI hierchary dumped')) {
    throw 'Cannot obtain fresh app semantics. Pause animations first. No tap made.'
  }
  & $bdkAdb -s $bdkSerial pull $bdkRemote $bdkLocal | Out-Null
  if ($LASTEXITCODE -ne 0) { throw 'Fresh semantics pull failed. No tap made.' }
  [xml]$bdkUi = Get-Content -LiteralPath $bdkLocal
  $bdkNodes = @($bdkUi.SelectNodes('//node') | Where-Object {
    $_.package -eq $bdkPackage -and $_.enabled -eq 'true' -and
      $(if ($Prefix) { $_.'content-desc'.StartsWith($Description) }
        else { $_.'content-desc' -eq $Description })
  })
  if ($bdkNodes.Count -ne 1) {
    throw "Expected one app target '$Description', found $($bdkNodes.Count). No tap made."
  }
  $bdkBounds = [regex]::Match($bdkNodes[0].bounds, '^\[(\d+),(\d+)\]\[(\d+),(\d+)\]$')
  if (-not $bdkBounds.Success) { throw 'Invalid target bounds. No tap made.' }
  $bdkLeft = [int]$bdkBounds.Groups[1].Value
  $bdkTop = [int]$bdkBounds.Groups[2].Value
  $bdkRight = [int]$bdkBounds.Groups[3].Value
  $bdkBottom = [int]$bdkBounds.Groups[4].Value
  if ($bdkRight -le $bdkLeft -or $bdkBottom -le $bdkTop) {
    throw 'Target is not visible. No tap made.'
  }
  Assert-BdkForeground
  $bdkX = [int](($bdkLeft + $bdkRight) / 2)
  $bdkY = [int](($bdkTop + $bdkBottom) / 2)
  & $bdkAdb -s $bdkSerial shell input tap $bdkX $bdkY
  if ($LASTEXITCODE -ne 0) { throw 'App tap failed.' }
  Write-Output "Tapped BDK Audio: $Description"
} finally {
  & $bdkAdb -s $bdkSerial shell rm -f $bdkRemote | Out-Null
}
