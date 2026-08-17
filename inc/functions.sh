#!/bin/bash

IsYes() {
	case "${1:-}" in
		Y|y|YES|yes|TRUE|true|1)
			return 0
			;;
		*)
			return 1
			;;
	esac
}

LoadEnv() {
	if [ ! -f "$local_path/.env" ]; then
		echo "ERROR: $local_path/.env not found"
		echo "Create it from .env.example first."
		exit 1
	fi

	set -a
	source "$local_path/.env"
	set +a
}

#
# Auto-update this deployment framework.
#
SelfUpdate() {
	SELF_UPDATE_CHANGED=0

	if [ ! -d "$local_path/.git" ]; then
		echo "Auto Update: .git directory not found. Skipping."
		return 0
	fi

	if ! command -v git >/dev/null 2>&1; then
		echo "Auto Update: git not found. Skipping."
		return 0
	fi

	local remote="${AUTO_UPDATE_REMOTE:-origin}"
	local branch="${AUTO_UPDATE_BRANCH:-main}"

	local old_hash
	local new_hash

	old_hash="$(git -C "$local_path" rev-parse HEAD)"

	echo "Auto Update: checking $remote/$branch"

	if ! git -C "$local_path" fetch \
		--quiet \
		"$remote" \
		"$branch"; then

		echo "WARNING: Auto Update fetch failed."
		echo "Continuing with current version."
		return 0
	fi

	new_hash="$(git -C "$local_path" rev-parse FETCH_HEAD)"

	if [ "$old_hash" = "$new_hash" ]; then
		echo "Auto Update: already up to date."
		return 0
	fi

	echo "Auto Update: new version found"
	echo "Old: $old_hash"
	echo "New: $new_hash"

	if ! git -C "$local_path" reset \
		--hard \
		"$new_hash" \
		>/dev/null; then

		echo "WARNING: Auto Update failed."
		return 0
	fi

	SELF_UPDATE_CHANGED=1
}

InitPaths() {
	builds_path="$root_path/builds"
	static_path="$root_path/static"
	logs_dir="$root_path/server.logs"
	htdocs_path="$root_path/htdocs"

	mkdir -p \
		"$builds_path" \
		"$static_path" \
		"$logs_dir"
}

LoadModules() {
	source "$local_path/inc/notifications.sh"

	if IsYes "${NOTIF:-N}"; then

		local notif_file
		notif_file="$local_path/notifs/${NOTIF_ENGINE:-telegram}.sh"

		if [ ! -f "$notif_file" ]; then
			echo "ERROR: Notification engine not found: $notif_file"
			exit 1
		fi

		source "$notif_file"

	else

		notif_send() {
			return 0
		}
	fi

	local tech_file
	tech_file="$local_path/tech/${TECH:-generic}.sh"

	if [ ! -f "$tech_file" ]; then
		echo "ERROR: Technology module not found: $tech_file"
		exit 1
	fi

	source "$tech_file"

	for function_name in \
		TechValidate \
		TechPrepare \
		TechBeforeSwitch \
		TechAfterSwitch \
		TechRollback
	do
		if ! type "$function_name" >/dev/null 2>&1; then
			echo "ERROR: $tech_file does not provide $function_name()"
			exit 1
		fi
	done
}

StartLogging() {
	mkdir -p "$logs_dir"

	exec > >(
		tee -a "$logs_dir/auto.deploy.log"
	) 2>&1
}

OutputLog() {
	printf '%s %s\n' \
		"$(date '+%Y-%m-%d %H:%M:%S')" \
		"$*"
}

AcquireLock() {
	exec 9>"$local_path/deploy.lock"

	if ! flock -n 9; then
		echo "ERROR: another deployment is already running"
		exit 1
	fi
}

ValidateSHA() {
	local sha="$1"

	if [[ ! "$sha" =~ ^[0-9a-f]{40}$ ]]; then
		echo "ERROR: invalid commit SHA: $sha"
		exit 1
	fi
}

PrepareTemp() {
	rm -rf -- "$temp_path"
	rm -f -- "$archive_path"

	mkdir -p "$temp_path"
}

DownloadArtifact() {
	local key="$1"
	local destination="$2"

	OutputLog "S3: s3://$S3_BUCKET/$key"

	aws s3 cp \
		"s3://$S3_BUCKET/$key" \
		"$destination" \
		--region "$AWS_REGION"
}

ValidateArchive() {
	local archive="$1"

	OutputLog "Validating release archive"

	if tar -tzf "$archive" |
		grep -Eq '(^/|(^|/)\.\.(/|$))'; then

		echo "ERROR: unsafe path found inside release archive"
		return 1
	fi
}

ExtractArtifact() {
	local archive="$1"
	local destination="$2"

	OutputLog "Extracting release"

	tar -xzf "$archive" \
		-C "$destination"
}

FinalizeBuild() {
	if [ -e "$build_path" ]; then
		OutputLog "Removing existing non-active build: $build_path"
		rm -rf -- "$build_path"
	fi

	mv "$temp_path" "$build_path"

	OutputLog "Build ready: $build_path"
}

SwitchHtdocs() {
	local target="$1"
	local temporary="$root_path/.htdocs.$$"

	rm -f "$temporary"

	ln -s "$target" "$temporary"

	mv -Tf \
		"$temporary" \
		"$htdocs_path"

	OutputLog "htdocs -> $target"
}

RestartService() {
	if [ -z "${SERVICE:-}" ]; then
		OutputLog "No SERVICE configured. Restart skipped."
		return 0
	fi

	OutputLog "Restarting service: $SERVICE"

	systemctl restart "$SERVICE"

	if ! systemctl is-active \
		--quiet \
		"$SERVICE"; then

		echo "ERROR: service is not active: $SERVICE"
		return 1
	fi

	OutputLog "Service active: $SERVICE"
}

StopService() {
	if [ -z "${SERVICE:-}" ]; then
		return 0
	fi

	systemctl stop "$SERVICE"
}

HealthCheck() {
	if [ -z "${HEALTH_URL:-}" ]; then
		OutputLog "No HEALTH_URL configured. Health check skipped."
		return 0
	fi

	local retries="${HEALTH_RETRIES:-10}"
	local delay="${HEALTH_DELAY:-1}"
	local timeout="${HEALTH_TIMEOUT:-3}"

	local attempt=1

	OutputLog "Health check: $HEALTH_URL"

	while [ "$attempt" -le "$retries" ]; do

		if curl \
			-fsS \
			--max-time "$timeout" \
			"$HEALTH_URL" \
			>/dev/null; then

			OutputLog "Health check: OK"
			return 0
		fi

		OutputLog "Health attempt $attempt/$retries failed"

		sleep "$delay"

		attempt=$((attempt + 1))
	done

	echo "ERROR: health check failed"
	return 1
}

RollbackTo() {
	local target="$1"

	if [ -z "$target" ] || [ ! -d "$target" ]; then
		return 1
	fi

	SwitchHtdocs "$target"

	TechRollback "$target" || true

	RestartService

	HealthCheck

	return 0
}

CleanupBuilds() {
	local keep="${BUILDS_COUNT:-3}"
	local current

	current="$(readlink -f "$htdocs_path" 2>/dev/null || true)"

	OutputLog "Keeping last $keep builds"

	local -a builds=()

	mapfile -t builds < <(
		find "$builds_path" \
			-maxdepth 1 \
			-mindepth 1 \
			-type d \
			-regextype posix-extended \
			-regex '.*/[0-9a-f]{40}' \
			-printf '%T@ %p\n' |
		sort -rn |
		cut -d' ' -f2-
	)

	local kept=0
	local directory

	for directory in "${builds[@]}"; do

		if [ "$kept" -lt "$keep" ]; then
			kept=$((kept + 1))
			continue
		fi

		if [ "$directory" = "$current" ]; then
			continue
		fi

		OutputLog "Removing old build: $directory"

		rm -rf -- "$directory"
	done
}

CleanupTemp() {
	if [ -n "${temp_path:-}" ]; then
		rm -rf -- "$temp_path"
	fi

	if [ -n "${archive_path:-}" ]; then
		rm -f -- "$archive_path"
	fi
}

CleanupFailedBuild() {
	if [ -z "${build_path:-}" ]; then
		return 0
	fi

	local active
	active="$(readlink -f "$htdocs_path" 2>/dev/null || true)"

	if [ "$active" != "$build_path" ]; then
		rm -rf -- "$build_path"
	fi
}