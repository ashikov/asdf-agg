# asdf-agg

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)

An [asdf](https://asdf-vm.com/) plugin for installing and managing
[`agg`](https://github.com/asciinema/agg), the asciinema cast-to-GIF renderer.

The plugin installs official prebuilt `agg` release binaries. It does not require Rust or Cargo.

## Requirements

- [asdf](https://asdf-vm.com/) 0.16.0 or newer
- Bash, Git, curl, and standard Unix command-line tools

asdf 0.16.0 is the oldest supported version and is checked separately on Linux x86_64 by a real add, resolve, install, select, and `asdf exec` integration gate.

## Install

Until this plugin is accepted into the asdf shortname index, add it with its repository URL:

```sh
asdf plugin add agg https://github.com/ashikov/asdf-agg.git
```

## Usage

List stable versions and resolve the latest one:

```sh
asdf list all agg
asdf latest agg
```

Install and select the latest stable version for the current project:

```sh
asdf install agg latest
asdf set agg latest
asdf exec agg --version
```

With the selected version on the asdf shim path, a typical conversion is:

```sh
agg demo.cast demo.gif
```

See the [agg documentation](https://github.com/asciinema/agg) for renderer options and input requirements.

## Supported platforms

| Operating system | Architecture | C library |
| --- | --- | --- |
| Linux | x86_64/amd64 | glibc or musl |
| Linux | arm64/aarch64 | glibc |
| macOS | x86_64 | system |
| macOS | arm64/aarch64 | system |

Only stable releases are listed. Linux x86_64/amd64 uses the official portable musl release binary on both glibc and musl hosts, avoiding a dependency on the minimum glibc version of each upstream release. Linux arm64 musl is unsupported because upstream does not publish a matching binary. Windows and 32-bit ARM assets are outside this plugin's supported scope.

Linux arm64/aarch64 continues to use the upstream GNU binary because no official musl ARM64 asset is available. Its glibc requirement can vary between upstream releases; for `agg` 1.9.0, that binary requires glibc 2.18.

Upstream releases do not currently include standalone checksum files. Downloads use HTTPS and are accepted only when the artifact is non-empty, executable, runs successfully, and reports the requested version exactly.

See [CONTRIBUTING.md](CONTRIBUTING.md) for contribution guidelines.

## License

MIT — see [LICENSE](LICENSE).
