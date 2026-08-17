#!/bin/bash

notif_escape() {
    printf '%s' "$1" |
        sed \
            -e 's/&/\&amp;/g' \
            -e 's/</\&lt;/g' \
            -e 's/>/\&gt;/g'
}

notif_deploy_started() {
    notif_send "$(cat <<EOF
<b>DEPLOYMENT STARTED</b>
══════════════════════════════════════

<b>Project:</b> $(notif_escape "${PROJECT:-unknown}")
<b>Environment:</b> $(notif_escape "${ENVIRONMENT:-unknown}")
<b>Host:</b> $(notif_escape "$(hostname)")
<b>Commit:</b> <code>$(notif_escape "$SHA")</code>
<b>Time:</b> $(date -u '+%Y-%m-%d %H:%M:%S UTC')
EOF
)"
}

notif_deploy_result() {
    local status="$1"
    local duration="$2"
    local rollback="$3"

    notif_send "$(cat <<EOF
<b>DEPLOYMENT RESULT</b>
══════════════════════════════════════

<b>Project:</b> $(notif_escape "${PROJECT:-unknown}")
<b>Environment:</b> $(notif_escape "${ENVIRONMENT:-unknown}")
<b>Status:</b> $(notif_escape "$status")
<b>Commit:</b> <code>$(notif_escape "$SHA")</code>
<b>Duration:</b> ${duration}s
<b>Rollback:</b> $(notif_escape "$rollback")
<b>Time:</b> $(date -u '+%Y-%m-%d %H:%M:%S UTC')
EOF
)"
}