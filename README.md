MeshCore Drone Updater is an automated firmware flashing service designed for nRF52-based MeshCore nodes in hard-to-reach locations (such as roofs) using a Raspberry Pi mounted on a drone.


🚀 Features

Autonomous Updates: Automatically detects nRF52 devices in DFU mode via Bluetooth Low Energy (BLE).

Mapping Logic: Uses mapping files (dfu_mapping.txt and firmware_mapping.txt) to match discovered DFU BLE names to the correct firmware versions.

Firmware Overrides: Support for temporary overrides of the mapped firmwares.


🛠 Installation

The installation is designed to be straightforward for Raspberry Pi OS (and other Linux distributions):


git clone https://github.com/lucidnx/meshcore-drone-updater.git

cd meshcore-drone-updater

sudo ./install.sh


The script will install necessary dependencies, configure the Python environment, and set up the updater as a system service.


📂 Configuration & Mapping

The updater relies on two primary mapping files to determine which firmware to flash to which device:

dfu_mapping.txt: Maps device names to specific firmware files.

firmware_mapping.txt: Maps device names to specific firmware files.

Local Overrides

If you need to force a specific update without modifying mapping files, you can place files in the following directory (SD card boot partition for easy access using computer):

Path: /boot/firmware/drone-updater/

firmware.zip: Local firmware package.

dfu.zip: Local DFU package.

If these files exist, the updater will prioritize them over the automated mapping table.

After flash, these override files are removed.


🚁 Use Case: Drone-Based Maintenance

This tool is specifically optimized for "Drive-by" (or "Fly-by") updates:

A Raspberry Pi (running this service) is attached to a drone.

The drone flies within BLE range of a node (e.g., on a rooftop or tower).

The node is triggered into DFU mode.

The service detects the DFU name, matches it to the mapping, and flashes the new firmware automatically.


🔧 Technical Details

Uses the nrf_dfu_py library by @recrof for the DFU protocol implementation.

Runs as a systemd service, ensuring it starts on boot and logs activity for post-flight review.


🤝 Acknowledgments

recrof/nrf_dfu_py - The core BLE DFU script.

meshcore-dev/MeshCore - The mesh firmware ecosystem this tool primarily supports.
