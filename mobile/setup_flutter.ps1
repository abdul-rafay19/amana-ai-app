# One-time setup. Run from the repo root (PowerShell):
#   powershell -ExecutionPolicy Bypass -File mobile\setup_flutter.ps1
# It creates the android/ios platform folders, adds permissions and sets min SDK.
$ErrorActionPreference = "Stop"
Set-Location $PSScriptRoot
if (-not (Get-Command flutter -ErrorAction SilentlyContinue)) { throw "flutter is not in PATH. Install Flutter first." }

if (-not (Test-Path "android")) {
  flutter create --org pk.amana --project-name amana_app --platforms android,ios _gen
  Copy-Item -Recurse -Force "_gen\android" "android"
  if (Test-Path "_gen\ios") { Copy-Item -Recurse -Force "_gen\ios" "ios" }
  Remove-Item -Recurse -Force "_gen"
}

# ---- Android manifest: internet, microphone, camera, text-to-speech
$mf = "android\app\src\main\AndroidManifest.xml"
$x = Get-Content $mf -Raw
if ($x -notmatch "RECORD_AUDIO") {
  $perm = @"
<uses-permission android:name="android.permission.INTERNET"/>
    <uses-permission android:name="android.permission.RECORD_AUDIO"/>
    <uses-permission android:name="android.permission.CAMERA"/>
    <queries>
        <intent><action android:name="android.intent.action.TTS_SERVICE"/></intent>
    </queries>
    <application
"@
  $x = $x -replace "<application", $perm.TrimEnd()
  $x = $x -replace "<application\s*$", "<application"
  Set-Content -Path $mf -Value $x -Encoding UTF8
}

# ---- Android min SDK 24 (needed by the audio recorder)
foreach ($g in @("android\app\build.gradle.kts", "android\app\build.gradle")) {
  if (Test-Path $g) {
    $t = Get-Content $g -Raw
    $t = $t -replace "minSdk\s*=\s*flutter\.minSdkVersion", "minSdk = 24"
    $t = $t -replace "minSdkVersion\s+flutter\.minSdkVersion", "minSdkVersion 24"
    Set-Content -Path $g -Value $t -Encoding UTF8
  }
}

# ---- iOS usage descriptions (only if the ios folder exists)
$pl = "ios\Runner\Info.plist"
if (Test-Path $pl) {
  $p = Get-Content $pl -Raw
  if ($p -notmatch "NSMicrophoneUsageDescription") {
    $add = "<key>NSMicrophoneUsageDescription</key><string>Amana listens to your voice to fill in your order.</string><key>NSCameraUsageDescription</key><string>Take a photo of a payment slip.</string><key>NSPhotoLibraryUsageDescription</key><string>Choose a photo of a payment slip.</string></dict></plist>"
    $p = $p -replace "</dict>\s*</plist>", $add
    Set-Content -Path $pl -Value $p -Encoding UTF8
  }
}

# ---- remove the default counter-app test (it would not compile against our main.dart)
if (Test-Path "test\widget_test.dart") { Remove-Item "test\widget_test.dart" -Force }

& "$PSScriptRoot\apply_branding.ps1"
flutter analyze
flutter test
Write-Host "`nDone. Run:  flutter run   (no server needed)"
