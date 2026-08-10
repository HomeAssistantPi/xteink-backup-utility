#!/usr/bin/env bash
# ==============================================================================
# XTEINK Pro 4 / ESP32-S3 Flash & Storage Utility
# "The Universal Edition - Works on your machine, his machine, and that machine."
# Copyright (c) All rights reserved. Oscar Trapp
# ==============================================================================

# --- PORTABLE PATH LOGIC ---
# We use $HOME so this works for 'oscar', 'root', or 'batman'.
# All backups now live in one central folder in the user's home directory.
BASE_DIR="$HOME/xteink_backups"
BACKUP_DIR="$BASE_DIR/flash_backups"
SD_BACKUP_DIR="$BASE_DIR/sd_backups"

# Create the hierarchy of folders if they don't exist
mkdir -p "${BACKUP_DIR}" "${SD_BACKUP_DIR}"

# --- DISTRO & DEPENDENCY CHECKER ---

detect_and_install_dependencies() {
    local missing=()
    for cmd in dialog esptool rsync sed tr lsusb lsblk; do
        if ! command -v $cmd &> /dev/null; then
            missing+=("$cmd")
        fi
    done

    if [ ${#missing[@]} -gt 0 ]; then
        echo "Missing tools: ${missing[*]}"

        # Detect the flavor of Linux we are running
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
            echo "Cannot proceed without dependencies. exiting."
            exit 1
        fi
    fi
}

# Run the check before anything else
detect_and_install_dependencies

# --- THE MAGIC FILTERS ---

# Cleans up esptool output so 'dialog' doesn't have a nervous breakdown.
stream_filter() {
    stdbuf -oL tr '\r' '\n' | sed -u -E 's/\x1B\[[0-9;]*[a-zA-Z]//g'
}

# Finds the ESP32-S3. It's usually the one that just got plugged in.
get_active_port() {
    ls -t /dev/ttyACM* /dev/ttyUSB* 2>/dev/null | head -n 1
}

# Hardware instructions for the "Page Up" button dance.
prompt_rom_instructions() {
    dialog --title " The Secret Handshake (ROM Mode) " \
           --yesno "Instructions to enter ROM Mode:\n\n1. Unplug USB-C and Power Off.\n2. Press and HOLD 'Page Up' (Left button).\n3. Plug in the USB-C cable.\n4. Count to two, then release the button.\n\nIs the device ready?" 15 62
    return $?
}

# --- STORAGE HELPERS ---

# Tries to mount an unmounted SD card so we can actually see the files.
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

# Let's you pick a specific backup file from your central folder.
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

# --- THE INTERNAL FLASH STUFF ---

do_reboot_device() {
    PORT=$(get_active_port)
    if [ -z "$PORT" ]; then
        dialog --msgbox "Device not found. Check the cable!" 7 40
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
    [ -z "$PORT" ] && { dialog --msgbox "Device is shy. Please enter ROM mode correctly." 6 45; return; }

    local outfile="${BACKUP_DIR}/xteink_flash_$(date +%Y%m%d_%H%M%S).bin"
    (
        echo "==> Pulling 16MB of data from the device brain..."
        sudo esptool --chip esp32s3 --port "${PORT}" --no-stub --after no-reset read-flash 0x0 0x1000000 "${outfile}" 2>&1
    ) | stream_filter | dialog --title " Backup Progress " --programbox 22 76
}

do_flash_restore() {
    prompt_rom_instructions || return
    PORT=$(get_active_port)
    [ -z "$PORT" ] && { dialog --msgbox "No device found in ROM mode." 6 45; return; }

    select_backup_file || return
    local image_file="$SELECTED_FILE"

    dialog --yesno "DANGER: This will overwrite the device OS with:\n$image_file\n\nContinue?" 10 60 || return

    (
        echo "==> Writing to Internal Flash. DO NOT UNPLUG."
        sudo esptool --chip esp32s3 --port "${PORT}" --no-stub --after no-reset write-flash 0x0 "${image_file}" 2>&1
    ) | stream_filter | dialog --title " Flash Restore " --programbox 22 76
}

# --- THE SD CARD STUFF ---

do_sd_file_sync() {
    local drives=()
    # Filter: Keep partitions, hide NVMe/System drives.
    while read -r path size type mount label; do
        if [[ "$path" != *"nvme"* ]] && [[ "$path" != *"loop"* ]] && [[ "$mount" != "/" ]]; then
            if [[ "$type" == "part" ]] || [[ "$type" == "disk" ]]; then
                drives+=("$path" "$size | $label ($type)")
            fi
        fi
    done < <(lsblk -lpno NAME,SIZE,TYPE,MOUNTPOINT,LABEL)

    if [ ${#drives[@]} -eq 0 ]; then
        dialog --msgbox "I don't see any SD cards in your card reader." 8 50
        return
    fi

    local selected_dev
    selected_dev=$(dialog --menu "Pick the SD card partition:" 15 65 5 "${drives[@]}" 2>&1 >/dev/tty)
    [ -z "$selected_dev" ] && return

    local mount_path
    mount_path=$(mount_if_needed "$selected_dev")
    [ -z "$mount_path" ] && { dialog --msgbox "Failed to mount partition." 7 40; return; }

    local dest_dir="${SD_BACKUP_DIR}/files_$(date +%Y%m%d_%H%M%S)"
    mkdir -p "$dest_dir"

    (
        echo "==> Syncing files from SD to PC..."
        rsync -av --progress "${mount_path}/" "${dest_dir}/" 2>&1
    ) | stream_filter | dialog --title " SD File Sync " --programbox 22 76

    dialog --msgbox "Sync complete. Files are in:\n$dest_dir" 7 50
}

do_sd_raw_dd() {
    local drives=()
    while read -r path size type; do
        if [[ "$path" != *"nvme"* ]]; then
            drives+=("$path" "$size ($type)")
        fi
    done < <(lsblk -dpno NAME,SIZE,TYPE)

    local target=$(dialog --menu "Select RAW SD Card Reader device:" 14 65 5 "${drives[@]}" 2>&1 >/dev/tty)
    [ -z "$target" ] && return

    local img_out="${SD_BACKUP_DIR}/sd_full_image_$(date +%Y%m%d_%H%M%S).img"
    dialog --yesno "RAW CLONE: This creates a perfect copy of the whole card.\n\nFile location: $img_out\n\nContinue?" 10 60 || return

    (
        echo "==> Cloning... this will take a few minutes."
        sudo dd if="$target" of="$img_out" bs=4M status=progress 2>&1
    ) | stream_filter | dialog --title " RAW SD Clone " --programbox 22 76
}

# --- THE MENU SYSTEM ---

menu_sd_backup() {
    while true; do
        SD_CHOICE=$(dialog --clear --title " MicroSD Storage " --menu "Choose method (PC Card Reader required):" 15 60 4 \
                           1 "Local Reader: Full RAW Image (.img)" \
                           2 "Local Reader: File Sync (rsync)" \
                           3 "--- On-Device USB Mode (Currently Disabled) ---" \
                           4 "Back" 2>&1 >/dev/tty)
        case "$SD_CHOICE" in
            1) do_sd_raw_dd ;;
            2) do_sd_file_sync "local" ;;
            3) dialog --msgbox "On-device USB mode is currently disabled because the device's USB driver is too slow and unstable for large backups." 10 55 ;;
            *) break ;;
        esac
    done
}

# Sudo warmer: Ask for the password once so it's ready for esptool/mount.
sudo -v

while true; do
    CHOICE=$(dialog --clear --backtitle "XTEINK Pro 4 Utility" --title " Main Menu " --menu "Backups stored in: $BASE_DIR" 16 65 7 \
                    1 "Backup Internal Flash (ROM Mode)" \
                    2 "Restore Internal Flash (ROM Mode)" \
                    3 "Hardware Software-Reset to ROM Mode" \
                    4 "Reboot Device to Normal OS" \
                    5 "MicroSD Card Options (Card Reader)" \
                    6 "Query Device Hardware ID" \
                    7 "Exit" 2>&1 >/dev/tty)
    case "$CHOICE" in
        1) do_flash_backup ;;
        2) do_flash_restore ;;
        3) PORT=$(get_active_port)
           if [ -n "$PORT" ]; then
               (sudo esptool --chip esp32s3 --port "$PORT" --before default_reset flash-id 2>&1) | stream_filter | dialog --title " ROM Mode Trigger " --programbox 20 70
           fi ;;
        4) do_reboot_device ;;
        5) menu_sd_backup ;;
        6) PORT=$(get_active_port)
           if [ -n "$PORT" ]; then
               (sudo esptool --chip esp32s3 --port "$PORT" --no-stub flash_id 2>&1) | stream_filter | dialog --title " Hardware Info " --programbox 20 70
           fi ;;
        7|*) clear; break ;;
    esac
done
