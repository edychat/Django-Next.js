#!/bin/bash
# Enable KVM in WSL2 for Android Emulator
# Run this once to set up KVM permanently

echo "🔧 Setting up KVM for Android Emulator in WSL2..."

# Load KVM kernel module
sudo modprobe kvm-intel 2>/dev/null || sudo modprobe kvm 2>/dev/null

# Make KVM accessible to all users
sudo chmod 666 /dev/kvm 2>/dev/null

# Create systemd service to load KVM on boot
sudo tee /etc/systemd/system/kvm-setup.service > /dev/null <<'EOF'
[Unit]
Description=Load KVM kernel module for Android Emulator
DefaultDependencies=no
After=sysinit.target

[Service]
Type=oneshot
ExecStart=/sbin/modprobe kvm-intel
ExecStart=/sbin/modprobe kvm
ExecStart=/bin/chmod 666 /dev/kvm
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
EOF

# Enable the service
sudo systemctl daemon-reload
sudo systemctl enable kvm-setup.service

echo "✅ KVM is configured!"
echo ""
echo "KVM will now be available automatically when WSL2 starts."
echo "You can now run: .\dev.ps1 android"
