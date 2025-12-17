#!/usr/bin/env python3
import asyncio
import os
import sys
import logging
import re
import subprocess
from bleak import BleakScanner

# --- Configuration ---
WORK_DIR = "/opt/drone_updater/"
CONFIG_DIR = "/boot/firmware/drone_updater/"
MAPPING_FILE = os.path.join(CONFIG_DIR, "firmware_mapping.txt")
UNIVERSAL_FW = os.path.join(CONFIG_DIR, "firmware.zip")
LOG_FILE = "/var/log/drone_updater.log"
DFU_SCRIPT = os.path.join(WORK_DIR, "dfu_cli.py")
PRN_VALUE = "4"
# enable_verbose = "--verbose"
enable_verbose = "--scan"

# Configure Logging
logging.basicConfig(
    filename=LOG_FILE,
    level=logging.INFO,
    format='%(asctime)s - %(levelname)s - %(message)s',
    datefmt='%Y-%m-%d %H:%M:%S'
)
console = logging.StreamHandler()
console.setLevel(logging.INFO)
logging.getLogger('').addHandler(console)

# Global memory (Persists until a DIFFERENT device overrides it)
context = {
    "base_name": None,  # e.g., RAK4631
    "full_name": None,  # e.g., RAK4631_R_MC
    "firmware": None    # e.g., /path/to/fw.zip
}

async def wait_for_downloader():
    service_name = "firmware-downloader.service"
    logging.info(f"Checking status of {service_name}...")
    while True:
        try:
            cmd = ["systemctl", "is-active", service_name]
            proc = await asyncio.create_subprocess_exec(
                *cmd, stdout=asyncio.subprocess.PIPE, stderr=asyncio.subprocess.PIPE
            )
            stdout, _ = await proc.communicate()
            if stdout.decode().strip() in ["active", "activating"]:
                logging.info(f"{service_name} is active. Waiting...")
                await asyncio.sleep(5)
            else:
                break
        except:
            break

def load_firmware_mapping():
    mapping = {}
    universal_override = None
    if os.path.exists(UNIVERSAL_FW):
        universal_override = UNIVERSAL_FW

    if not os.path.exists(MAPPING_FILE):
        return mapping

    try:
        with open(MAPPING_FILE, 'r') as f:
            for line in f:
                line = line.strip()
                if not line or line.startswith("#"): continue
                parts = line.split(None, 1)
                if len(parts) >= 1:
                    device_name = parts[0]
                    raw_path = universal_override if universal_override else (parts[1] if len(parts) == 2 else "")

                    if raw_path:
                        real_path = os.path.realpath(raw_path)
                        if os.path.exists(real_path):
                            mapping[device_name] = real_path
                        else:
                            logging.error(f"Mapping skipped. File not found: {raw_path}")
    except Exception as e:
        logging.error(f"Error reading mapping: {e}")
    return mapping

def get_device_base(name):
    return name.split('_')[0] if name else ""

async def run_dfu(target_name, address, firmware_path):
    logging.info(f"STARTING OTA: {target_name} [{address}]")
    logging.info(f"FIRMWARE: {firmware_path}")

    # Standard fast command
    cmd = [sys.executable, DFU_SCRIPT, "--prn", PRN_VALUE, enable_verbose, firmware_path, address]

    last_logged_percent = -1
    full_log_buffer = []

    try:
        process = await asyncio.create_subprocess_exec(
            *cmd, stdout=asyncio.subprocess.PIPE, stderr=asyncio.subprocess.STDOUT
        )

        percent_pattern = re.compile(r"(\d{1,3})\s?%")

        # Buffer for detecting \r newlines
        line_buffer = ""

        while True:
            chunk_bytes = await process.stdout.read(1024)
            if not chunk_bytes:
                break

            chunk_str = chunk_bytes.decode('utf-8', errors='ignore')
            line_buffer += chunk_str

            while True:
                pos_n = line_buffer.find('\n')
                pos_r = line_buffer.find('\r')

                if pos_n == -1 and pos_r == -1:
                    break

                # Determine separator order
                if pos_n != -1 and (pos_r == -1 or pos_n < pos_r):
                    limit = pos_n
                    skip = 1
                else:
                    limit = pos_r
                    skip = 1

                line = line_buffer[:limit].strip()
                line_buffer = line_buffer[limit+skip:]

                if not line: continue
                full_log_buffer.append(line)

                # --- Parsing Logic ---

                # 1. Priority: Tagged Info/Errors
                if any(k in line for k in ["[INFO]", "[WARN]", "Timeout", "Error", "Exception"]):
                    logging.info(f"DFU: {line}")
                    match = percent_pattern.search(line)
                    if match: last_logged_percent = int(match.group(1))

                # 2. Priority: Percentage Updates
                elif percent_pattern.search(line):
                    match = percent_pattern.search(line)
                    pct = int(match.group(1))

                    if pct != last_logged_percent:
                        logging.info(f"Flashing Progress: {pct}%")
                        last_logged_percent = pct

                # 3. Priority: Everything Else (Restores missing logs)
                else:
                    logging.info(f"DFU: {line}")

        await process.wait()

        if process.returncode == 0:
            logging.info(f"SUCCESS: Flashing finished for {target_name}")
            return True
        else:
            logging.error(f"FAILED: Flashing ended with code {process.returncode}")
            logging.error("--- DUMPING LOG ---")
            for l in full_log_buffer: logging.error(f"  > {l}")
            logging.error("-------------------")
            return False

    except Exception as e:
        logging.error(f"Execution Exception: {e}")
        return False

async def service_loop():
    global context
    await wait_for_downloader()
    logging.info("--- Drone Auto-Updater Service Started ---")

    while True:
        try:
            mapping = load_firmware_mapping()
            devices = await BleakScanner.discover(timeout=3.0)

            found_bl_match = None
            found_other_mapped = None

            for dev in devices:
                name = dev.name
                if not name: continue

                if name.endswith("_BL"):
                    if context["base_name"] and get_device_base(name) == context["base_name"]:
                        found_bl_match = dev
                elif name in mapping:
                    found_other_mapped = dev

            # Priority 1: Bootloader Loop
            if found_bl_match and context["firmware"]:
                logging.info(f"RECOVERY: Found {found_bl_match.name}. Flashing...")
                await run_dfu(found_bl_match.name, found_bl_match.address, context['firmware'])
                continue

            # Priority 2: New Device
            if found_other_mapped:
                if context["full_name"] != found_other_mapped.name:
                    logging.info(f"NEW TARGET: {found_other_mapped.name}")
                    context["full_name"] = found_other_mapped.name
                    context["base_name"] = get_device_base(found_other_mapped.name)
                    context["firmware"] = mapping[found_other_mapped.name]

                logging.info(f"Target Acquired: {found_other_mapped.name}")
                await run_dfu(found_other_mapped.name, found_other_mapped.address, context["firmware"])
                continue

            await asyncio.sleep(1)

        except asyncio.CancelledError:
            break
        except Exception as e:
            logging.error(f"Main Loop Error: {e}")
            await asyncio.sleep(5)

if __name__ == "__main__":
    try:
        asyncio.run(service_loop())
    except KeyboardInterrupt:
        pass
