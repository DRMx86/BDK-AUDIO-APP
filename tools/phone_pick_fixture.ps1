param(
  [Parameter(Mandatory = $true)]
  [ValidateSet('Show roots', 'Downloads', 'BDK-QA-short.m4a', 'BDK-QA-chunks.wav', 'BDK-QA-long.flac', 'BDK-QA-presets.json', 'BDK-QA-FORMAT-FIXTURE-NOT-FIRMWARE.bin', 'BDK-QA-FORMAT-FIXTURE-NOT-FIRMWARE.enc')]
  [string]$Target
)

# Native audio-import QA only: select task-owned fixtures through Android's
# picker. Never accepts arbitrary user filenames or operates outside PickActivity.
$ErrorActionPreference = 'Stop'
$bdkAdb = Join-Path $env:LOCALAPPDATA 'Android\Sdk\platform-tools\adb.exe'
$bdkSerial = '9125299103B7'
$bdkPickerPackage = 'com.google.android.documentsui'
$bdkToken = [guid]::NewGuid().ToString('N')
$bdkRemote = "/sdcard/bdk-picker-$bdkToken.xml"
$bdkLocal = Join-Path $PSScriptRoot "..\artifacts\picker-$bdkToken.xml"
function Assert-BdkPicker {
  $bdkActivity = & $bdkAdb -s $bdkSerial shell dumpsys activity activities
  if ($LASTEXITCODE -ne 0 -or -not ($bdkActivity -match
      'topResumedActivity=.*com.google.android.documentsui/com.android.documentsui.picker.PickActivity')) {
    throw 'The expected audio picker is not foreground. No tap made.'
  }
}
Assert-BdkPicker
try {
  $bdkDump = & $bdkAdb -s $bdkSerial shell uiautomator dump $bdkRemote 2>&1
  if ($LASTEXITCODE -ne 0 -or -not ($bdkDump -match 'UI hierchary dumped')) {
    throw 'Could not obtain fresh picker state. No tap made.'
  }
  & $bdkAdb -s $bdkSerial pull $bdkRemote $bdkLocal | Out-Null
  if ($LASTEXITCODE -ne 0) { throw 'Picker state pull failed.' }
  [xml]$bdkUi = Get-Content -LiteralPath $bdkLocal
  $bdkTargets = @($bdkUi.SelectNodes('//node') | Where-Object {
    $_.package -eq $bdkPickerPackage -and $_.enabled -eq 'true' -and
      ($_.text -eq $Target -or $_.'content-desc' -eq $Target) -and
      ($Target -ne 'Downloads' -or $_.'resource-id' -eq 'android:id/title')
  } | Group-Object -Property bounds | ForEach-Object { $_.Group[0] })
  if ($bdkTargets.Count -ne 1) { throw "Expected one fixture-picker target, found $($bdkTargets.Count). No tap made." }
  $bdkBounds = [regex]::Match($bdkTargets[0].bounds, '^\[(\d+),(\d+)\]\[(\d+),(\d+)\]$')
  if (-not $bdkBounds.Success) { throw 'Invalid picker target bounds.' }
  $bdkLeft = [int]$bdkBounds.Groups[1].Value
  $bdkTop = [int]$bdkBounds.Groups[2].Value
  $bdkRight = [int]$bdkBounds.Groups[3].Value
  $bdkBottom = [int]$bdkBounds.Groups[4].Value
  if ($bdkRight -le $bdkLeft -or $bdkBottom -le $bdkTop) { throw 'Target not visible.' }
  Assert-BdkPicker
  & $bdkAdb -s $bdkSerial shell input tap ([int](($bdkLeft + $bdkRight) / 2)) ([int](($bdkTop + $bdkBottom) / 2))
  if ($LASTEXITCODE -ne 0) { throw 'Picker tap failed.' }
  Write-Output "Selected fixture picker target: $Target"
} finally {
  & $bdkAdb -s $bdkSerial shell rm -f $bdkRemote | Out-Null
}
