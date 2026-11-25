#!/usr/bin/env bash
# Public keys only: private keys stay in 1Password or an encrypted file in ~/.ssh.

usage() {
  cat <<'EOF'
gh ssh — register SSH authentication and signing keys with GitHub

USAGE
  gh ssh create [--provider file|op] [--path PATH] [--account ACCOUNT --vault VAULT]
                [--item TITLE] [--title TITLE] [--yes]
  gh ssh add --public-key PATH [--title TITLE]
  gh ssh status [--public-key PATH]

create: generate a new passphrase-protected ~/.ssh key (default), or generate
        one inside 1Password (--provider op). Never replaces an existing key.
add:    register an existing public key; does not access its private key.
status: list your GitHub SSH keys, or check whether a public key is registered.

create prints a public-key-only TOML snippet for identity files. The op provider
requires the 1Password CLI and an unlocked account. SSO authorization, when
required by an organization, must be completed on GitHub afterward.
EOF
}

fail() { printf 'gh-ssh: %s\n' "$*" >&2; return 1; }

require() {
  command -v "$1" >/dev/null 2>&1 || fail "missing $1 (required for this command)"
}

check_runtime() {
  if ((BASH_VERSINFO[0] < 4 || (BASH_VERSINFO[0] == 4 && BASH_VERSINFO[1] < 4))); then
    fail "Bash 4.4+ required (macOS: brew install bash)"
    return 1
  fi
  require gh
  require jq
  require ssh-keygen
}

# GitHub returns both kinds of key separately. Only the public half is compared.
registered() {
  local endpoint=$1 key=$2
  local response
  response=$(gh api "$endpoint" --paginate) || return 2
  jq -ser --arg key "$key" \
    'any(.[][]; (.key | split(" ")[:2]) == ($key | split(" ")[:2]))' \
    <<< "$response" >/dev/null
}

public_key() {
  local file=$1 key
  [[ -f "$file" ]] || { fail "no public key at $file"; return 1; }
  ssh-keygen -lf "$file" >/dev/null 2>&1 || { fail "invalid public key: $file"; return 1; }
  IFS= read -r key < "$file" || [[ -n "$key" ]]
  printf '%s' "$key"
}

add_key() {
  local file=$1 title=$2 key=$3 type endpoint
  for type in authentication signing; do
    if [[ $type == authentication ]]; then
      endpoint=user/keys
    else
      endpoint=user/ssh_signing_keys
    fi
    if registered "$endpoint" "$key"; then
      printf 'Already registered as a %s key\n' "$type"
    else
      case $? in 1) ;; *) fail "could not check existing $type keys"; return 1 ;; esac
      gh ssh-key add "$file" --type "$type" --title "$title" || {
        fail "could not add $type key; any key added earlier remains registered"
        return 1
      }
      printf 'Registered %s key\n' "$type"
    fi
  done
}

snippet() {
  local key=$1 account=$2 vault=$3
  printf '\n# Public key only; paste into your identity file if desired:\n'
  printf '[ssh]\npublicKey = %s\n' "$(jq -n --arg value "$key" '$value')"
  if [[ -n "$account" ]]; then
    printf '\n[op]\naccount = %s\nvault = %s\n' \
      "$(jq -n --arg value "$account" '$value')" \
      "$(jq -n --arg value "$vault" '$value')"
  fi
}

add_command() {
  local file='' title='GitHub SSH Key' key
  while (($#)); do
    case $1 in
      --public-key|--title)
        (($# >= 2)) || { fail "$1 requires a value"; return 1; }
        case $1 in --public-key) file=$2 ;; --title) title=$2 ;; esac
        shift 2 ;;
      -h|--help) usage; return ;;
      *) fail "unknown add option: $1"; return 1 ;;
    esac
  done
  [[ -n "$file" ]] || { fail 'add requires --public-key PATH'; return 1; }
  key=$(public_key "$file") || return 1
  add_key "$file" "$title" "$key"
  snippet "$key" '' ''
}

create_command() {
  local provider=file path="$HOME/.ssh/id_ed25519_github" account='' vault=''
  local item='GitHub SSH Key' title='GitHub SSH Key' yes=0 key file items
  while (($#)); do
    case $1 in
      --provider|--path|--account|--vault|--item|--title)
        (($# >= 2)) || { fail "$1 requires a value"; return 1; }
        case $1 in
          --provider) provider=$2 ;; --path) path=$2 ;; --account) account=$2 ;;
          --vault) vault=$2 ;; --item) item=$2 ;; --title) title=$2 ;;
        esac
        shift 2 ;;
      --yes) yes=1; shift ;;
      -h|--help) usage; return ;;
      *) fail "unknown create option: $1"; return 1 ;;
    esac
  done
  case $provider in
    file)
      [[ -z "$account$vault" ]] || { fail '--account/--vault require --provider op'; return 1; }
      [[ ! -e "$path" && ! -L "$path" && ! -e "$path.pub" && ! -L "$path.pub" ]] || {
        fail "key already exists: $path"
        return 1
      }
      require gum || return 1
      if (( ! yes )); then
        gum confirm "Create a passphrase-protected key at $path?" || return 1
      fi
      [[ -t 0 ]] || { fail 'ssh-keygen needs a terminal to prompt for a passphrase'; return 1; }
      umask 077
      mkdir -p -- "$(dirname -- "$path")"
      ssh-keygen -q -t ed25519 -a 64 -f "$path" -C "$title"
      if ssh-keygen -y -P '' -f "$path" >/dev/null 2>&1; then
        fail "key has no passphrase; set one with ssh-keygen -p -f '$path' before using it"
        return 1
      fi
      file="$path.pub"
      ;;
    op)
      [[ -n "$account" && -n "$vault" ]] || {
        fail '--provider op requires --account and --vault'; return 1;
      }
      [[ "$item" != */* ]] || { fail 'item title must not contain /'; return 1; }
      require op || return 1
      require gum || return 1
      items=$(op item list --vault "$vault" --account "$account" --format json) || {
        fail 'could not check 1Password vault; no key was created'
        return 1
      }
      if jq -e --arg item "$item" 'any(.[]; .title == $item)' <<< "$items" >/dev/null; then
        fail "1Password item already exists: $item (will not replace it)"
        return 1
      fi
      if (( ! yes )); then
        gum confirm "Create a new SSH key in 1Password ($vault)?" || return 1
      fi
      # Do not print the item: it contains the private key. No secret is passed as an argument.
      op item create --category 'SSH Key' --title "$item" --vault "$vault" \
        --account "$account" --ssh-generate-key ed25519 >/dev/null
      file=$(mktemp)
      chmod 600 "$file"
      _gh_ssh_temp_file=$file
      trap 'rm -f -- "$_gh_ssh_temp_file"' EXIT
      op read --account "$account" "op://$vault/$item/public key" > "$file"
      ;;
    *) fail "unknown provider: $provider"; return 1 ;;
  esac
  key=$(public_key "$file") || return 1
  add_key "$file" "$title" "$key"
  snippet "$key" "$account" "$vault"
}

status_command() {
  local file='' key auth signing
  while (($#)); do
    case $1 in
      --public-key)
        (($# >= 2)) || { fail "$1 requires a value"; return 1; }
        file=$2; shift 2 ;;
      -h|--help) usage; return ;;
      *) fail "unknown status option: $1"; return 1 ;;
    esac
  done
  if [[ -z "$file" ]]; then
    printf 'Authentication keys:\n'
    gh api user/keys --paginate --jq '.[] | "  \(.title) (\(.id))"'
    printf 'Signing keys:\n'
    gh api user/ssh_signing_keys --paginate --jq '.[] | "  \(.title) (\(.id))"'
    return
  fi
  key=$(public_key "$file") || return 1
  auth=missing; signing=missing
  if registered user/keys "$key"; then
    auth=registered
  else
    case $? in 1) ;; *) fail 'could not check authentication keys'; return 1 ;; esac
  fi
  if registered user/ssh_signing_keys "$key"; then
    signing=registered
  else
    case $? in 1) ;; *) fail 'could not check signing keys'; return 1 ;; esac
  fi
  printf 'Authentication: %s\nSigning: %s\n' "$auth" "$signing"
  [[ $auth == registered && $signing == registered ]]
}

main() {
  local command=${1:-}
  case $command in
    ''|-h|--help|help) usage; return ;;
    -V|--version) cat "$(dirname -- "${BASH_SOURCE[0]}")/../version.txt"; return ;;
  esac
  check_runtime || return 1
  shift
  case $command in
    create) create_command "$@" ;;
    add) add_command "$@" ;;
    status) status_command "$@" ;;
    *) fail "unknown command: $command"; usage >&2; return 1 ;;
  esac
}
