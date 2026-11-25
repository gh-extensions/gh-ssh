#!/usr/bin/env bats

setup() {
  export MOCK_LOG="$BATS_TEST_TMPDIR/actions"
  export MOCK_PUB="$BATS_TEST_TMPDIR/key.pub"
  export PATH="$BATS_TEST_TMPDIR/bin:$PATH"
  mkdir -p "$BATS_TEST_TMPDIR/bin"
  ssh-keygen -q -t ed25519 -N '' -f "$BATS_TEST_TMPDIR/key"
  cat > "$BATS_TEST_TMPDIR/bin/gh" <<'EOF'
#!/usr/bin/env bash
if [[ $1 == api ]]; then
  if [[ ${MOCK_API_FAIL:-} == yes ]]; then exit 1; fi
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
  'item list')
    if [[ ${MOCK_OP_FAIL:-} == yes ]]; then exit 1; fi
    if [[ ${MOCK_OP_EXISTS:-} == yes ]]; then
      printf '[{"title":"GitHub SSH Key"}]\n'
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
exit 0
EOF
  chmod +x "$BATS_TEST_TMPDIR/bin/"{gh,op,gum}
  export EXT="$BATS_TEST_DIRNAME/../gh-ssh"
}

@test 'add registers both key types and prints only the public key' {
  run "$EXT" add --public-key "$MOCK_PUB" --title test
  [ "$status" -eq 0 ]
  [[ "$output" == *'Registered authentication key'* ]]
  [[ "$output" == *'Registered signing key'* ]]
  [[ "$output" == *'[ssh]'* ]]
  [[ "$output" == *'publicKey = "ssh-ed25519 '* ]]
  [ "$(wc -l < "$MOCK_LOG")" -eq 2 ]
}

@test 'add skips keys already registered in both places' {
  export MOCK_REGISTERED=yes
  run "$EXT" add --public-key "$MOCK_PUB"
  [ "$status" -eq 0 ]
  [[ "$output" == *'Already registered as a signing key'* ]]
  [ ! -e "$MOCK_LOG" ]
}

@test 'add finds a key on an earlier paginated API response' {
  export MOCK_REGISTERED=yes MOCK_PAGES=yes
  run "$EXT" add --public-key "$MOCK_PUB"
  [ "$status" -eq 0 ]
  [ ! -e "$MOCK_LOG" ]
}

@test 'add aborts if GitHub API fails rather than creating a duplicate' {
  export MOCK_API_FAIL=yes
  run "$EXT" add --public-key "$MOCK_PUB"
  [ "$status" -ne 0 ]
  [[ "$output" == *'could not check existing authentication keys'* ]]
  [ ! -e "$MOCK_LOG" ]
}

@test 'op provider generates an item and prints identity metadata without private material' {
  run "$EXT" create --provider op --account example.1password.com --vault Personal --yes
  [ "$status" -eq 0 ]
  [[ "$output" == *'[op]'* ]]
  [[ "$output" == *'account = "example.1password.com"'* ]]
  [[ "$output" != *'item created'* ]]
  [ "$(wc -l < "$MOCK_LOG")" -eq 3 ]
}

@test 'op provider does not create a duplicate 1Password item' {
  export MOCK_OP_EXISTS=yes
  run "$EXT" create --provider op --account example.1password.com --vault Personal --yes
  [ "$status" -ne 0 ]
  [[ "$output" == *'item already exists'* ]]
  [ ! -e "$MOCK_LOG" ]
}

@test 'op provider stops on a vault access failure' {
  export MOCK_OP_FAIL=yes
  run "$EXT" create --provider op --account example.1password.com --vault Personal --yes
  [ "$status" -ne 0 ]
  [[ "$output" == *'could not check 1Password vault'* ]]
  [ ! -e "$MOCK_LOG" ]
}

@test 'file provider refuses to overwrite an existing key' {
  run "$EXT" create --path "$BATS_TEST_TMPDIR/key" --yes
  [ "$status" -ne 0 ]
  [[ "$output" == *'key already exists'* ]]
  [ ! -e "$MOCK_LOG" ]
}

@test 'status matches an existing public key in both GitHub key lists' {
  export MOCK_REGISTERED=yes
  run "$EXT" status --public-key "$MOCK_PUB"
  [ "$status" -eq 0 ]
  [[ "$output" == *'Authentication: registered'* ]]
  [[ "$output" == *'Signing: registered'* ]]
}
