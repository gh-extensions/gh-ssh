#!/usr/bin/env bats
load test_helper

@test 'add registers both key types without printing project-specific output' {
  run "$EXT" add --public-key "$MOCK_PUB" --title test
  [ "$status" -eq 0 ]
  [[ "$output" == *'Registered authentication key'* ]]
  [[ "$output" == *'Registered signing key'* ]]
  [[ "$output" != *'[ssh]'* ]]
  [[ "$output" != *"$(<"$MOCK_PUB")"* ]]
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
