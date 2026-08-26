#!/usr/bin/env bash

set -euo pipefail

repo_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)

# shellcheck source=../lib/utils.bash
source "${repo_dir}/lib/utils.bash"

tests_run=0
tests_failed=0

assert_equal() {
	local expected=$1
	local actual=$2
	local message=${3:-values should be equal}

	if [ "$actual" != "$expected" ]; then
		printf '    %s\n    expected: %s\n    actual:   %s\n' "$message" "$expected" "$actual" >&2
		exit 1
	fi
}

assert_contains() {
	local haystack=$1
	local needle=$2
	local message=${3:-value should contain substring}

	case "$haystack" in
	*"$needle"*) ;;
	*)
		printf '    %s\n    expected substring: %s\n    actual: %s\n' "$message" "$needle" "$haystack" >&2
		exit 1
		;;
	esac
}

assert_executable() {
	local path=$1

	if [ ! -x "$path" ]; then
		printf '    expected executable: %s\n' "$path" >&2
		exit 1
	fi
}

assert_path_absent() {
	local path=$1

	if [ -e "$path" ]; then
		printf '    expected path to be absent: %s\n' "$path" >&2
		exit 1
	fi
}

assert_directory_empty() {
	local path=$1
	local entry

	entry=$(ls -A "$path")
	if [ -n "$entry" ]; then
		printf '    expected empty directory: %s\n    found: %s\n' "$path" "$entry" >&2
		exit 1
	fi
}

run_test() {
	local name=$1
	shift
	tests_run=$((tests_run + 1))

	if ("$@"); then
		printf 'ok %d - %s\n' "$tests_run" "$name"
	else
		printf 'not ok %d - %s\n' "$tests_run" "$name"
		tests_failed=$((tests_failed + 1))
	fi
}

make_fake_agg() {
	local path=$1
	local version=$2

	printf '%s\n' \
		'#!/usr/bin/env bash' \
		"printf 'agg %s\\n' '$version'" >"$path"
	chmod +x "$path"
}

capture_failure() {
	local output_variable=$1
	local status_variable=$2
	shift 2
	local captured_output
	local captured_status

	set +e
	captured_output=$("$@" 2>&1)
	captured_status=$?
	set -e
	printf -v "$output_variable" '%s' "$captured_output"
	printf -v "$status_variable" '%s' "$captured_status"
}

test_stable_version_filtering_and_ordering() {
	local actual
	local expected

	actual=$(stable_versions_from_tags <"${repo_dir}/test/fixtures/tags.txt" | sort_versions)
	expected=$(printf '%s\n' 1.0.0 1.4.3 1.9.0 1.9.2 1.9.10 1.10.0 2.0.0)

	assert_equal "$expected" "$actual" "stable versions should be normalized and sorted semantically"
}

test_latest_stable_selection() {
	local versions
	local latest
	local latest_minor

	versions=$(stable_versions_from_tags <"${repo_dir}/test/fixtures/tags.txt" | sort_versions)
	latest=$(printf '%s\n' "$versions" | latest_stable_from_versions "")
	latest_minor=$(printf '%s\n' "$versions" | latest_stable_from_versions "1.9")

	assert_equal "2.0.0" "$latest" "a prerelease must not supersede the latest stable version"
	assert_equal "1.9.10" "$latest_minor" "latest-stable should honor the asdf version prefix"

	if printf '%s\n' "$versions" | latest_stable_from_versions "9" >/dev/null; then
		printf '    a missing latest-stable prefix should fail\n' >&2
		exit 1
	fi
}

test_release_version_validation() {
	local output
	local status

	validate_release_version 1.9.0

	for invalid in v1.9.0 1.9 1.9.0-rc.1 1.9.0-beta.2 latest main ''; do
		capture_failure output status validate_release_version "$invalid"
		assert_equal "1" "$status" "invalid or unstable version '$invalid' should fail"
		assert_contains "$output" "unsupported version" "invalid version errors should be explicit"
	done
}

test_supported_platform_mappings() {
	assert_equal "agg-x86_64-unknown-linux-gnu" "$(release_asset Linux x86_64 gnu)"
	assert_equal "agg-x86_64-unknown-linux-gnu" "$(release_asset linux amd64 gnu)"
	assert_equal "agg-aarch64-unknown-linux-gnu" "$(release_asset Linux arm64 gnu)"
	assert_equal "agg-aarch64-unknown-linux-gnu" "$(release_asset Linux aarch64 gnu)"
	assert_equal "agg-x86_64-unknown-linux-musl" "$(release_asset Linux x86_64 musl)"
	assert_equal "agg-x86_64-apple-darwin" "$(release_asset Darwin x86_64 '')"
	assert_equal "agg-aarch64-apple-darwin" "$(release_asset darwin arm64 '')"
	assert_equal "agg-aarch64-apple-darwin" "$(release_asset Darwin aarch64 '')"
}

test_unsupported_platform_errors() {
	local output
	local status

	capture_failure output status release_asset FreeBSD x86_64 gnu
	assert_equal "1" "$status" "unsupported operating systems should fail"
	assert_contains "$output" "FreeBSD/x86_64" "the error should include the detected platform"

	capture_failure output status release_asset Linux riscv64 gnu
	assert_equal "1" "$status" "unsupported architectures should fail"
	assert_contains "$output" "Linux/riscv64" "the error should include the detected platform"

	capture_failure output status release_asset Linux arm64 musl
	assert_equal "1" "$status" "Linux arm64 musl has no official asset"
	assert_contains "$output" "Linux/arm64" "the error should include the detected platform"
	assert_contains "$output" "musl" "the error should include the detected libc"

	capture_failure output status release_asset Linux x86_64 unknown
	assert_equal "1" "$status" "unknown Linux libc should fail"
	assert_contains "$output" "libc: unknown" "the error should include the detected libc"
}

test_libc_detection() {
	local detected
	local output
	local status

	detected=$(PATH="${repo_dir}/test/fixtures:${PATH}" FAKE_GETCONF_MODE=gnu detect_libc Linux x86_64)
	assert_equal "gnu" "$detected" "getconf should identify glibc"

	detected=$(PATH="${repo_dir}/test/fixtures:${PATH}" FAKE_GETCONF_MODE=fail FAKE_LDD_MODE=musl detect_libc Linux x86_64)
	assert_equal "musl" "$detected" "ldd should identify musl when getconf is unavailable"

	detected=$(PATH="${repo_dir}/test/fixtures:${PATH}" FAKE_GETCONF_MODE=fail FAKE_LDD_MODE=gnu detect_libc Linux arm64)
	assert_equal "gnu" "$detected" "ldd should identify glibc when getconf is unavailable"

	detected=$(detect_libc Darwin arm64)
	assert_equal "" "$detected" "non-Linux platforms should not have a libc target"

	set +e
	output=$(PATH="${repo_dir}/test/fixtures:${PATH}" FAKE_GETCONF_MODE=fail FAKE_LDD_MODE=unknown detect_libc Linux x86_64 2>&1)
	status=$?
	set -e
	assert_equal "1" "$status" "unknown Linux libc should fail"
	assert_contains "$output" "libc: unknown" "unknown libc errors should be explicit"
}

test_release_urls() {
	assert_equal \
		"https://github.com/asciinema/agg/releases/download/v1.9.0/agg-x86_64-unknown-linux-gnu" \
		"$(release_url 1.9.0 Linux x86_64 gnu)"
	assert_equal \
		"https://github.com/asciinema/agg/releases/download/v1.9.0/agg-x86_64-unknown-linux-musl" \
		"$(release_url 1.9.0 Linux amd64 musl)"
	assert_equal \
		"https://github.com/asciinema/agg/releases/download/v1.9.0/agg-aarch64-unknown-linux-gnu" \
		"$(release_url 1.9.0 Linux arm64 gnu)"
	assert_equal \
		"https://github.com/asciinema/agg/releases/download/v1.9.0/agg-x86_64-apple-darwin" \
		"$(release_url 1.9.0 Darwin x86_64 '')"
	assert_equal \
		"https://github.com/asciinema/agg/releases/download/v1.9.0/agg-aarch64-apple-darwin" \
		"$(release_url 1.9.0 Darwin arm64 '')"
}

test_binary_validation() {
	local test_dir
	local artifact
	local output
	local status

	test_dir=$(mktemp -d "${TMPDIR:-/tmp}/asdf-agg-validation.XXXXXX")
	trap 'rm -rf "$test_dir"' RETURN
	artifact="${test_dir}/agg"

	: >"$artifact"
	chmod +x "$artifact"
	capture_failure output status verify_agg_binary "$artifact" 1.9.0
	assert_equal "1" "$status" "empty artifacts should fail"

	make_fake_agg "$artifact" 1.9.0
	chmod -x "$artifact"
	capture_failure output status verify_agg_binary "$artifact" 1.9.0
	assert_equal "1" "$status" "non-executable artifacts should fail"

	make_fake_agg "$artifact" 9.9.9
	capture_failure output status verify_agg_binary "$artifact" 1.9.0
	assert_equal "1" "$status" "version mismatches should fail"
	assert_contains "$output" "agg 9.9.9" "mismatch errors should include actual output"

	printf '#!/usr/bin/env bash\nexit 42\n' >"$artifact"
	chmod +x "$artifact"
	capture_failure output status verify_agg_binary "$artifact" 1.9.0
	assert_equal "1" "$status" "artifacts that cannot run should fail"
}

test_download_places_verified_binary_only() {
	local test_dir
	local source_binary
	local download_dir
	local url_log

	test_dir=$(mktemp -d "${TMPDIR:-/tmp}/asdf-agg-download.XXXXXX")
	trap 'rm -rf "$test_dir"' RETURN
	source_binary="${test_dir}/upstream-binary"
	download_dir="${test_dir}/download"
	url_log="${test_dir}/url"
	make_fake_agg "$source_binary" 1.9.0

	PATH="${repo_dir}/test/fixtures:${PATH}" \
		FAKE_CURL_SOURCE="$source_binary" \
		FAKE_CURL_URL_LOG="$url_log" \
		FAKE_UNAME_OS=Linux \
		FAKE_UNAME_ARCH=x86_64 \
		FAKE_GETCONF_MODE=gnu \
		ASDF_INSTALL_TYPE=version \
		ASDF_INSTALL_VERSION=1.9.0 \
		ASDF_DOWNLOAD_PATH="$download_dir" \
		"${repo_dir}/bin/download"

	assert_executable "${download_dir}/agg"
	assert_equal "agg 1.9.0" "$("${download_dir}/agg" --version)"
	assert_equal \
		"https://github.com/asciinema/agg/releases/download/v1.9.0/agg-x86_64-unknown-linux-gnu" \
		"$(cat "$url_log")"
	assert_equal "1" "$(find "$download_dir" -type f | wc -l | tr -d ' ')" \
		"the download directory should contain only the ready binary"
}

test_download_failure_leaves_no_files() {
	local test_dir
	local source_binary
	local download_dir
	local status

	test_dir=$(mktemp -d "${TMPDIR:-/tmp}/asdf-agg-download-failure.XXXXXX")
	trap 'rm -rf "$test_dir"' RETURN
	source_binary="${test_dir}/partial"
	download_dir="${test_dir}/download"
	printf 'partial download\n' >"$source_binary"

	set +e
	PATH="${repo_dir}/test/fixtures:${PATH}" \
		FAKE_CURL_SOURCE="$source_binary" \
		FAKE_CURL_URL_LOG="${test_dir}/url" \
		FAKE_CURL_EXIT_CODE=22 \
		FAKE_CURL_WRITE_ON_FAILURE=1 \
		FAKE_UNAME_OS=Linux \
		FAKE_UNAME_ARCH=x86_64 \
		FAKE_GETCONF_MODE=gnu \
		ASDF_INSTALL_TYPE=version \
		ASDF_INSTALL_VERSION=1.9.0 \
		ASDF_DOWNLOAD_PATH="$download_dir" \
		"${repo_dir}/bin/download" >/dev/null 2>&1
	status=$?
	set -e

	assert_equal "1" "$status" "HTTP failures should fail the download"
	assert_directory_empty "$download_dir"
}

test_download_rejects_invalid_artifacts() {
	local test_dir
	local source_binary
	local download_dir
	local status

	test_dir=$(mktemp -d "${TMPDIR:-/tmp}/asdf-agg-invalid-download.XXXXXX")
	trap 'rm -rf "$test_dir"' RETURN
	source_binary="${test_dir}/response"
	download_dir="${test_dir}/download"
	printf '<html>not a release binary</html>\n' >"$source_binary"

	set +e
	PATH="${repo_dir}/test/fixtures:${PATH}" \
		FAKE_CURL_SOURCE="$source_binary" \
		FAKE_CURL_URL_LOG="${test_dir}/url" \
		FAKE_UNAME_OS=Linux \
		FAKE_UNAME_ARCH=x86_64 \
		FAKE_GETCONF_MODE=gnu \
		ASDF_INSTALL_TYPE=version \
		ASDF_INSTALL_VERSION=1.9.0 \
		ASDF_DOWNLOAD_PATH="$download_dir" \
		"${repo_dir}/bin/download" >/dev/null 2>&1
	status=$?
	set -e

	assert_equal "1" "$status" "invalid response content should fail"
	assert_directory_empty "$download_dir"

	: >"$source_binary"
	set +e
	PATH="${repo_dir}/test/fixtures:${PATH}" \
		FAKE_CURL_SOURCE="$source_binary" \
		FAKE_CURL_URL_LOG="${test_dir}/url" \
		FAKE_UNAME_OS=Linux \
		FAKE_UNAME_ARCH=x86_64 \
		FAKE_GETCONF_MODE=gnu \
		ASDF_INSTALL_TYPE=version \
		ASDF_INSTALL_VERSION=1.9.0 \
		ASDF_DOWNLOAD_PATH="$download_dir" \
		"${repo_dir}/bin/download" >/dev/null 2>&1
	status=$?
	set -e
	assert_equal "1" "$status" "empty response content should fail"
	assert_directory_empty "$download_dir"
}

test_install_creates_expected_executable() {
	local test_dir
	local download_dir
	local install_dir

	test_dir=$(mktemp -d "${TMPDIR:-/tmp}/asdf-agg-install.XXXXXX")
	trap 'rm -rf "$test_dir"' RETURN
	download_dir="${test_dir}/download"
	install_dir="${test_dir}/install"
	mkdir -p "$download_dir" "$install_dir"
	make_fake_agg "${download_dir}/agg" 1.9.0

	ASDF_INSTALL_TYPE=version \
		ASDF_INSTALL_VERSION=1.9.0 \
		ASDF_INSTALL_PATH="$install_dir" \
		ASDF_DOWNLOAD_PATH="$download_dir" \
		"${repo_dir}/bin/install"

	assert_executable "${install_dir}/bin/agg"
	assert_equal "agg 1.9.0" "$("${install_dir}/bin/agg" --version)"
	assert_path_absent "${install_dir}/bin/agg-x86_64-unknown-linux-gnu"
	assert_equal "1" "$(find "$install_dir" -type f | wc -l | tr -d ' ')" \
		"installation should not create nested or extra artifacts"
}

test_install_rejects_bad_artifacts_and_unsafe_paths() {
	local test_dir
	local download_dir
	local install_dir
	local output
	local status

	test_dir=$(mktemp -d "${TMPDIR:-/tmp}/asdf-agg-install-failure.XXXXXX")
	trap 'rm -rf "$test_dir"' RETURN
	download_dir="${test_dir}/download"
	install_dir="${test_dir}/install"
	mkdir -p "$download_dir"

	set +e
	ASDF_INSTALL_TYPE=version ASDF_INSTALL_VERSION=1.9.0 ASDF_INSTALL_PATH="$install_dir" \
		ASDF_DOWNLOAD_PATH="$download_dir" "${repo_dir}/bin/install" >/dev/null 2>&1
	status=$?
	set -e
	assert_equal "1" "$status" "a missing artifact should fail"
	assert_path_absent "$install_dir"

	make_fake_agg "${download_dir}/agg" 9.9.9
	set +e
	ASDF_INSTALL_TYPE=version ASDF_INSTALL_VERSION=1.9.0 ASDF_INSTALL_PATH="$install_dir" \
		ASDF_DOWNLOAD_PATH="$download_dir" "${repo_dir}/bin/install" >/dev/null 2>&1
	status=$?
	set -e
	assert_equal "1" "$status" "a mismatched artifact should fail"
	assert_path_absent "$install_dir"

	make_fake_agg "${download_dir}/agg" 1.9.0
	mkdir -p "$install_dir"
	printf 'keep\n' >"${install_dir}/sentinel"
	set +e
	ASDF_INSTALL_TYPE=version ASDF_INSTALL_VERSION=1.9.0 ASDF_INSTALL_PATH="$install_dir" \
		ASDF_DOWNLOAD_PATH="$download_dir" "${repo_dir}/bin/install" >/dev/null 2>&1
	status=$?
	set -e
	assert_equal "1" "$status" "a non-empty install path should not be replaced"
	assert_equal "keep" "$(cat "${install_dir}/sentinel")" "existing install contents should be preserved"
	assert_path_absent "${install_dir}/bin/agg"

	rm "${install_dir}/sentinel"
	rmdir "$install_dir"
	printf 'not a directory\n' >"$install_dir"
	set +e
	output=$(ASDF_INSTALL_TYPE=version ASDF_INSTALL_VERSION=1.9.0 ASDF_INSTALL_PATH="$install_dir" \
		ASDF_DOWNLOAD_PATH="$download_dir" "${repo_dir}/bin/install" 2>&1)
	status=$?
	set -e
	assert_equal "1" "$status" "a file install path should fail"
	assert_contains "$output" "not a directory" "the unsafe path error should be explicit"
	assert_equal "not a directory" "$(cat "$install_dir")" "the existing file should be preserved"
}

run_test "stable tags are normalized, prereleases excluded, and versions semantically ordered" test_stable_version_filtering_and_ordering
run_test "latest-stable resolves the latest matching stable version" test_latest_stable_selection
run_test "invalid and unstable release versions are rejected" test_release_version_validation
run_test "mocked supported platforms map to exact upstream assets" test_supported_platform_mappings
run_test "mocked unsupported platform and libc combinations fail clearly" test_unsupported_platform_errors
run_test "mocked libc detection distinguishes GNU, musl, and unknown" test_libc_detection
run_test "release URLs use exact official asset names" test_release_urls
run_test "artifact validation rejects empty, non-executable, mismatched, and unrunnable files" test_binary_validation
run_test "download exposes only a verified executable" test_download_places_verified_binary_only
run_test "HTTP failure leaves the download directory empty" test_download_failure_leaves_no_files
run_test "invalid and empty download content is rejected" test_download_rejects_invalid_artifacts
run_test "install creates the asdf bin/agg layout" test_install_creates_expected_executable
run_test "install rejects bad artifacts and preserves unsafe existing paths" test_install_rejects_bad_artifacts_and_unsafe_paths

printf '1..%d\n' "$tests_run"

if [ "$tests_failed" -ne 0 ]; then
	printf '%d test(s) failed\n' "$tests_failed" >&2
	exit 1
fi
