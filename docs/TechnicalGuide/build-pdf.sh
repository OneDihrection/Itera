#!/bin/zsh
# build-pdf.sh
# Itera
# Created by Amelia Putri Aftiana on 13/11/2026.
#
# Renders itera-technical-guide.html to docs/Itera-Technical-Guide.pdf with headless Google Chrome.
set -euo pipefail
here=${0:A:h}
chrome="/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"
"$chrome" --headless --disable-gpu --no-pdf-header-footer --allow-file-access-from-files \
  --print-to-pdf="$here/../Itera-Technical-Guide.pdf" "file://$here/itera-technical-guide.html" 2>/dev/null
echo "$here/../Itera-Technical-Guide.pdf"
