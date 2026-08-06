# specci-public

Documentation and tools for working with Specci.

## Install

```sh
curl -fsSL https://get.specci.ai | sh
```

It asks for your token and installs. The token is **masked as you type** — it never reaches your terminal's scrollback, a screenshot, or a screen share.

Piping a script into a shell asks you to trust it sight-unseen, so the installer is published here in full. Read it first if you'd rather:

```sh
curl -fsSL https://get.specci.ai | less
```

## What the installer does

1. Detects your platform and maps it to a target triple. An unsupported machine is refused here, before you are asked for anything.
2. Fetches the release manifest, authenticated with your token.
3. Resolves the right artefact for your platform and downloads it.
4. **Verifies the SHA-256 and refuses to install on mismatch.**
5. Installs into `~/.local/bin`, then tells you if that directory is not on your `PATH`.

It also stores your licence, so upgrades need no further prompting.

No toolchain, no clone, no compile. It uses no `sudo`, starts no background processes, and does not modify your shell configuration. It writes two things: the binary, and your licence under `~/.specci`.

## Upgrade

```sh
specci setup upgrade
```

Checks the release channel, verifies the download against its published checksum, and replaces the binary in place. `specci setup upgrade --check` reports what is available without changing anything.

## Uninstall

```sh
specci setup uninstall
```

It tells you exactly what it will remove before doing it, and never touches a repository — your `.specci/` directories are left alone.

Your stored licence is kept, so reinstalling needs no new token. To remove that too:

```sh
specci setup activate --forget
```

## Supported platforms

macOS on Apple Silicon (`aarch64-apple-darwin`).

Intel Macs and Linux are planned. Until then the installer refuses them with an explicit message rather than a confusing failure part way through.

## Appendix: unattended installs

For CI, container builds and provisioning — anywhere there is no terminal to be asked at.

**Prefer a file over an environment variable.** A file is not visible to child processes or to `ps -E`, and never reaches shell history:

```sh
curl -fsSL https://get.specci.ai | SPECCI_TOKEN_FILE=/run/secrets/specci sh
```

The environment variable works too, and is the least private option — written inline it is recorded verbatim in your shell history:

```sh
curl -fsSL https://get.specci.ai | SPECCI_TOKEN=<token> sh
```

| Variable | Default | Purpose |
| --- | --- | --- |
| `SPECCI_TOKEN_FILE` | — | path to a file whose first line is the token |
| `SPECCI_TOKEN` | — | the token itself |
| `SPECCI_INSTALL_DIR` | `$HOME/.local/bin` | where binaries land |
| `SPECCI_CHANNEL` | `stable` | release channel |
| `SPECCI_DL_BASE` | `https://dl.specci.ai` | download host |

Resolution order is `SPECCI_TOKEN`, then `SPECCI_TOKEN_FILE`, then the prompt. With none of them and no terminal, the installer refuses rather than hanging.

## Licence

MIT — see [LICENSE](LICENSE). It covers the contents of this repository only. Specci itself is proprietary and licensed separately; nothing here grants any right to it.
