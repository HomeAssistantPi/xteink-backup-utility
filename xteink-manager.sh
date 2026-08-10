#!/usr/bin/env bash
# ==============================================================================
# XTEINK Pro 4 / ESP32-S3 Flash & Storage Utility
# "The Universal Edition - Works on your machine, his machine, and that machine."
# ==============================================================================
# MIT License
#
# Copyright (c) 2024 Oscar Trapp
#
# Permission is hereby granted, free of charge, to any person obtaining a copy
# of this software and associated documentation files (the "Software"), to deal
# in the Software without restriction, including without limitation the rights
# to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
# copies of the Software, and to permit persons to whom the Software is
# furnished to do so, subject to the following conditions:
#
# The above copyright notice and this permission notice shall be included in all
# copies or substantial portions of the Software.
#
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
# IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
# FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
# AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
# LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
# OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
# SOFTWARE.
# ==============================================================================

# --- PORTABLE PATH LOGIC ---
# Using $HOME ensures this works for any user account (oscar, root, etc.)
BASE_DIR="$HOME/xteink_backups"
BACKUP_DIR="$BASE_DIR/flash_backups"
SD_BACKUP_DIR="$BASE_DIR/sd_backups"

# Create the folder hierarchy if it doesn't exist
mkdir -p "${BACKUP_DIR}" "${SD_BACKUP_DIR}"

# --- DISTRO & DEPENDENCY CHECKER ---
# This ensures the script is ready to run on OpenSUSE, Debian, Arch, or Fedora.
detect_and_install_dependencies() {
    local missing=()
    for cmd in dialog esptool rsync sed tr lsusb lsblk; do
        if ! command -v $cmd &> /dev/null; then
            missing+=("$cmd")
        fi
    done

    if [ ${#missing[@]} -gt 0 ]; then
        echo "The following tools are missing: ${missing[*]}"

        if [ -f /etc/os-release ]; then
            . /etc/os-release
            DISTRO=$ID
        fi

        echo "Detected Distro: $DISTRO"
        read -p "Would you like to attempt to install missing tools? (y/n): " confirm
        if [[ $confirm == [yY] ]]; then
            case $DISTRO in
                opensuse*|suse)
                    sudo zypper install -y dialog rsync python3-esptool usbutils util-linux ;;
                debian|ubuntu|pop|mint)
                    sudo apt-get update && sudo apt-get install -y dialog rsync python3-esptool usbutils util-linux ;;
                arch|manjaro)
                    sudo pacman -S --noconfirm dialog rsync esptool usbutils util-linux ;;
                fedora|rhel|centos)
                    sudo dnf install -y dialog rsync python3-esptool usbutils util-linux ;;
                *)
                    echo "Unknown distro. Please install ${missing[*]} manually."
                    exit 1 ;;
            esac
        else
            echo "Cannot proceed without dependencies. Exiting."
            exit 1
        fi
    fi
}

# Run the check before anything else
detect_and_install_dependencies

# --- THE MAGIC FILTERS ---

# Cleans up esptool output so 'dialog' windows remain clean and readable.
stream_filter() {
    stdbuf -oL tr '\r' '\n' | sed -u -E 's/\x1B\[[0-9;]*[a-zA-Z]//g'
}

# Finds the ESP32-S3 port dynamically.
get_active_port() {
    ls -t /dev/ttyACM* /dev/ttyUSB* 2>/dev/null | head -n 1
}

# Instruction set for hardware ROM mode entrance.
prompt_rom_instructions() {
    dialog --title " The Secret Handshake (ROM Mode) " \
           --yesno "Instructions to enter ROM Mode:\n\n1. Unplug USB-C and Power Off.\n2. Press and HOLD 'Page Up' (Left button).\n3. Plug in the USB-C cable.\n4. Count to two, then release the button.\n\nIs the device ready?" 15 62
    return $?
}

# --- STORAGE HELPERS ---

# Safely mounts partitions if they aren't auto-mounted by the OS.
mount_if_needed() {
    local dev_path="$1"
    local current_mount=$(lsblk -no MOUNTPOINT "$dev_path" | xargs)

    if [ -n "$current_mount" ]; then
        echo "$current_mount"
        return 0
    fi

    local tmp_mount="/tmp/xteink_sd_mnt"
    sudo mkdir -p "$tmp_mount"
    if sudo mount "$dev_path" "$tmp_mount" 2>/dev/null; then
        echo "$tmp_mount"
        return 0
    fi
    return 1
}

# Select a backup from the user's home backup vault.
select_backup_file() {
    SELECTED_FILE=""
    local files=()
    for f in "${BACKUP_DIR}"/*.bin; do
        if [ -f "$f" ]; then
            local fsize=$(ls -lh "$f" | awk '{print $5}')
            local fdate=$(date -r "$f" "+%Y-%m-%d %H:%M:%S")
            files+=("$f" "$fsize ($fdate)")
        fi
    done

    if [ ${#files[@]} -eq 0 ]; then
        dialog --msgbox "Folder: $BACKUP_DIR is empty!\nNo flash backups found." 8 55
        return 1
    fi

    SELECTED_FILE=$(dialog --menu "Select Flash Image to Restore:" 16 75 6 "${files[@]}" 2>&1 >/dev/tty)
    [ -z "$SELECTED_FILE" ] && return 1
    return 0
}

# --- INTERNAL FLASH OPERATIONS ---

do_reboot_device() {
    PORT=$(get_active_port)
    if [ -z "$PORT" ]; then
        dialog --msgbox "Device not found. Is it plugged in?" 7 40
        return 1
    fi
    (
        echo "==> Sending 'Run' command to ESP32-S3..."
        sudo esptool --chip esp32s3 --port "${PORT}" run 2>&1
    ) | stream_filter | dialog --title " Rebooting " --programbox 20 72
}

do_flash_backup() {
    prompt_rom_instructions || return
    PORT=$(get_active_port)
    [ -z "$PORT" ] && { dialog --msgbox "Device not detected. Check button state." 6 45; return; }

    local outfile="${BACKUP_DIR}/xteink_flash_$(date +%Y%m%d_%H%M%S).bin"
    (
        echo "==> Reading 16MB SPI Flash..."
        sudo esptool --chip esp32s3 --port "${PORT}" --no-stub --after no-reset read-flash 0x0 0x1000000 "${outfile}" 2>&1
    ) | stream_filter | dialog --title " Backup Progress " --programbox 22 76
}

do_flash_restore() {
    prompt_rom_instructions || return
    PORT=$(get_active_port)
    [ -z "$PORT" ] && { dialog --msgbox "No device found in ROM mode." 6 45; return; }

    select_backup_file || return
    local image_file="$SELECTED_FILE"

    dialog --yesno "DANGER: Overwrite internal flash with:\n$image_file\n\nAre you sure?" 10 60 || return

    (
        echo "==> Writing to Internal Flash. DO NOT DISCONNECT."
        sudo esptool --chip esp32s3 --port "${PORT}" --no-stub --after no-reset write-flash 0x0 "${image_file}" 2>&1
    ) | stream_filter | dialog --title " Flash Restore " --programbox 22 76
}

# --- SD CARD OPERATIONS (LOCAL READER) ---

do_sd_file_sync() {
    local drives=()
    # Filter: Hides system disks (NVMe) to protect user data.
    while read -r path size type mount label; do
        if [[ "$path" != *"nvme"* ]] && [[ "$path" != *"loop"* ]] && [[ "$mount" != "/" ]]; then
            if [[ "$type" == "part" ]] || [[ "$type" == "disk" ]]; then
                drives+=("$path" "$size | $label ($type)")
            fi
        fi
    done < <(lsblk -lpno NAME,SIZE,TYPE,MOUNTPOINT,LABEL)

    if [ ${#drives[@]} -eq 0 ]; then
        dialog --msgbox "No SD cards detected in card reader." 8 50
        return
    fi

    local selected_dev
    selected_dev=$(dialog --menu "Select SD partition:" 15 65 5 "${drives[@]}" 2>&1 >/dev/tty)
    [ -z "$selected_dev" ] && return

    local mount_path
    mount_path=$(mount_if_needed "$selected_dev")
    [ -z "$mount_path" ] && { dialog --msgbox "Could not mount partition." 7 40; return; }

    local dest_dir="${SD_BACKUP_DIR}/files_$(date +%Y%m%d_%H%M%S)"
    mkdir -p "$dest_dir"

    (
        echo "==> Syncing files via Rsync..."
        rsync -av --progress "${mount_path}/" "${dest_dir}/" 2>&1
    ) | stream_filter | dialog --title " SD Sync " --programbox 22 76

    dialog --msgbox "Sync complete. Folder:\n$dest_dir" 7 50
}

do_sd_raw_dd() {
    local drives=()
    while read -r path size type; do
        if [[ "$path" != *"nvme"* ]] && [[ "$path" != *"loop"* ]]; then
            drives+=("$path" "$size ($type)")
        fi
    done < <(lsblk -dpno NAME,SIZE,TYPE)

    local target=$(dialog --menu "Select RAW SD Card device:" 14 65 5 "${drives[@]}" 2>&1 >/dev/tty)
    [ -z "$target" ] && return

    local img_out="${SD_BACKUP_DIR}/sd_full_image_$(date +%Y%m%d_%H%M%S).img"
    dialog --yesno "RAW CLONE: Creating a full byte-for-byte image.\n\nFile: $img_out\n\nContinue?" 10 60 || return

    (
        echo "==> Cloning... please wait."
        sudo dd if="$target" of="$img_out" bs=4M status=progress 2>&1
    ) | stream_filter | dialog --title " RAW SD Clone " --programbox 22 76
}

# --- MENU NAVIGATION ---

menu_sd_backup() {
    while true; do
        SD_CHOICE=$(dialog --clear --title " MicroSD Storage " --menu "Method (PC Card Reader Recommended):" 15 60 4 \
                           1 "Local Reader: Full RAW Image (.img)" \
                           2 "Local Reader: File Sync (rsync)" \
                           3 "--- On-Device USB Mode (Currently Disabled) ---" \
                           4 "Back" 2>&1 >/dev/tty)
        case "$SD_CHOICE" in
            1) do_sd_raw_dd ;;
            2) do_sd_file_sync "local" ;;
            3) dialog --msgbox "Disabled: The device's USB driver is too slow/unstable for large backups." 10 55 ;;
            *) break ;;
        esac
    done
}

# Sudo warmer
sudo -v

while true; do
    CHOICE=$(dialog --clear --backtitle "XTEINK Pro 4 Utility (MIT Licensed)" --title " Main Menu " --menu "Vault Location: $BASE_DIR" 16 65 7 \
                    1 "Backup Internal Flash (ROM Mode)" \
                    2 "Restore Internal Flash (ROM Mode)" \
                    3 "Trigger Software Reset to ROM Mode" \
                    4 "Reboot Device (Return to OS)" \
                    5 "MicroSD Card Options (Card Reader)" \
                    6 "Query Device Hardware Info" \
                    7 "Exit" 2>&1 >/dev/tty)
    case "$CHOICE" in
        1) do_flash_backup ;;
        2) do_flash_restore ;;
        3) PORT=$(get_active_port)
           if [ -n "$PORT" ]; then
               (sudo esptool --chip esp32s3 --port "$PORT" --before default_reset flash-id 2>&1) | stream_filter | dialog --title " Resetting " --programbox 20 70
           fi ;;
        4) do_reboot_device ;;
        5) menu_sd_backup ;;
        6) PORT=$(get_active_port)
           if [ -n "$PORT" ]; then
               (sudo esptool --chip esp32s3 --port "$PORT" --no-stub flash_id 2>&1) | stream_filter | dialog --title " Info " --programbox 20 70
           fi ;;
        7|*) clear; break ;;
    esac
done
