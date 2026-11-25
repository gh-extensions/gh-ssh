# gh-ssh

Set up SSH authentication and commit signing keys with GitHub from your terminal.
`gh ssh` is a Bash-based [GitHub CLI extension](https://cli.github.com/manual/gh_extension).
Private keys are never sent to GitHub or printed by this tool.

## Requirements

- `gh`, Bash 4.4+, `jq`, `ssh-keygen`
- `gum` for interactive key creation
- `op` only for `create --provider op` (1Password CLI, signed in and unlocked)

On macOS: `brew install gh bash jq gum`; OpenSSH comes with macOS.
With Nix: `nix develop` provides all tools except the optional `op` CLI.

## Installation

```sh
gh extension install gh-extensions/gh-ssh
```

While this repo is private, you need GitHub access to the organization.

## Usage

```sh
gh ssh add --public-key ~/.ssh/id_ed25519.pub       # existing public key

gh ssh create                                       # encrypted key in ~/.ssh
gh ssh create --provider op --op-account my.1password.com --op-vault Personal

gh ssh status
gh ssh status --public-key ~/.ssh/id_ed25519.pub
```

`create` asks for confirmation and `ssh-keygen` asks for a passphrase when using
`~/.ssh`. It refuses to replace an existing key. `--path` changes the default
`~/.ssh/id_ed25519_github`; `--title` sets the title of both GitHub keys.
`--yes` skips the confirmation but **not** the passphrase prompt. With `op`,
`--op-item` changes the item title (default `GitHub SSH Key`). Avoid creating a
second item with the same title in the same vault. The `op` CLI may prompt for
Touch ID; no credentials are accepted as command-line arguments.

Both `create` and `add` register the public key once for GitHub authentication
and once for commit signing. If only one succeeds, rerun `add` with the same
public key: an already registered key is skipped. They print a public-key-only
TOML snippet for an identity file (including `[op]` when relevant). The snippet
is output, not a file edit, and does not contain a private key.

If your organization uses SAML SSO, authorize the authentication key in GitHub's
SSH key settings after registering it. This step is not automated.

Run `gh ssh --help` for all options. Never commit a private key or place one in
an identity file.

## Development

```sh
nix develop
bats tests/
shellcheck gh-ssh scripts/*.sh
```

The repo follows the org's Bash-extension layout: root executable, `scripts/`,
Bats tests, a Nix package/dev shell, and CI. All tests use fake `gh`, `op`, and
`ssh-keygen`; they never change a real account or key.
