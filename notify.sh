#!/bin/bash

set -Eeuo pipefail

local_path="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
root_path="$(dirname "$local_path")"

source "$local_path/inc/functions.sh"

LoadEnv
InitPaths
LoadNotifications
StartLogging

EVENT="${1:-}"
SHA="${2:-}"
BRANCH="${3:-unknown}"
PIPELINE_URL="${4:-}"

ValidateSHA "$SHA"

case "$EVENT" in
	PIPELINE_STARTED|BUILD_FAILED)
		;;
	*)
		echo "ERROR: unsupported notification event: $EVENT"
		exit 1
		;;
esac

notif_ci_event \
	"$EVENT" \
	"$SHA" \
	"$BRANCH" \
	"$PIPELINE_URL"