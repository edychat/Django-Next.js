#!/bin/bash
# Robust EliteCar app launcher with automatic Metro connection
set -e

export ANDROID_HOME=/root/Android/Sdk
ADB="$ANDROID_HOME/platform-tools/adb"
DEVICE="emulator-5554"
PACKAGE="app.elitecar.development"
METRO_PORT=8081

echo "🚀 EliteCar App Launcher"
echo ""

# Check if device is connected
if ! $ADB -s $DEVICE get-state 2>/dev/null | grep -q "device"; then
    echo "❌ Emulator not found at $DEVICE"
    echo "   Run: ./dev.sh android"
    exit 1
fi

echo "✅ Emulator connected: $DEVICE"

# Setup adb reverse for Metro and API
echo "🔌 Setting up port forwarding..."
$ADB -s $DEVICE reverse tcp:$METRO_PORT tcp:$METRO_PORT 2>/dev/null || true
$ADB -s $DEVICE reverse tcp:8000 tcp:8000 2>/dev/null || true
echo "   ✓ tcp:$METRO_PORT → tcp:$METRO_PORT"
echo "   ✓ tcp:8000 → tcp:8000"

# Check if Metro is running
echo ""
echo "🔍 Checking Metro bundler..."
if timeout 2 curl -s http://localhost:$METRO_PORT/status >/dev/null 2>&1; then
    echo "   ✓ Metro is running on port $METRO_PORT"
else
    echo "   ⚠️  Metro might not be responding"
    echo "   Continuing anyway..."
fi

# Launch the app with explicit Metro URL
echo ""
echo "📱 Launching EliteCar app..."

# First, ensure the server URL is registered by opening the deep link
# This adds http://localhost:8081 to the server list
$ADB -s $DEVICE shell am start \
    -a android.intent.action.VIEW \
    -d "exp+elitecar://expo-development-client/?url=$METRO_URL_ENCODED" \
    $PACKAGE 2>&1 | grep -v "Warning:" || true

# Give it a moment to register
sleep 2

# Now launch the main activity which should show the registered server
$ADB -s $DEVICE shell am start \
    -n "$PACKAGE/.MainActivity" \
    2>&1 | grep -v "Warning:" || true

echo ""
echo "✅ App launched with Metro URL: http://localhost:$METRO_PORT"
echo ""
echo "📋 Next steps:"
echo "   1. Check the emulator screen"
echo "   2. The app should automatically connect to Metro"
echo "   3. If it shows 'Searching...', shake device (Ctrl+Shift+D) and select 'Reload'"
echo ""
echo "💡 Troubleshooting:"
echo "   - App not loading? Check Metro logs: podman logs -f elitecarapp_mobile-elitecar_1"
echo "   - Still issues? Restart Metro: podman restart elitecarapp_mobile-elitecar_1"
