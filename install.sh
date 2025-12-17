#!/bin/bash

echo " "
echo "-------------------------"
echo " Drone Updater Installer "
echo "-------------------------"
echo " "

sleep 1

if [[ $EUID -ne 0 ]]; then
   echo "This script must be run as root!"
   exit 1
fi

echo " "
echo "Root access confirmed. Proceeding..."

sleep 1

echo " "
echo "Updating system"
apt update
apt upgrade -y

sleep 1

echo "Installing Python3..."
apt install python3

sleep 1

echo "Installing pip..."
apt install python3-pip
python -m pip install --upgrade pip

sleep 1

echo " "
echo "Installing required packages..."
apt install python3-bleak python3-tk jq curl wget mc

sleep 1

echo " "
echo "Copying files..."
cp -r boot_drone_updater/* /boot/firmware/drone_updater/
cp -r power_saving /opt/
cp -r drone_updater /opt/
cp -r firmware_downloader /opt/

sleep 1

echo " "
echo "Setting permissions..."
chown -R root:root /opt/power_saving
chmod -R 755 /opt/power_saving
chown -R root:root /opt/drone_updater
chmod -R 755 /opt/drone_updater
chown -R root:root /opt/firmware_downloader
chmod -R 755 /opt/firmware_downloader

sleep 1

sudo tee -a /boot/firmware/config.txt > /dev/null <<EOF


# Limit max CPU speed to 600MHz (Default is 1000)
arm_freq=600

# Enable GPIO Shutdown
dtoverlay=gpio-shutdown
EOF

echo " "
echo "CPU Frequency set to 600MHz to save power"
echo "Enabled GPIO3 for safe shutdown/start RPi"

sleep 1

sed -i 's/$/ maxcpus=1/' "/boot/firmware/cmdline.txt"

echo "Configured Limit for CPU to 1 core..."

sleep 1

echo " "
echo "Creating services..."
cp power-saving.service /etc/systemd/system/power-saving.service
cp firmware-downloader.service /etc/systemd/system/firmware-downloader.service
cp drone-updater.service /etc/systemd/system/drone-updater.service

sleep 1

echo " "
echo "Starting Services..."
systemctl daemon-reload
systemctl enable drone-updater
systemctl enable firmware-downloader

echo " "
echo "Power saving function will turn off wifi after 1 minute when it's not connected to AP to preserve power"
echo "Be aware that not having saved wifi connection may cut you off"
echo " "
read -p "Do you want to enable power saving? (y/n) " -n 1 -r
echo " "
if [[ $REPLY =~ ^[Yy]$ ]]
then
    echo " "
    echo "Excellent, enabling..."
    systemctl enable power-saving
else
    echo " "
    echo "Power saving will remain disabled"
fi

sleep 2

echo " "
read -p "Do you want to download firmware now? (y/n) " -n 1 -r
echo " "
if [[ $REPLY =~ ^[Yy]$ ]]
then
    echo "Starting Download..."
    systemctl start firmware-downloader
else
    echo "Firmware will be downloaded on next reboot."
fi

sleep 2

echo " "
read -p "Do you want to reboot now? (y/n) " -n 1 -r
echo " "
if [[ $REPLY =~ ^[Yy]$ ]]
then
    echo " "
    echo "Rebooting..."
    sleep 3
    reboot
else
    echo " "
    echo "Done, Enjoy :-)"
    sleep 2
fi
