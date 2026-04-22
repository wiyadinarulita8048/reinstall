#!/bin/bash
set -e
set -o pipefail

curl -L -o reinstall.sh https://raw.githubusercontent.com/wiyadinarulita8048/reinstall/refs/heads/main/reinstall.sh
sed -i 's/\r$//' reinstall.sh
chmod +x reinstall.sh

display_menu() {
    echo "Please select the Windows version:"
    echo "1. Windows Server 2012"
    echo "2. Windows Server 2016"
    echo "3. Windows Server 2019"
    echo "4. Windows Server 2022"
    echo "5. Windows 10"
    echo "6. Windows 11"
    read -rp "Enter your choice: " choice
}

display_menu

gdrive_id=""
img_file=""
img_url=""

case $choice in
    1)
        img_file="windows2012.gz"
        gdrive_id="1kmiRaGNKCWDYJrwkpZQ-UmhrO-esL49x"
        ;;
    2)
        img_file="windows2016.gz"
        gdrive_id="1fzl_7KefeA6shtXmzsyZofPWTwgm_iSY"
        ;;
    3)
        img_file="windows2019.gz"
        gdrive_id="1amlEtPS2Arexhj5-uOEg-LJYflfaXnNv"
        ;;
    4)
        img_file="windows2022.gz"
        gdrive_id="1t9A5oF1-iCmVJ0gpFAm33dCjOd-lsk8W"
        ;;
    5)
        img_file="windows10.gz"
        gdrive_id="11vWmvpLclmcP3ccXr2WDiLEVaH-lvd1w"
        ;;
    6)
        img_file="windows11.xz"
        img_url="https://dl.lamp.sh/vhd/tiny11_23h2.xz"
        ;;
    *)
        echo "Invalid choice. Exiting."
        exit 1
        ;;
esac

# Install gdown after parameter selection as preparation for Google Drive access.
# gdown uses the drive.usercontent.google.com endpoint (v5+) which provides
# direct binary downloads for publicly shared files without cookie confirmation.
# It is available in the reinstall boot environment if needed as a fallback.
if [ -n "$gdrive_id" ]; then
    echo ""
    echo "=== Preparing gdown for Google Drive access ==="
    if command -v pip3 >/dev/null 2>&1; then
        if pip3 install -q gdown; then
            echo "  gdown installed via pip3."
        else
            echo "  Warning: pip3 install gdown failed. The direct usercontent URL will be used instead."
        fi
    elif command -v pip >/dev/null 2>&1; then
        if pip install -q gdown; then
            echo "  gdown installed via pip."
        else
            echo "  Warning: pip install gdown failed. The direct usercontent URL will be used instead."
        fi
    else
        echo "  Warning: pip3/pip not found. gdown could not be installed."
        echo "  The Google Drive download will rely on the direct usercontent URL."
    fi
fi

# Build the image source URL.
# For Google Drive images: use the drive.usercontent.google.com direct-download
# endpoint (the same URL format used by gdown v5+). For publicly shared files
# this URL delivers binary data without requiring cookie-based confirmation,
# making it usable by reinstall.sh's URL validator and by the Alpine boot
# environment that performs the actual full download after handoff.
# The heavy image download is NOT performed here — it is deferred entirely to
# the Alpine environment that reinstall.sh sets up.
if [ -n "$gdrive_id" ]; then
    img_source="https://drive.usercontent.google.com/download?id=${gdrive_id}&export=download&confirm=t"
    echo ""
    echo "Selected: $img_file  (Google Drive ID: $gdrive_id)"
    echo "Post-handoff download URL: $img_source"
    echo "(The image will be downloaded in the reinstall boot environment, not here.)"
else
    img_source="$img_url"
    echo ""
    echo "Selected: $img_file"
    echo "Image URL: $img_source"
fi

# Preflight: verify the image URL is reachable and returns binary data before
# handing off to reinstall.sh. This is a small partial download (512 KB) to
# catch connectivity or permission issues early, without fetching the full image.
echo ""
echo "=== Preflight check ==="
echo "Checking image URL (partial download test, no full pre-download)..."
preflight_tmp="$(mktemp)"
preflight_ok=0
if curl --connect-timeout 15 -Lfr 0-524287 -o "$preflight_tmp" "$img_source" 2>/dev/null; then
    if [ -s "$preflight_tmp" ] && ! head -c 512 "$preflight_tmp" | grep -Eqi '<!DOCTYPE|<html'; then
        preflight_ok=1
        echo "  OK: URL is reachable and returns binary data."
    else
        echo "  ERROR: URL returned an HTML page instead of binary image data."
        echo "         The Google Drive file may not be publicly shared, or Google Drive"
        echo "         is requiring additional authentication for this file ID."
    fi
else
    echo "  ERROR: Could not reach the image URL."
fi
rm -f "$preflight_tmp"

if [ "$preflight_ok" -eq 0 ]; then
    echo ""
    echo "Preflight failed. Aborting to avoid an unrecoverable reinstall state."
    echo "Ensure the Google Drive file is publicly shared ('Anyone with the link') and retry."
    exit 1
fi
echo "=== Preflight passed ==="

REINSTALL_LOG="/tmp/reinstall-$(date +%Y%m%d-%H%M%S).log"
echo ""
echo "reinstall.sh output will be logged to: $REINSTALL_LOG"
echo "Starting reinstall with image: $img_source"
echo ""

reinstall_rc=0
set +e
bash reinstall.sh dd --img="$img_source" 2>&1 | tee "$REINSTALL_LOG"
reinstall_rc=${PIPESTATUS[0]}
set -e

echo ""
echo "Log saved to: $REINSTALL_LOG"
if [ "$reinstall_rc" -eq 0 ]; then
    echo "reinstall.sh setup completed successfully."
    echo ""
    echo "NEXT STEP: The Windows image ($img_file) will be downloaded from"
    echo "Google Drive during the reinstall boot phase."
    reboot
else
    echo "ERROR: reinstall.sh exited with code ${reinstall_rc}."
    echo "Review the log above (or $REINSTALL_LOG) for details before attempting a reboot."
    exit 1
fi
