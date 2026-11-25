#!/usr/bin/env bash

[ -z "${DEBUG:-}" ] || set -x
set -euo pipefail

# shellcheck source=scripts/gh_cmd.sh
source "$(dirname "${BASH_SOURCE[0]}")/gh_cmd.sh"

_gh_add() {
	local file='' title='GitHub SSH Key' key
	while (($#)); do
		case $1 in
		--public-key | --title)
			(($# >= 2)) || { _cmd_fail "$1 requires a value"; return 1; }
			case $1 in --public-key) file=$2 ;; --title) title=$2 ;; esac
			shift 2 ;;
		-h | --help) _show_help; return ;;
		*) _cmd_fail "unknown add option: $1"; return 1 ;;
		esac
	done
	[[ -n "$file" ]] || { _cmd_fail 'add requires --public-key PATH'; return 1; }
	key=$(_cmd_public_key "$file") || return 1
	_cmd_add_key "$file" "$title" "$key"
	_cmd_snippet "$key" '' ''
}
