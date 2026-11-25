#!/usr/bin/env bash

[ -z "${DEBUG:-}" ] || set -x
set -euo pipefail

# Shared public-key helpers. Private keys never enter these functions.
_cmd_fail() {
	printf 'gh-ssh: %s\n' "$*" >&2
	return 1
}

_cmd_require() {
	command -v "$1" >/dev/null 2>&1 || _cmd_fail "missing $1 (required for this command)"
}

# Fetch all API pages, but never expose an error response as a list of keys.
# On missing scopes, tell the user how to grant access without changing gh's login.
_cmd_fetch_keys() {
	local endpoint=$1 scope=$2 response
	if ! response=$(gh api "$endpoint" --paginate); then
		_cmd_fail "could not list $endpoint; if access is missing, run: gh auth refresh -h ${GH_HOST:-github.com} -s $scope"
		return 2
	fi
	if ! printf '%s\n' "$response" | jq -sc 'if length > 0 and all(.[]; type == "array") then add else error("expected key lists") end'; then
		_cmd_fail "invalid response from $endpoint"
		return 2
	fi
}

# Returns 0 if present, 1 if absent, 2 on API or JSON errors.
_cmd_registered() {
	local endpoint=$1 key=$2 scope response
	case $endpoint in
	user/keys) scope=admin:public_key ;;
	user/ssh_signing_keys) scope=admin:ssh_signing_key ;;
	*) _cmd_fail "unknown key endpoint: $endpoint"; return 2 ;;
	esac
	response=$(_cmd_fetch_keys "$endpoint" "$scope") || return 2
	jq -er --arg key "$key" \
		'any(.[]; (.key | split(" ")[:2]) == ($key | split(" ")[:2]))' \
		<<< "$response" >/dev/null || {
			local result=$?
			((result == 1)) && return 1
			return 2
		}
}

_cmd_public_key() {
	local file=$1 key
	[[ -f "$file" ]] || { _cmd_fail "no public key at $file"; return 1; }
	ssh-keygen -lf "$file" >/dev/null 2>&1 || {
		_cmd_fail "invalid public key: $file"
		return 1
	}
	IFS= read -r key < "$file" || [[ -n "$key" ]]
	printf '%s' "$key"
}

_cmd_add_key() {
	local file=$1 title=$2 key=$3 type endpoint
	for type in authentication signing; do
		if [[ $type == authentication ]]; then
			endpoint=user/keys
		else
			endpoint=user/ssh_signing_keys
		fi
		if _cmd_registered "$endpoint" "$key"; then
			printf 'Already registered as a %s key\n' "$type"
		else
			case $? in 1) ;; *) _cmd_fail "could not check existing $type keys"; return 1 ;; esac
			gh ssh-key add "$file" --type "$type" --title "$title" || {
				_cmd_fail "could not add $type key; any key added earlier remains registered"
				return 1
			}
			printf 'Registered %s key\n' "$type"
		fi
	done
}

_cmd_snippet() {
	local key=$1 account=$2 vault=$3
	printf '\n# Public key only; paste into your identity file if desired:\n'
	printf '[ssh]\npublicKey = %s\n' "$(jq -n --arg value "$key" '$value')"
	if [[ -n "$account" ]]; then
		printf '\n[op]\naccount = %s\nvault = %s\n' \
			"$(jq -n --arg value "$account" '$value')" \
			"$(jq -n --arg value "$vault" '$value')"
	fi
}
