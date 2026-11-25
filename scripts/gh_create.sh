#!/usr/bin/env bash

[ -z "${DEBUG:-}" ] || set -x
set -euo pipefail

# shellcheck source=scripts/gh_cmd.sh
source "$(dirname "${BASH_SOURCE[0]}")/gh_cmd.sh"
# shellcheck source=scripts/gh_op.sh
source "$(dirname "${BASH_SOURCE[0]}")/gh_op.sh"

_gh_create() {
	local provider=file path="$HOME/.ssh/id_ed25519_github" op_account='' op_vault=''
	local op_item='GitHub SSH Key' title='GitHub SSH Key' yes=0 key file items
	while (($#)); do
		case $1 in
		--provider | --path | --op-account | --op-vault | --op-item | --title)
			(($# >= 2)) || { _cmd_fail "$1 requires a value"; return 1; }
			case $1 in
			--provider) provider=$2 ;; --path) path=$2 ;; --op-account) op_account=$2 ;;
			--op-vault) op_vault=$2 ;; --op-item) op_item=$2 ;; --title) title=$2 ;;
			esac
			shift 2 ;;
		--yes) yes=1; shift ;;
		-h | --help) _show_help; return ;;
		*) _cmd_fail "unknown create option: $1"; return 1 ;;
		esac
	done
	case $provider in
	file)
		[[ -z "$op_account$op_vault" && "$op_item" == 'GitHub SSH Key' ]] || {
			_cmd_fail '--op-account/--op-vault/--op-item require --provider op'
			return 1
		}
		[[ ! -e "$path" && ! -L "$path" && ! -e "$path.pub" && ! -L "$path.pub" ]] || {
			_cmd_fail "key already exists: $path"
			return 1
		}
		_cmd_require gum || return 1
		if (( ! yes )); then
			gum confirm "Create a passphrase-protected key at $path?" || return 1
		fi
		[[ -t 0 ]] || { _cmd_fail 'ssh-keygen needs a terminal for its passphrase prompt'; return 1; }
		umask 077
		mkdir -p -- "$(dirname -- "$path")"
		ssh-keygen -q -t ed25519 -a 64 -f "$path" -C "$title"
		if ssh-keygen -y -P '' -f "$path" >/dev/null 2>&1; then
			_cmd_fail "key has no passphrase; set one with ssh-keygen -p -f '$path'"
			return 1
		fi
		file="$path.pub"
		;;
	op)
		if ((yes)) && [[ -z "$op_account" || -z "$op_vault" ]]; then
			_cmd_fail '--yes with 1Password requires --op-account and --op-vault'
			return 1
		fi
		[[ "$op_item" != */* ]] || { _cmd_fail 'item title must not contain /'; return 1; }
		_cmd_require op || return 1
		_cmd_require gum || return 1
		op_account=$(_cmd_op_account "$op_account") || return 1
		if [[ -z "$op_vault" ]]; then
			op_vault=$(_cmd_op_vault "$op_account") || return 1
			[[ -n "$op_vault" ]] || { _cmd_fail 'no vault selected'; return 1; }
		fi
		items=$(op item list --vault "$op_vault" --account "$op_account" --format json) || {
			_cmd_fail 'could not check 1Password vault; no key was created'
			return 1
		}
		if jq -e --arg item "$op_item" 'any(.[]; .title == $item)' <<< "$items" >/dev/null; then
			_cmd_fail "1Password item already exists: $op_item (will not replace it)"
			return 1
		fi
		if (( ! yes )); then
			gum confirm "Create '$op_item' in $op_account / $op_vault?" || return 1
		fi
		# Do not print the item: it contains the private key. No secret is passed as an argument.
		op item create --category 'SSH Key' --title "$op_item" --vault "$op_vault" \
			--account "$op_account" --ssh-generate-key ed25519 >/dev/null
		file=$(mktemp)
		chmod 600 "$file"
		_GH_SSH_TEMP_FILE=$file
		trap 'rm -f -- "$_GH_SSH_TEMP_FILE"' EXIT
		op read --account "$op_account" "op://$op_vault/$op_item/public key" > "$file"
		;;
	*) _cmd_fail "unknown provider: $provider"; return 1 ;;
	esac
	key=$(_cmd_public_key "$file") || return 1
	_cmd_add_key "$file" "$title" "$key"
	printf '\nPublic key:\n%s\n' "$key"
}
