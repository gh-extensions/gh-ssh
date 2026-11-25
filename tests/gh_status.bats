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

@test 'status with a public key fails clearly when a scope is missing' {
  export MOCK_API_FAIL=user/ssh_signing_keys
  run "$EXT" status --public-key "$MOCK_PUB"
  [ "$status" -ne 0 ]
  [[ "$output" == *'gh auth refresh -h github.com -s admin:ssh_signing_key'* ]]
  [[ "$output" != *'"message"'* ]]
}
