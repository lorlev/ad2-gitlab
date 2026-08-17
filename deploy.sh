#!/bin/bash

set -Eeuo pipefail

local_path="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
root_path="$(dirname "$local_path")"

source "$local_path/inc/functions.sh"

LoadEnv

#
# Update auto.deploy itself before loading the other modules.
#
if IsYes "${AUTO_UPDATE:-N}" && [ "${AUTO_DEPLOY_REEXEC:-0}" != "1" ]; then
	SelfUpdate

	if [ "${SELF_UPDATE_CHANGED:-0}" = "1" ]; then
		echo "Auto Deploy updated. Restarting with the new version..."

		AUTO_DEPLOY_REEXEC=1 \
			exec "$local_path/deploy.sh" "$@"
	fi
fi

#
# Paths / modules
#
InitPaths
LoadModules
StartLogging
AcquireLock

#
# Deployment arguments
#
SHA="${1:-}"

ValidateSHA "$SHA"

build_path="$builds_path/$SHA"
temp_path="$builds_path/.${SHA}.tmp"
archive_path="$builds_path/.${SHA}.tar.gz"

CURRENT="$(readlink -f "$htdocs_path" 2>/dev/null || true)"
SWITCHED=0
START_TIME="$(date +%s)"

#
# Error handler
#
DeployFailed() {
	local code=$?

	trap - ERR
	set +e

	OutputLog ""
	OutputLog "Deployment FAILED"
	OutputLog "Exit code: $code"

	local rollback="NO"

	if [ "$SWITCHED" = "1" ]; then

		if [ -n "$CURRENT" ] && [ -d "$CURRENT" ]; then

			OutputLog "Trying rollback to: $CURRENT"

			if RollbackTo "$CURRENT"; then
				rollback="YES"
				OutputLog "Rollback succeeded"
			else
				rollback="FAILED"
				OutputLog "Rollback FAILED"
			fi

		else

			OutputLog "No previous release exists"

			rm -f "$htdocs_path"
			StopService || true

			rollback="NO_PREVIOUS_RELEASE"
		fi
	fi

	CleanupTemp
	CleanupFailedBuild

	local duration
	duration="$(($(date +%s) - START_TIME))"

	notif_deploy_result \
		"FAILED" \
		"$duration" \
		"$rollback"

	exit "$code"
}

trap DeployFailed ERR

#
# Already active?
#
if [ "$CURRENT" = "$build_path" ]; then
	OutputLog "Commit already deployed: $SHA"
	exit 0
fi

#
# Start
#
notif_deploy_started

OutputLog "Deployment started"
OutputLog "Project: ${PROJECT:-unknown}"
OutputLog "Environment: ${ENVIRONMENT:-unknown}"
OutputLog "Commit: $SHA"

#
# Prepare temporary release
#
PrepareTemp

OutputLog ""
OutputLog "Downloading release"

DownloadArtifact \
	"$S3_PREFIX/$SHA/release.tar.gz" \
	"$archive_path"

ValidateArchive "$archive_path"

ExtractArtifact \
	"$archive_path" \
	"$temp_path"

OutputLog ""
OutputLog "Downloading application .env"

DownloadArtifact \
	"$S3_PREFIX/$SHA/.env" \
	"$temp_path/.env"

#
# Technology-specific preparation
#
TechValidate "$temp_path"
TechPrepare "$temp_path"

#
# Turn temporary directory into final build
#
FinalizeBuild

#
# Laravel migration/cache etc.
#
TechBeforeSwitch "$build_path"

#
# Atomic release
#
OutputLog ""
OutputLog "Switching htdocs"

SwitchHtdocs "$build_path"

SWITCHED=1

#
# Restart application service
#
RestartService

#
# Health check
#
HealthCheck

#
# Optional post-deploy work
#
TechAfterSwitch "$build_path"

#
# Success
#
CleanupBuilds
CleanupTemp

duration="$(($(date +%s) - START_TIME))"

trap - ERR

notif_deploy_result \
	"SUCCEEDED" \
	"$duration" \
	"NO"

OutputLog ""
OutputLog "Deployment SUCCEEDED"
OutputLog "Commit: $SHA"
OutputLog "Duration: ${duration}s"