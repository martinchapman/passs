# passs

Abstraction over [unix pass](https://www.passwordstore.org/) enforcing directory structure rules and more.

## Installation

passs requires `pass` and `jq`.

```sh
sh -c "$(curl -fsSL https://raw.githubusercontent.com/martinchapman/passs/main/install.sh)"
```

## Vault

Entries under `vault/` are pushed as a single encrypted file (`.vault.enc`), so their names never reach the remote.
`passs git push` encrypts the vault before pushing, and `passs git pull` decrypts it after pulling.

## Development

Tests use shunit2.

On Ubuntu/Debian:

```sh
sudo apt-get install jq shunit2
make test
```
