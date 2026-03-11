#!/usr/bin/env bash
version=1

# abort on error, undefined var, or failed pipe
set -euo pipefail

# Column padding between fields
col_pad=3

# Parse command line arguments
TEST_MODE=false
ERASE_FLASH=false
SHOW_HELP=false
FIRMWARE_FILE=""

while [[ $# -gt 0 ]]; do
    case $1 in
        -t|--test) TEST_MODE=true; shift ;;
        -e|--erase) ERASE_FLASH=true; shift ;;
        -h|--help) SHOW_HELP=true; shift ;;
        -*) echo "Unknown option: $1"; SHOW_HELP=true; shift ;;
        *) FIRMWARE_FILE="$1"; shift ;;
    esac
done

# Handle -h|--help: Display usage information
if $SHOW_HELP; then
    echo "Usage: mesh_flasher.sh [OPTIONS] <firmware_file.bin>"
    echo ""
    echo "Firmware flashing utility for ESP32-based MeshCore devices."
    echo "Flashes firmware using esptool with optional erase and verification."
    echo ""
    echo "Options:"
    echo "  -t, --test      Show commands without executing (dry run)"
    echo "  -e, --erase     Erase flash before writing firmware"
    echo "  -h, --help      Display this help message"
    echo ""
    echo "Arguments:"
    echo "  firmware_file.bin    Path to firmware binary file (mandatory)"
    echo ""
    echo "Firmware Types:"
    echo "  Merged (.bin):       Flash at address 0x00000"
    echo "  Non-merged (.bin):   Flash at address 0x10000"
    echo ""
    echo "Examples:"
    echo "  ./mesh_flasher.sh heltec_v4_companion_radio_usb-v1.14.0-9f1a3ea.bin"
    echo "  ./mesh_flasher.sh -e heltec_v4_companion_radio_usb-v1.14.0-9f1a3ea-merged.bin"
    echo "  ./mesh_flasher.sh -t -e heltec_v4_companion_radio_usb-v1.14.0-9f1a3ea.bin"
    exit 0
fi

# Validate firmware file argument
if [[ -z "$FIRMWARE_FILE" ]]; then
    echo "Error: Firmware file is required."
    echo ""
    echo "Usage: mesh_flasher.sh [OPTIONS] <firmware_file.bin>"
    echo ""
    echo "Options:"
    echo "  -t, --test      Show commands without executing (dry run)"
    echo "  -e, --erase     Erase flash before writing firmware"
    echo "  -h, --help      Display this help message"
    exit 1
fi

# Validate firmware file ends with .bin extension
if [[ "$FIRMWARE_FILE" != *.bin ]]; then
    echo "Error: Firmware file must end with .bin extension."
    exit 1
fi

# Validate firmware file exists
if [[ ! -f "$FIRMWARE_FILE" ]]; then
    echo "Error: Firmware file '$FIRMWARE_FILE' not found."
    exit 1
fi

# Determine flash address based on filename
FIRMWARE_BASENAME=$(basename "$FIRMWARE_FILE")
if [[ "$FIRMWARE_BASENAME" == *"-merged"* ]]; then
    FLASH_ADDR="0x00000"
    FIRMWARE_TYPE="Merged"
else
    FLASH_ADDR="0x10000"
    FIRMWARE_TYPE="Non-merged"
fi

# Prompt user to prepare device for DFU mode BEFORE any device listing
echo ""
echo "IMPORTANT: The target device must be in DFU (Device Firmware Update) mode before device enumeration."
echo "To enter DFU mode:"
echo "  1. Hold the BOOT button on the device"
echo "  2. Press and release the RESET button"
echo "  3. Release the BOOT button"
echo ""
read -rp "Is the target device ready in DFU mode? (y/n): " dfu_confirm
case "$dfu_confirm" in
    [Yy]*) ;;
    *) echo "Aborted. Please run the script again when the device is in DFU mode."; exit 0 ;;
    *) echo "Please answer y (yes) or n (no)."; exit 1 ;;
esac

# Note: Based on current testing if a device Serial/MAC does not have colons (:) then it is not in DFU mode.
echo ""
echo "Note: Based on current testing if a device Serial/MAC does not have colons (:) then it is not in DFU mode."
echo ""

# Load MAC->Role and MAC->Name maps from devices.txt for display purposes
declare -A MAC_NAME_MAP MAC_ROLE_MAP
if [[ -f "devices.txt" ]]; then
    while IFS=',' read -r mac role name; do
        [[ -z "$mac" ]] && continue
        [[ "$mac" == \#* ]] && continue
        [[ "$mac" == Region=* ]] && continue
        mac=$(echo "$mac" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
        role=$(echo "$role" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
        name=$(echo "$name" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
        mac_lc=$(echo "$mac" | tr '[:upper:]' '[:lower:]')
        MAC_ROLE_MAP["$mac_lc"]="$role"
        MAC_NAME_MAP["$mac_lc"]="$name"
    done < devices.txt
fi

# Discover serial devices
mapfile -t DEVICES < <(ls /dev/ttyUSB* /dev/ttyACM* 2>/dev/null | sort)

if [[ ${#DEVICES[@]} -eq 0 ]]; then
    echo "No /dev/ttyUSB* or /dev/ttyACM* devices detected."
    exit 1
fi

# Collect data and calculate max widths for each column
declare -a DATA_ROWS
max_dev_len=0
max_mac_len=0
max_role_len=0
max_name_len=0

# Define header lengths
header_dev="Device Path(s)"
header_mac="Serial/MAC"
header_role="Role"
header_name="Name"

# Get maximum lengths of headers
max_dev_len=${#header_dev}
max_mac_len=${#header_mac}
max_role_len=${#header_role}
max_name_len=${#header_name}

for dev in "${DEVICES[@]}"; do
    mac=$(udevadm info --name="$dev" \
        | grep ID_SERIAL_SHORT= \
        | cut -d= -f2)
    [[ -z "$mac" ]] && mac="N/A"
    mac_lc=$(echo "$mac" | tr '[:upper:]' '[:lower:]')
    role=${MAC_ROLE_MAP["$mac_lc"]:-N/A}
    name=${MAC_NAME_MAP["$mac_lc"]:-N/A}

    # Store raw data for later printing
    DATA_ROWS+=("$dev|$mac|$role|$name")

    # Calculate lengths
    (( ${#dev} > max_dev_len )) && max_dev_len=${#dev}
    (( ${#mac} > max_mac_len )) && max_mac_len=${#mac}
    (( ${#role} > max_role_len )) && max_role_len=${#role}
    (( ${#name} > max_name_len )) && max_name_len=${#name}
done

# Add padding to each column width except the last
max_dev_len=$(( max_dev_len + col_pad ))
max_mac_len=$(( max_mac_len + col_pad ))
max_role_len=$(( max_role_len + col_pad ))

# Calculate total width for the divider
total_width=$(( max_dev_len + max_mac_len + max_role_len + max_name_len ))

# Create a divider line
divider=$(printf '%*s' "$total_width" '' | tr ' ' '-')

# Print the header with fixed widths
printf "%-${max_dev_len}s%-${max_mac_len}s%-${max_role_len}s%s\n" "$header_dev" "$header_mac" "$header_role" "$header_name"
echo "$divider"

# Print data rows with fixed widths
for row in "${DATA_ROWS[@]}"; do
    IFS='|' read -r d m r n <<< "$row"
    printf "%-${max_dev_len}s%-${max_mac_len}s%-${max_role_len}s%s\n" "$d" "$m" "$r" "$n"
done

# Prompt for device selection
while true; do
    read -rp "Enter the number of the device to use: " choice
    if [[ "$choice" =~ ^[0-9]+$ ]] && (( choice >= 1 && choice <= ${#DEVICES[@]} )); then
        SELECTED_DEVICE="${DEVICES[$((choice-1))]}"
        break
    else
        echo "Invalid selection – please enter a number between 1 and ${#DEVICES[@]}."
    fi
done

# Display configuration summary
echo ""
echo "Configuration Summary:"
echo "  Device: $SELECTED_DEVICE"
echo "  Firmware: $FIRMWARE_FILE"
echo "  Firmware Type: $FIRMWARE_TYPE"
echo "  Flash Address: $FLASH_ADDR"
echo "  Erase Before Flash: $([ "$ERASE_FLASH" = true ] && echo "Yes" || echo "No")"
echo "  Test Mode: $([ "$TEST_MODE" = true ] && echo "Yes" || echo "No")"
echo ""

# Confirm before proceeding
read -rp "Proceed with flashing? (y/n): " flash_confirm
case "$flash_confirm" in
    [Yy]*) ;;
    *) echo "Flashing cancelled by user."; exit 0 ;;
    *) echo "Please answer y (yes) or n (no)."; exit 1 ;;
esac

# Function to execute or display command
run_esptool() {
    local cmd="$1"
    if $TEST_MODE; then
        echo "[DRY RUN] $cmd"
    else
        echo "$cmd"
        eval "$cmd"
    fi
}

# Execute erase if requested
if $ERASE_FLASH; then
    echo ""
    echo "Erasing flash..."
    erase_cmd="esptool -p $SELECTED_DEVICE erase-flash"
    run_esptool "$erase_cmd"
fi

# Flash firmware
echo ""
echo "Flashing firmware..."
flash_cmd="esptool -p $SELECTED_DEVICE write-flash $FLASH_ADDR $FIRMWARE_FILE"
run_esptool "$flash_cmd"

# Verify flash
echo ""
echo "Verifying flash..."
verify_cmd="esptool -p $SELECTED_DEVICE verify-flash $FLASH_ADDR $FIRMWARE_FILE"
run_esptool "$verify_cmd"

echo ""
echo "Flashing completed successfully."
