#!/bin/bash

notif_send() {
	local text="$1"

	if ! IsYes "${NOTIF:-N}"; then
		return 0
	fi

	if [ -z "${NOTIF_TOKEN:-}" ] ||
	   [ -z "${NOTIF_ID:-}" ]; then

		OutputLog "WARNING: Telegram configuration missing"
		return 0
	fi

	if ! curl \
		-fsS \
		-X POST \
		"https://api.telegram.org/bot${NOTIF_TOKEN}/sendMessage" \
		--data-urlencode "chat_id=${NOTIF_ID}" \
		--data-urlencode "parse_mode=HTML" \
		--data-urlencode "disable_web_page_preview=true" \
		--data-urlencode "text=${text}" \
		>/dev/null; then

		OutputLog "WARNING: Telegram notification failed"
	fi

	return 0
}