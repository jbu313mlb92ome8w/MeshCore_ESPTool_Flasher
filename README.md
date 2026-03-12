# MeshCore_ESPTool_Flasher
Script to Flash and Verify MeshCore to LoRa Device
- Only tested with Heltec v4 as that is all I have access to currently.
- I dont't have a micro$lop OS to test this setup on. Someone let me know if it works?
<br>
<br>
## Usage
- Place mesh_flasher.sh and, preferably, all needed firmware files in the same directory. 
- Make mesh_flasher.sh executable with `sudo chmod +x mesh_flasher.sh`
- Execute script with `/your/directory/mesh_flasher.sh`
  - `sudo` is not needed to run this script.
  - Your user may need to be part of the `dialout` group to access serial USB devices.
  - I like to change to the directory the script is in and run it with `./mesh_flasher.sh`
  - This script will use "devices.txt" from [MeshCLI_Batch](https://github.com/jbu313mlb92ome8w/MeshCLI_Batch) if available, not required. Just a nice to have.
- The script will use the memory addresses listed in the [MeshCore FAQ](https://github.com/meshcore-dev/MeshCore/blob/main/docs/faq.md#513-q-can-i-use-a-raspberry-pi-to-update-a-meshcore-radio)
  - 0x00000 for merged
  - 0x10000 for non-merged 
- Examples:
  - Help display with `-h` help flag.
    - ./mesh_flasher.sh -h
  - Get a feel how the script works with the `-t` test flag.
    - ./mesh_flasher.sh -t heltec_v4_companion_radio_usb-v1.13.0-295f67d-merged.bin
  - Flash and verify device, no flags.
    - ./mesh_flasher.sh heltec_v4_companion_radio_usb-v1.13.0-295f67d-merged.bin
  - Erase, flash, and verfiy device with `-e` flag.
    - ./mesh_flasher.sh -e heltec_v4_companion_radio_usb-v1.13.0-295f67d-merged.bin
