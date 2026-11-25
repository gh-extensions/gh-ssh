setup() {
  export MOCK_LOG="$BATS_TEST_TMPDIR/actions"
  export MOCK_PUB="$BATS_TEST_TMPDIR/key.pub"
  export PATH="$BATS_TEST_TMPDIR/bin:$PATH"
  mkdir -p "$BATS_TEST_TMPDIR/bin"
  ssh-keygen -q -t ed25519 -N '' -f "$BATS_TEST_TMPDIR/key"
  cat > "$BATS_TEST_TMPDIR/bin/gh" <<'EOF'
#!/usr/bin/env bash
if [[ $1 == api ]]; then
  if [[ ${MOCK_API_FAIL:-} == yes || ${MOCK_API_FAIL:-} == "$2" ]]; then
    printf '{"message":"Not Found","status":"404"}\n'
    printf 'gh: Not Found (HTTP 404)\n' >&2
    exit 1
  fi
  if [[ ${MOCK_REGISTERED:-} == yes ]]; then
    jq -n --arg key "$(<"$MOCK_PUB")" '[{key:$key, title:"existing", id:1}]'
    if [[ ${MOCK_PAGES:-} == yes ]]; then printf '[]\n'; fi
  else
    printf '[]\n'
  fi
elif [[ $1 == ssh-key && $2 == add ]]; then
  printf '%s\n' "$*" >> "$MOCK_LOG"
else
  exit 1
fi
EOF
  cat > "$BATS_TEST_TMPDIR/bin/op" <<'EOF'
#!/usr/bin/env bash
case "$1 $2" in
  'whoami --account' | 'whoami --format')
    printf '{"url":"https://example.1password.com/"}\n' ;;
  'vault list')
    if [[ ${MOCK_VAULT_FAIL:-} == yes ]]; then exit 1; fi
    printf '[{"name":"Personal"},{"name":"Shared"}]\n' ;;
  'item list')
    if [[ ${MOCK_OP_FAIL:-} == yes ]]; then exit 1; fi
    if [[ ${MOCK_OP_EXISTS:-} == yes ]]; then
      if [[ ${MOCK_OP_NO_DATE:-} == yes ]]; then
        printf '[{"title":"GitHub SSH Key"}]\n'
      else
        printf '[{"title":"GitHub SSH Key","created_at":"2023-01-01T00:00:00Z"}]\n'
      fi
    else
      printf '[]\n'
    fi ;;
  'item create') printf 'item created\n' >> "$MOCK_LOG" ;;
  'read --account') cat "$MOCK_PUB" ;;
  *) exit 1 ;;
esac
EOF
  cat > "$BATS_TEST_TMPDIR/bin/gum" <<'EOF'
#!/usr/bin/env bash
case $1 in
  choose) printf '%s\n' "${MOCK_VAULT_CHOICE:-Personal}" ;;
  confirm) printf '%s\n' "$*" >> "$MOCK_GUM_LOG" ;;
  *) exit 1 ;;
esac
EOF
  export MOCK_GUM_LOG="$BATS_TEST_TMPDIR/confirmations"
  chmod +x "$BATS_TEST_TMPDIR/bin/"{gh,op,gum}
  export EXT="$BATS_TEST_DIRNAME/../gh-ssh"
}
