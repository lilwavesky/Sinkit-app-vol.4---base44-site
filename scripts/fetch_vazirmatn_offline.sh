#!/usr/bin/env bash
set -euo pipefail

OUT_DIR="$(dirname "$0")/../assets/google_fonts"
mkdir -p "$OUT_DIR"

BASE_URL="https://github.com/rastikerdar/vazirmatn/raw/master/fonts/ttf"
for weight in Regular Medium Bold; do
  echo "Downloading Vazirmatn-${weight}.ttf ..."
  curl -fL "${BASE_URL}/Vazirmatn-${weight}.ttf" -o "${OUT_DIR}/Vazirmatn-${weight}.ttf"
done

echo "Done. Vazirmatn Regular, Medium, and Bold are now bundled offline in assets/google_fonts/."
