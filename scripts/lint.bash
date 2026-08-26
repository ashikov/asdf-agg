#!/usr/bin/env bash

set -euo pipefail

repo_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
cd "$repo_dir"

shellcheck --shell=bash --external-sources --source-path=SCRIPTDIR \
	bin/* \
	lib/* \
	scripts/* \
	test/*.bash \
	test/fixtures/curl \
	test/fixtures/getconf \
	test/fixtures/ldd \
	test/fixtures/uname

shfmt --language-dialect bash --diff \
	bin/* \
	lib/* \
	scripts/* \
	test/*.bash \
	test/fixtures/curl \
	test/fixtures/getconf \
	test/fixtures/ldd \
	test/fixtures/uname
