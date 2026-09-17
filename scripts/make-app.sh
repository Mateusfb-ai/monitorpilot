#!/bin/zsh
# Empacota o MonitorPilot como .app de menu bar (LSUIElement) com assinatura ad-hoc.
set -euo pipefail
cd "$(dirname "$0")/.."

swift build -c release

APP="build/MonitorPilot.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"

cp .build/release/MonitorPilot "$APP/Contents/MacOS/MonitorPilot"
mkdir -p "$APP/Contents/Resources"
cp AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"

cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key><string>MonitorPilot</string>
    <key>CFBundleIdentifier</key><string>app.monitorpilot</string>
    <key>CFBundleName</key><string>MonitorPilot</string>
    <key>CFBundleShortVersionString</key><string>0.1.0</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>LSMinimumSystemVersion</key><string>14.0</string>
    <key>LSUIElement</key><true/>
    <key>CFBundleIconFile</key><string>AppIcon</string>
    <key>NSHumanReadableCopyright</key><string>MonitorPilot — uso pessoal</string>
    <!-- Gravação de Tela (PIP / Monitor de Transmissão): o TCC do ScreenCapture
         NÃO tem chave de usage description oficial (o macOS usa o nome do app no
         diálogo). Mantido só como documentação da intenção. -->
    <key>NSScreenCaptureUsageDescription</key><string>Exibir outra tela em PIP e transmitir telas.</string>
</dict>
</plist>
PLIST

codesign --force --sign - "$APP"
echo "pronto: $APP"
