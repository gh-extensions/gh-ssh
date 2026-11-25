#!/usr/bin/env bash

[ -z "${DEBUG:-}" ] || set -x
set -euo pipefail

# shellcheck source=scripts/gh_cmd.sh
source "$(dirname "${BASH_SOURCE[0]}")/gh_cmd.sh"
# shellcheck source=scripts/gh_op.sh
source "$(dirname "${BASH_SOURCE[0]}")/gh_op.sh"

# Read only item-list metadata. Never call `op item get`: its JSON can include a private key.
_gh_op_status() {
	local account=$1 vault=$2 item=$3 expected_file=$4 review_days=$5 rotate_days=$6
	local items matches created_at file key expected age epoch note='' mismatch=0
	items=$(op item list --vault "$vault" --account "$account" --long --format json) || {
		_cmd_fail 'could not list 1Password item metadata'
		return 1
	}
	matches=$(jq -er --arg title "$item" '[.[] | select(.title == $title)] | length' \
		<<< "$items") || { _cmd_fail 'invalid 1Password item list'; return 1; }
	[[ $matches == 1 ]] || {
		_cmd_fail "expected one item named '$item' in $account / $vault; found $matches"
		return 1
	}
	created_at=$(jq -r --arg title "$item" \
		'.[] | select(.title == $title) | .created_at // empty' <<< "$items")

	file=$(mktemp)
	chmod 600 "$file"
	_GH_SSH_TEMP_FILE=$file
	trap 'rm -f -- "$_GH_SSH_TEMP_FILE"' EXIT
	op read --account "$account" "op://$vault/$item/public key" > "$file" || {
		_cmd_fail 'could not read the public-key field from 1Password'
		return 1
	}
	key=$(_cmd_public_key "$file") || return 1
	printf '1Password: %s / %s / %s\n' "$account" "$vault" "$item"
	if [[ -n "$created_at" ]]; then
		epoch=$(jq -er --arg created "$created_at" \
			'$created | sub("\\.[0-9]+"; "") | sub("\\+00:00$"; "Z") | fromdateiso8601' \
			<<< 'null' 2>/dev/null) || epoch=''
		if [[ -n "$epoch" ]]; then
			age=$(( ($(date -u +%s) - epoch) / 86400 ))
			if ((age >= rotate_days)); then
				note='; consider rotating'
			elif ((age >= review_days)); then
				note='; review the key'
			fi
			printf 'Created: %s (%s days ago%s)\n' "${created_at:0:10}" "$age" "$note"
		else
			printf 'Created: %s (age unavailable)\n' "$created_at"
		fi
	else
		printf 'Created: unavailable in 1Password item-list metadata\n'
	fi
	if [[ -n "$expected_file" ]]; then
		expected=$(_cmd_public_key "$expected_file") || return 1
		local key_type key_data expected_type expected_data
		read -r key_type key_data _ <<< "$key"
		read -r expected_type expected_data _ <<< "$expected"
		if [[ $key_type == "$expected_type" && $key_data == "$expected_data" ]]; then
			printf 'Expected public key: matches\n'
		else
			printf 'Expected public key: DIFFERENT\n'
			mismatch=1
		fi
	fi
	_gh_key_status "$key" || return 1
	((mismatch == 0))
}

_gh_key_status() {
	local key=$1 auth=missing signing=missing
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

_gh_status() {
	local file='' provider=file op_account='' op_vault='' op_item='GitHub SSH Key'
	local expected_file='' review_days=365 rotate_days=730 key auth_keys signing_keys
	while (($#)); do
		case $1 in
		--public-key | --provider | --op-account | --op-vault | --op-item | --expected-public-key | --review-days | --rotate-days)
			(($# >= 2)) || { _cmd_fail "$1 requires a value"; return 1; }
			case $1 in
			--public-key) file=$2 ;; --provider) provider=$2 ;;
			--op-account) op_account=$2 ;; --op-vault) op_vault=$2 ;;
			--op-item) op_item=$2 ;; --expected-public-key) expected_file=$2 ;;
			--review-days) review_days=$2 ;; --rotate-days) rotate_days=$2 ;;
			esac
			shift 2 ;;
		-h | --help) _show_help; return ;;
		*) _cmd_fail "unknown status option: $1"; return 1 ;;
		esac
	done
	case $provider in
	file)
		[[ -z "$op_account$op_vault$expected_file" && $op_item == 'GitHub SSH Key' &&
			$review_days == 365 && $rotate_days == 730 ]] || {
			_cmd_fail '1Password status flags require --provider op'
			return 1
		}
		if [[ -z "$file" ]]; then
			auth_keys=$(_cmd_fetch_keys user/keys admin:public_key) || return 1
			signing_keys=$(_cmd_fetch_keys user/ssh_signing_keys admin:ssh_signing_key) || return 1
			printf 'Authentication keys:\n'
			jq -r '.[] | "  \(.title) (\(.id))"' <<< "$auth_keys"
			printf 'Signing keys:\n'
			jq -r '.[] | "  \(.title) (\(.id))"' <<< "$signing_keys"
			return
		fi
		key=$(_cmd_public_key "$file") || return 1
		_gh_key_status "$key"
		;;
	op)
		[[ -z "$file" ]] || { _cmd_fail 'use --expected-public-key with --provider op'; return 1; }
		[[ "$op_item" != */* ]] || { _cmd_fail 'item title must not contain /'; return 1; }
		[[ $review_days =~ ^[0-9]+$ && $rotate_days =~ ^[0-9]+$ ]] || {
			_cmd_fail 'review and rotation days must be non-negative integers'
			return 1
		}
		review_days=$((10#$review_days))
		rotate_days=$((10#$rotate_days))
		_cmd_require op || return 1
		[[ -n "$op_vault" ]] || _cmd_require gum || return 1
		op_account=$(_cmd_op_account "$op_account") || return 1
		if [[ -z "$op_vault" ]]; then
			op_vault=$(_cmd_op_vault "$op_account") || return 1
			[[ -n "$op_vault" ]] || { _cmd_fail 'no vault selected'; return 1; }
		fi
		_gh_op_status "$op_account" "$op_vault" "$op_item" "$expected_file" \
			"$review_days" "$rotate_days"
		;;
	*) _cmd_fail "unknown provider: $provider"; return 1 ;;
	esac
}
