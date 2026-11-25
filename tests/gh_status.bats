#!/usr/bin/env bats
load test_helper

@test 'status lists both key types after successful API calls' {
  export MOCK_REGISTERED=yes
  run "$EXT" status
  [ "$status" -eq 0 ]
  [[ "$output" == *'Authentication keys:'* ]]
  [[ "$output" == *'Signing keys:'* ]]
  [[ "$output" == *'existing (1)'* ]]
}

@test 'status does not print a 404 body when authentication scope is missing' {
  export MOCK_API_FAIL=user/keys
  run "$EXT" status
  [ "$status" -ne 0 ]
  [[ "$output" == *'gh auth refresh -h github.com -s admin:public_key'* ]]
  [[ "$output" != *'"message"'* ]]
  [[ "$output" != *'Authentication keys:'* ]]
}

@test 'status does not print partial results when signing scope is missing' {
  export MOCK_API_FAIL=user/ssh_signing_keys
  run "$EXT" status
  [ "$status" -ne 0 ]
  [[ "$output" == *'gh auth refresh -h github.com -s admin:ssh_signing_key'* ]]
  [[ "$output" != *'"message"'* ]]
  [[ "$output" != *'Authentication keys:'* ]]
  [[ "$output" != *'Signing keys:'* ]]
}

@test 'status matches an existing public key in both GitHub lists' {
  export MOCK_REGISTERED=yes
  run "$EXT" status --public-key "$MOCK_PUB"
  [ "$status" -eq 0 ]
  [[ "$output" == *'Authentication: registered'* ]]
  [[ "$output" == *'Signing: registered'* ]]
}

@test '1Password status checks age, GitHub registration and an expected key' {
  export MOCK_OP_EXISTS=yes MOCK_REGISTERED=yes
  run "$EXT" status --provider op --op-account example.1password.com \
    --op-vault Personal --expected-public-key "$MOCK_PUB"
  [ "$status" -eq 0 ]
  [[ "$output" == *'Created: 2023-01-01 ('* ]]
  [[ "$output" == *'consider rotating'* ]]
  [[ "$output" == *'Expected public key: matches'* ]]
  [[ "$output" == *'Authentication: registered'* ]]
  [[ "$output" == *'Signing: registered'* ]]
  [[ "$output" != *'PRIVATE KEY'* ]]
}

@test '1Password status detects a different expected key' {
  export MOCK_OP_EXISTS=yes MOCK_REGISTERED=yes
  ssh-keygen -q -t ed25519 -N '' -f "$BATS_TEST_TMPDIR/other"
  run "$EXT" status --provider op --op-account example.1password.com \
    --op-vault Personal --expected-public-key "$BATS_TEST_TMPDIR/other.pub"
  [ "$status" -ne 0 ]
  [[ "$output" == *'Expected public key: DIFFERENT'* ]]
}

@test '1Password status shows missing date without reading the full item' {
  export MOCK_OP_EXISTS=yes MOCK_OP_NO_DATE=yes MOCK_REGISTERED=yes
  run "$EXT" status --provider op --op-account example.1password.com --op-vault Personal
  [ "$status" -eq 0 ]
  [[ "$output" == *'Created: unavailable'* ]]
}

@test '1Password status fails when the selected item is absent' {
  run "$EXT" status --provider op --op-account example.1password.com --op-vault Personal
  [ "$status" -ne 0 ]
  [[ "$output" == *'expected one item'* ]]
}

@test '1Password status can select the active account and vault' {
  export MOCK_OP_EXISTS=yes MOCK_REGISTERED=yes
  run "$EXT" status --provider op
  [ "$status" -eq 0 ]
  [[ "$output" == *'example.1password.com / Personal'* ]]
}

@test 'status with a public key fails clearly when a scope is missing' {
  export MOCK_API_FAIL=user/ssh_signing_keys
  run "$EXT" status --public-key "$MOCK_PUB"
  [ "$status" -ne 0 ]
  [[ "$output" == *'gh auth refresh -h github.com -s admin:ssh_signing_key'* ]]
  [[ "$output" != *'"message"'* ]]
}
