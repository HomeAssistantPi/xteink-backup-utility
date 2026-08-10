# XTEINK Pro 4 Utility

A comprehensive, menu-driven Bash CLI utility for the **XTEINK Pro 4 (ESP32-S3)**. This tool provides a safe and automated way to manage internal SPI flash memory and MicroSD card backups from a Linux environment.

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
[![Platform](https://img.shields.io/badge/platform-Linux-lightgray.svg)](#)
[![Hardware](https://img.shields.io/badge/hardware-ESP32--S3-green.svg)](#)

## 🌟 Features

*   **Internal Flash Management:**
    *   Full 16MB SPI Flash backup.
    *   Internal flash restoration from previous backups.
    *   Query hardware IDs and chip information.
*   **MicroSD Card Tools (via PC Card Reader):**
    *   **RAW Image Clone:** Create a perfect byte-for-byte `.img` backup of the entire card.
    *   **File Sync:** Fast directory-level backup using `rsync` (ideal for daily book/data backups).
*   **Universal & Portable:**
    *   All backups are centralized in `~/xteink_backups/`.
    *   Works across all Linux user accounts.
*   **Distro-Aware Dependency Setup:**
    *   Automatically detects and offers to install missing tools on **OpenSUSE, Debian, Ubuntu, Fedora, and Arch Linux**.
*   **Safety First:**
    *   Automatically filters out internal system drives (NVMe/SSD) from the selection menus to prevent accidental data loss.

## 🚀 Installation

1.  **Clone the repository:**
    ```bash
    git clone https://github.com/YOUR_USERNAME/xteink-pro4-utility.git
    cd xteink-pro4-utility
    ```

2.  **Make the script executable:**
    ```bash
    chmod +x xteink-manager.sh
    ```

3.  **Run the utility:**
    ```bash
    ./xteink-manager.sh
    ```

## 📖 How-To: Internal Flash (ROM Mode)

To backup or restore the internal flash, the XTEINK Pro 4 must be in **Hardware ROM Mode**:

1.  Disconnect the USB-C cable and power the device **OFF**.
2.  Press and **HOLD** the **Page Up** button (the top button on the left side of the device).
3.  Plug in the USB-C cable while continuing to hold the button.
4.  Count to two, then release the button.
5.  The script will now be able to communicate with the ESP32-S3 chip.

## 💾 How-To: MicroSD Backups

> [!IMPORTANT]
> **On-Device USB Mode is currently disabled** in this utility. The built-in USB mass storage drivers on many ESP32-S3 firmwares are unstable for large data transfers.

**Recommended Workflow:**
1.  Remove the MicroSD card from your XTEINK.
2.  Insert the card into your Linux PC's card reader.
3.  Select **MicroSD Card Options** from the Main Menu.
4.  Choose **RAW Image** for a full system clone or **File Sync** to quickly backup your books and documents.

## 📁 Backup Directory Structure

The script organizes all data in your home directory:
```text
~/xteink_backups/
├── flash_backups/    # .bin files (Internal OS snapshots)
└── sd_backups/       # .img files or synced folders (SD Card data)
