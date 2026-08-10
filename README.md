# XTEINK Pro 4 Utility

A comprehensive Bash CLI utility for the **XTEINK Pro 4 (ESP32-S3)**. This tool provides a safe and easy way to manage internal flash memory and MicroSD card backups from a Linux environment.

![License](https://img.shields.io/badge/license-MIT-green.svg)
![Platform](https://img.shields.io/badge/platform-Linux-lightgray.svg)

## ✨ Features

- **Internal Flash Backup/Restore:** Full 16MB image management for the ESP32-S3.
- **MicroSD Card Tools:** 
  - **RAW Image Clone:** Byte-for-byte `.img` backup of the entire card.
  - **File Sync:** Fast directory backup using `rsync`.
- **Automatic Dependency Setup:** Distro-aware installer for OpenSUSE, Debian, Ubuntu, Arch, and Fedora.
- **Safe Hardware Discovery:** Automatically hides your PC's internal drives to prevent accidental overwrites.
- **Centralized Storage:** All backups are saved to `~/xteink_backups/` for easy access.

## 🚀 Installation

1. **Clone the repository:**
   ```bash
   git clone https://github.com/YOUR_USERNAME/xteink-pro4-utility.git
   cd xteink-pro4-utility
