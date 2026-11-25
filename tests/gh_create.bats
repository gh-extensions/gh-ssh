#!/usr/bin/env bats
load test_helper

@test 'op provider creates an item and prints identity metadata without private material' {
  run "$EXT" create --provider op --op-account example.1password.com --op-vault Personal --yes
  [ "$status" -eq 0 ]
  [[ "$output" == *'[op]'* ]]
  [[ "$output" == *'account = "example.1password.com"'* ]]
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
