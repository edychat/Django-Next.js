#!/bin/bash
# Test Metro connectivity and app setup

echo "🔍 Metro Connectivity Test"
echo "=========================="
echo ""

# 1. Check Metro container
echo "1. Metro Container Status:"
if podman ps | grep -q "mobile-elitecar_1"; then
    echo "   ✓ Container is running"
else
    echo "   ✗ Container is not running"
    exit 1
fi

# 2. Check if Metro is listening
echo ""
echo "2. Metro Port Status:"
if ss -tlnp 2>/dev/null | grep -q ":8081"; then
    echo "   ✓ Port 8081 is listening"
else
    echo "   ✗ Port 8081 is not listening"
fi

# 3. Check adb reverse
echo ""
echo "3. ADB Reverse Status:"
export ANDROID_HOME=/root/Android/Sdk
$ANDROID_HOME/platform-tools/adb -s emulator-5554 reverse --list | grep 8081 && echo "   ✓ adb reverse tcp:8081 is active" || echo "   ✗ adb reverse not set up"

# 4. Check from emulator's perspective
echo ""
echo "4. Network Test from Emulator:"
echo "   Testing connection to localhost:8081 from inside emulator..."
$ANDROID_HOME/platform-tools/adb -s emulator-5554 shell "echo 'GET /status HTTP/1.0\r\n\r\n' | nc localhost 8081 -w 2 2>&1 | head -5" || echo "   ✗ Connection failed"

# 5. Check Metro logs
echo ""
echo "5. Recent Metro Activity:"
podman logs --tail 10 --since 30s elitecarapp_mobile-elitecar_1 2>&1 | tail -5 || echo "   (No recent activity)"

echo ""
echo "=========================="
echo "Test complete!"
