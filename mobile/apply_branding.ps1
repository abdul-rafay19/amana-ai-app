# Run once from the mobile folder:   powershell -ExecutionPolicy Bypass -File apply_branding.ps1
# Sets the app name shown under the icon and generates the launcher icon from assets/icon/.
$ErrorActionPreference = "Stop"
Set-Location $PSScriptRoot
$utf8 = New-Object System.Text.UTF8Encoding($false)   # no BOM (a BOM breaks Java/XML tools)

$mf = (Resolve-Path "android\app\src\main\AndroidManifest.xml").Path
$x = [System.IO.File]::ReadAllText($mf)
$x = [regex]::Replace($x, 'android:label="[^"]*"', 'android:label="Amana AI"')
[System.IO.File]::WriteAllText($mf, $x, $utf8)
Write-Host "App name set to: Amana AI"

flutter pub get
dart run flutter_launcher_icons
Write-Host "Icon generated."

# Native splash (shows instantly while Flutter starts). Optional: if it fails the app still works.
try {
  dart run flutter_native_splash:create
  Write-Host "Native splash generated."
} catch {
  Write-Host "Native splash step skipped (not required): $_"
}
Write-Host "`nNow run:  flutter run"
