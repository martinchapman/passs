# passs

Abstraction over [unix pass](https://www.passwordstore.org/) enforcing directory structure rules and more.

## Installation

passs requires `pass` and `jq`.

```sh
sh -c "$(curl -fsSL https://raw.githubusercontent.com/martinchapman/passs/main/install.sh)"
```

## Development

Tests use shunit2.

On Ubuntu/Debian:

```sh
sudo apt-get install jq shunit2
make test
```
