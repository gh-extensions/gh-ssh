#!/usr/bin/env bats
load test_helper

@test 'status matches an existing public key in both GitHub lists' {
  export MOCK_REGISTERED=yes
  run "$EXT" status --public-key "$MOCK_PUB"
  [ "$status" -eq 0 ]
  [[ "$output" == *'Authentication: registered'* ]]
  [[ "$output" == *'Signing: registered'* ]]
}
