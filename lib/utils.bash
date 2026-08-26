#!/usr/bin/env bash

AGG_GIT_REPOSITORY=https://github.com/asciinema/agg.git
AGG_RELEASES_URL=https://github.com/asciinema/agg/releases
TOOL_NAME=agg

fail() {
	printf 'asdf-%s: %s\n' "$TOOL_NAME" "$*" >&2
	exit 1
}

require_value() {
	local name=$1
	local value=$2

	if [ -z "$value" ]; then
		fail "$name is required"
	fi
}

stable_versions_from_tags() {
	awk '
		/^v?[0-9]+\.[0-9]+\.[0-9]+$/ {
			sub(/^v/, "")
			print
		}
	'
}

sort_versions() {
	LC_ALL=C sort -t. -k1,1n -k2,2n -k3,3n
}

list_remote_tags() {
	git ls-remote --tags --refs "$AGG_GIT_REPOSITORY" |
		awk '{sub(/^refs\/tags\//, "", $2); print $2}'
}

list_all_versions() {
	local versions

	versions=$(list_remote_tags | stable_versions_from_tags | sort_versions)
	if [ -z "$versions" ]; then
		fail "no installable stable releases found"
	fi

	printf '%s\n' "$versions"
}

latest_stable_from_versions() {
	local query=${1:-}

	awk -v query="$query" '
		query == "" || index($0, query) == 1 { latest = $0 }
		END {
			if (latest == "") {
				exit 1
			}
			print latest
		}
	'
}

validate_release_version() {
	local version=$1

	if [[ ! "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
		fail "unsupported version '$version'; only stable semantic releases are installable"
	fi
}

release_asset() {
	local os=$1
	local architecture=$2
	local libc=${3:-}
	local target_os
	local target_architecture

	case "$architecture" in
	x86_64 | amd64)
		target_architecture=x86_64
		;;
	aarch64 | arm64)
		target_architecture=aarch64
		;;
	*)
		fail "unsupported platform: ${os}/${architecture}"
		;;
	esac

	case "$os" in
	Linux | linux)
		case "$libc" in
		gnu)
			target_os=unknown-linux-gnu
			;;
		musl)
			if [ "$target_architecture" != "x86_64" ]; then
				fail "unsupported platform: ${os}/${architecture} (libc: $libc)"
			fi
			target_os=unknown-linux-musl
			;;
		*)
			fail "unsupported platform: ${os}/${architecture} (libc: ${libc:-unknown})"
			;;
		esac
		;;
	Darwin | darwin)
		target_os=apple-darwin
		;;
	*)
		fail "unsupported platform: ${os}/${architecture}"
		;;
	esac

	printf 'agg-%s-%s\n' "$target_architecture" "$target_os"
}

detect_libc() {
	local os=$1
	local architecture=$2
	local output

	if [ "$os" != "Linux" ] && [ "$os" != "linux" ]; then
		printf '\n'
		return
	fi

	if command -v getconf >/dev/null 2>&1 && output=$(getconf GNU_LIBC_VERSION 2>/dev/null); then
		case "$output" in
		glibc\ *)
			printf 'gnu\n'
			return
			;;
		esac
	fi

	if command -v ldd >/dev/null 2>&1; then
		output=$(ldd --version 2>&1 || true)
		case "$output" in
		*musl*)
			printf 'musl\n'
			return
			;;
		*GLIBC* | *"GNU libc"* | *"GNU C Library"*)
			printf 'gnu\n'
			return
			;;
		esac
	fi

	fail "unsupported platform: ${os}/${architecture} (libc: unknown)"
}

release_url() {
	local version=$1
	local os=$2
	local architecture=$3
	local libc=${4:-}
	local asset

	validate_release_version "$version"
	asset=$(release_asset "$os" "$architecture" "$libc")
	printf '%s/download/v%s/%s\n' "$AGG_RELEASES_URL" "$version" "$asset"
}

download_release() {
	local version=$1
	local destination=$2
	local os=$3
	local architecture=$4
	local libc=$5
	local url

	url=$(release_url "$version" "$os" "$architecture" "$libc")
	printf '* Downloading agg %s for %s/%s...\n' "$version" "$os" "$architecture" >&2

	if ! curl \
		--fail \
		--location \
		--silent \
		--show-error \
		--retry 3 \
		--output "$destination" \
		"$url"; then
		fail "could not download $url"
	fi
}

verify_agg_binary() {
	local binary=$1
	local version=$2
	local output

	if [ ! -s "$binary" ] || [ ! -x "$binary" ]; then
		fail "downloaded artifact is not a non-empty executable"
	fi

	if ! output=$("$binary" --version 2>&1); then
		fail "downloaded artifact could not run: $output"
	fi

	if [ "$output" != "agg $version" ]; then
		fail "downloaded artifact reported '$output', expected 'agg $version'"
	fi
}

install_version() {
	local install_type=$1
	local version=$2
	local download_path=$3
	local install_path=$4
	local source_binary
	local install_parent
	local staging_path

	if [ "$install_type" != "version" ]; then
		fail "release installs only; ASDF_INSTALL_TYPE was '$install_type'"
	fi

	validate_release_version "$version"
	source_binary="${download_path}/agg"
	verify_agg_binary "$source_binary" "$version"

	if [ -e "$install_path" ] && [ ! -d "$install_path" ]; then
		fail "install path exists and is not a directory: $install_path"
	fi

	if [ -d "$install_path" ] && [ -n "$(ls -A "$install_path")" ]; then
		fail "install path is not empty: $install_path"
	fi

	install_parent=$(dirname "$install_path")
	mkdir -p "$install_parent"
	staging_path=$(mktemp -d "${install_path}.tmp.XXXXXX") || fail "could not create installation staging directory"
	chmod 755 "$staging_path"

	# Invoked indirectly by the trap below.
	# shellcheck disable=SC2329
	cleanup_install_staging() {
		if [ -n "$staging_path" ] && [ -d "$staging_path" ]; then
			rm -rf "$staging_path"
		fi
	}
	trap cleanup_install_staging EXIT

	mkdir -p "${staging_path}/bin"
	cp "$source_binary" "${staging_path}/bin/agg"
	chmod 755 "${staging_path}/bin/agg"
	verify_agg_binary "${staging_path}/bin/agg" "$version"

	if [ -d "$install_path" ]; then
		rmdir "$install_path" || fail "could not replace the empty install path: $install_path"
	fi
	mv "$staging_path" "$install_path"
	staging_path=
	trap - EXIT
	printf 'agg %s installation was successful\n' "$version" >&2
}
