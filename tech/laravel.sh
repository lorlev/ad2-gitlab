#!/bin/bash

RunArtisan() {
	local path="$1"
	shift

	(
		cd "$path"

		runuser \
			-u "${APP_USER:-www-data}" \
			-- \
			"${PHP_BIN:-/usr/bin/php}" \
			artisan \
			"$@"
	)
}

TechValidate() {
	local path="$1"
	local env_file="$path/.env"

	OutputLog "Validating Laravel release"

	[ -f "$path/artisan" ] || {
		echo "ERROR: artisan not found"
		return 1
	}

	[ -f "$path/vendor/autoload.php" ] || {
		echo "ERROR: vendor/autoload.php not found"
		return 1
	}

	[ -f "$env_file" ] || {
		echo "ERROR: application .env not found"
		return 1
	}

	OutputLog "Laravel validation: OK"
}

TechPrepare() {
	local path="$1"

	local app_user="${APP_USER:-www-data}"
	local app_group="${APP_GROUP:-www-data}"

	OutputLog "Preparing Laravel release"

	#
	# Persistent storage
	#
	if IsYes "${LARAVEL_PERSIST_STORAGE:-Y}"; then

		mkdir -p \
			"$static_path/storage/logs" \
			"$static_path/storage/framework/cache" \
			"$static_path/storage/framework/sessions" \
			"$static_path/storage/framework/views"

		rm -rf "$path/storage"

		ln -s \
			"$static_path/storage" \
			"$path/storage"

		chown -R \
			"$app_user:$app_group" \
			"$static_path/storage"

		chmod -R \
			ug+rwX \
			"$static_path/storage"
	fi

	#
	# bootstrap/cache belongs to each release
	#
	mkdir -p "$path/bootstrap/cache"

	chown -R \
		"$app_user:$app_group" \
		"$path/bootstrap/cache"

	chmod -R \
		ug+rwX \
		"$path/bootstrap/cache"

	#
	# Application environment
	#
	chown \
		"root:$app_group" \
		"$path/.env"

	chmod \
		640 \
		"$path/.env"
}

TechBeforeSwitch() {
	local path="$1"

	if IsYes "${LARAVEL_MIGRATE:-Y}"; then
		OutputLog "Laravel migrate"

		RunArtisan \
			"$path" \
			migrate \
			--force
	fi

	OutputLog "Laravel optimize:clear"

	RunArtisan \
		"$path" \
		optimize:clear

	if IsYes "${LARAVEL_FILAMENT_ASSETS:-N}"; then
		OutputLog "Laravel filament:assets"

		RunArtisan \
			"$path" \
			filament:assets
	fi

	if IsYes "${LARAVEL_CONFIG_CACHE:-Y}"; then
		OutputLog "Laravel config:cache"

		RunArtisan \
			"$path" \
			config:cache
	fi

	if IsYes "${LARAVEL_ROUTE_CACHE:-N}"; then
		OutputLog "Laravel route:cache"

		RunArtisan \
			"$path" \
			route:cache
	fi
}

TechAfterSwitch() {
	return 0
}

TechRollback() {
	return 0
}