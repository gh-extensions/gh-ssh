# gh-ssh

> Set up GitHub SSH authentication and commit signing keys in one command — with a passphrase-protected file or optional 1Password integration.

[![CI](https://github.com/gh-extensions/gh-ssh/actions/workflows/ci.yml/badge.svg)](https://github.com/gh-extensions/gh-ssh/actions/workflows/ci.yml)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)

`gh ssh` creates or accepts a public key, registers it for both GitHub SSH
access and commit signing, and prints an optional identity-file snippet.
Private keys are never sent to GitHub or printed by the extension.

## Requirements

- [GitHub CLI](https://cli.github.com/) (`gh`), signed in
- [Bash](https://www.gnu.org/software/bash/) 4.4+ (`bash`)
- [jq](https://jqlang.github.io/jq/) (`jq`)
- [OpenSSH](https://www.openssh.com/) (`ssh-keygen`)
- [Gum](https://github.com/charmbracelet/gum) (`gum`, for `create`)
- [1Password CLI](https://developer.1password.com/docs/cli/) (`op`, only for `create --provider op`)

**macOS (Homebrew):**

```bash
brew install gh bash jq gum
```

OpenSSH is included with macOS. Install `op` separately if using 1Password.

**Nix:**

```bash
nix profile install nixpkgs#gh nixpkgs#bash nixpkgs#jq nixpkgs#gum nixpkgs#openssh
```

The flake's dev shell and package include these tools, but not the optional `op` CLI.

## Installation

```bash
gh extension install gh-extensions/gh-ssh
```

This repository is private for now; installation requires access to the org.
There is no tagged release yet, so installation follows `main`.

**Nix:** the flake exposes a package with its runtime tools on `PATH`. With
Home Manager, add it to `programs.gh.extensions`:

```nix
{
  inputs.gh-ssh.url = "github:gh-extensions/gh-ssh";

  # In a Home Manager module:
  programs.gh.extensions = [ inputs.gh-ssh.packages.${system}.default ];
}
```

## Usage

```bash
gh ssh create [--provider file|op] [--path PATH] [--title TITLE] [--yes]
gh ssh create --provider op [--op-account ACCOUNT] [--op-vault VAULT] [--op-item TITLE]
gh ssh add --public-key PATH [--title TITLE]
gh ssh status [--public-key PATH]
```

### Create

Generate a new Ed25519 key in `~/.ssh` (default) or inside 1Password:

```bash
gh ssh create
gh ssh create --provider op                              # active account; choose vault
gh ssh create --provider op --op-account my.1password.com --op-vault Personal
```

The file provider defaults to `~/.ssh/id_ed25519_github`; `--path` changes it.
`ssh-keygen` prompts for a passphrase and the extension refuses an empty one.
Neither provider replaces an existing key or 1Password item. `--yes` skips the
Gum confirmation, **not** the passphrase or 1Password unlock prompt.

With `--provider op`, the account defaults to the currently signed-in account
(`op whoami`); when no vault is given, Gum lists that account's vaults for you
to choose from. The confirmation names the resolved account and vault. For
`--yes`, **both** `--op-account` and `--op-vault` are required so automation
cannot silently use a different account. `--op-item` sets the 1Password item
title (default: `GitHub SSH Key`); `--title` sets the GitHub key title. The
extension never accepts a private key or passphrase as a command-line argument.

### Add an existing key

```bash
gh ssh add --public-key ~/.ssh/id_ed25519.pub
```

Only the **public** `.pub` file is read. If the key is already registered for
authentication or signing, that registration is skipped. If one registration
fails, rerun `add` with the same public key to complete the other.

`create` and `add` print a public-key-only TOML snippet for an identity file:

```toml
[ssh]
publicKey = "ssh-ed25519 AAAA..."
```

The 1Password provider also prints `[op]` with its account and vault. Nothing
is written to your identity file automatically. Never add a private key to it.

### Status

```bash
gh ssh status                                      # list registered key titles
gh ssh status --public-key ~/.ssh/id_ed25519.pub  # check both registrations
```

`status --public-key` returns a nonzero exit code unless the key is present for
both authentication and signing. If GitHub reports a missing permission, grant
both scopes to your existing `gh` login (the extension does not do this for you):

```bash
gh auth refresh -h github.com -s admin:public_key,admin:ssh_signing_key
```

A failed API request never displays its JSON error as a key or prints a partial
list. The command reports which scope may be missing instead.

## Configuration and security

If your organization uses SAML SSO, authorize the **authentication** key in
GitHub's SSH key settings after registering it. This step is not automated.

This extension relies on your existing `gh` login; it creates no GitHub token.
It does not store a private key for `add`, and the 1Password provider keeps its
private key in the vault. The file provider keeps its private key locally under
`~/.ssh`. Run `gh ssh --help` for the full command reference.

## The gh-extensions Ecosystem

| Repo | What it provides |
| --- | --- |
| [gh-ai](https://github.com/gh-extensions/gh-ai) | AI-powered GitHub CLI workflows |
| [gh-fzf](https://github.com/gh-extensions/gh-fzf) | Fuzzy finding for GitHub resources |
| **gh-ssh** ← you are here | GitHub SSH authentication and signing setup |
| [gh-worktree](https://github.com/gh-extensions/gh-worktree) | Isolated worktrees for PRs, issues, and runs |

## Development

```bash
nix develop
bats tests/
shellcheck gh-ssh scripts/*.sh
```

Tests mock `gh`, `op`, and GitHub API calls; they do not change a real account.

## License

[MIT](LICENSE) — Copyright (c) 2026 gh-extensions contributors
