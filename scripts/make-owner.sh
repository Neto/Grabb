#!/bin/zsh
# Owner installer: Grabb that never asks for a license key, for the developer's own Macs.
# Writes ~/Desktop/Grabb-<version>-Owner.pkg (signed, notarized). Never publish this file.
# make-installer.sh also builds it at the end of every release.
set -euo pipefail
OWNER=1 PUBLISH_UPDATE=0 "$(dirname "$0")/make-installer.sh"
