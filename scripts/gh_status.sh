#!/usr/bin/env bash

[ -z "${DEBUG:-}" ] || set -x
set -euo pipefail

# shellcheck source=scripts/gh_cmd.sh
source "$(dirname "${BASH_SOURCE[0]}")/gh_cmd.sh"

_gh_status() {
	local file='' key auth signing
	while (($#)); do
		case $1 in
		--public-key)
			(($# >= 2)) || { _cmd_fail "$1 requires a value"; return 1; }
			file=$2; shift 2 ;;
		-h | --help) _show_help; return ;;
		*) _cmd_fail "unknown status option: $1"; return 1 ;;
		esac
	done
	if [[ -z "$file" ]]; then
		printf 'Authentication keys:\n'
		gh api user/keys --paginate --jq '.[] | "  \(.title) (\(.id))"'
		printf 'Signing keys:\n'
		gh api user/ssh_signing_keys --paginate --jq '.[] | "  \(.title) (\(.id))"'
		return
	fi
	key=$(_cmd_public_key "$file") || return 1
	auth=missing; signing=missing
	if _cmd_registered user/keys "$key"; then
		auth=registered
	else
		case $? in 1) ;; *) _cmd_fail 'could not check authentication keys'; return 1 ;; esac
	fi
	if _cmd_registered user/ssh_signing_keys "$key"; then
		signing=registered
	else
		case $? in 1) ;; *) _cmd_fail 'could not check signing keys'; return 1 ;; esac
	fi
	printf 'Authentication: %s\nSigning: %s\n' "$auth" "$signing"
	[[ $auth == registered && $signing == registered ]]
}
