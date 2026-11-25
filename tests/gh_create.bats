#!/usr/bin/env bats
load test_helper

@test 'interactive op provider uses the active account and selected vault' {
  run "$EXT" create --provider op
  [ "$status" -eq 0 ]
  [[ "$output" == *"$(<"$MOCK_PUB")"* ]]
  [[ "$output" != *'[op]'* ]]
  [[ "$(<"$MOCK_GUM_LOG")" == *'example.1password.com / Personal'* ]]
  [ "$(wc -l < "$MOCK_LOG")" -eq 3 ]
}

@test 'op provider refuses unattended account or vault inference' {
  run "$EXT" create --provider op --yes
  [ "$status" -ne 0 ]
  [[ "$output" == *'requires --op-account and --op-vault'* ]]
  [ ! -e "$MOCK_LOG" ]
}

@test 'op provider fails safely when vaults cannot be listed' {
  export MOCK_VAULT_FAIL=yes
  run "$EXT" create --provider op
  [ "$status" -ne 0 ]
  [[ "$output" == *'could not list 1Password vaults'* ]]
  [ ! -e "$MOCK_LOG" ]
}

@test 'op provider prints the plain public key, not identity metadata' {
  run "$EXT" create --provider op --op-account example.1password.com --op-vault Personal --yes
  [ "$status" -eq 0 ]
  [[ "$output" == *"$(<"$MOCK_PUB")"* ]]
  [[ "$output" != *'[op]'* ]]
  [[ "$output" != *'item created'* ]]
  [ "$(wc -l < "$MOCK_LOG")" -eq 3 ]
}

@test 'op provider does not create a duplicate 1Password item' {
  export MOCK_OP_EXISTS=yes
  run "$EXT" create --provider op --op-account example.1password.com --op-vault Personal --yes
  [ "$status" -ne 0 ]
  [[ "$output" == *'item already exists'* ]]
  [ ! -e "$MOCK_LOG" ]
}

@test 'op provider stops on a vault access failure' {
  export MOCK_OP_FAIL=yes
  run "$EXT" create --provider op --op-account example.1password.com --op-vault Personal --yes
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
