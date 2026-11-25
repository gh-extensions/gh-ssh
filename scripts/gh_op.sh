#!/usr/bin/env bash

[ -z "${DEBUG:-}" ] || set -x
set -euo pipefail

# 1Password account and vault selection; only account/vault metadata is read.
_cmd_op_account() {
	local requested=$1 info
	local -a args=()
	[[ -z "$requested" ]] || args=(--account "$requested")
	info=$(op whoami "${args[@]}" --format json) || {
		_cmd_fail 'could not determine the signed-in 1Password account'
		return 1
	}
	jq -er '.url | strings | sub("^https?://"; "") | sub("/$"; "") | select(length > 0)' \
		<<< "$info" || {
			_cmd_fail '1Password did not return an account URL; pass --op-account'
			return 1
		}
}

_cmd_op_vault() {
	local account=$1 vaults
	local -a names=()
	vaults=$(op vault list --account "$account" --format json) || {
		_cmd_fail 'could not list 1Password vaults'
		return 1
	}
	mapfile -t names < <(jq -r '.[] | .name | strings' <<< "$vaults")
	((${#names[@]})) || { _cmd_fail 'no vaults available'; return 1; }
	gum choose --header "Select a vault in $account" --select-if-one "${names[@]}"
}
