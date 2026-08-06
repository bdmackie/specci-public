#!/bin/sh
# specci bootstrap installer.
#
# Copyright (c) 2026 Enbloom. MIT licensed — see LICENSE.
# The licence covers this installer, not Specci itself.
#
#   curl -fsSL https://get.specci.ai | SPECCI_TOKEN=<token> sh
#
# This URL is permanent. It goes in the README, the docs and every onboarding
# message, so it is never versioned — the artefacts are versioned instead.
#
# Everything is wrapped in main() and only invoked on the last line. A truncated
# download therefore does nothing at all, rather than executing half an installer.

set -eu

DL_BASE="${SPECCI_DL_BASE:-https://dl.specci.ai}"
CHANNEL="${SPECCI_CHANNEL:-stable}"
PRODUCT="cli"
INSTALL_DIR="${SPECCI_INSTALL_DIR:-$HOME/.local/bin}"

say() { printf '%s\n' "$*"; }
err() { printf 'error: %s\n' "$*" >&2; exit 1; }

need() {
	command -v "$1" >/dev/null 2>&1 || err "'$1' is required but not installed."
}

# Resolve the Rust target triple for this machine. Unsupported platforms fail
# with the list of what does work — a clear refusal beats a confusing 404 later.
detect_target() {
	os="$(uname -s)"
	arch="$(uname -m)"
	case "$os/$arch" in
		Darwin/arm64) printf 'aarch64-apple-darwin' ;;
		Darwin/x86_64)
			err "Intel Macs are not supported yet (this build is Apple Silicon only)." ;;
		Linux/*)
			err "Linux is not supported yet. Currently supported: macOS on Apple Silicon." ;;
		*)
			err "Unsupported platform: $os $arch. Currently supported: macOS on Apple Silicon." ;;
	esac
}

# Minimal field extraction. The manifest is produced by our own release tooling
# and has a fixed, flat shape, so this avoids a jq dependency — macOS ships
# neither jq nor python3. It is deliberately narrow: if the manifest schema
# grows nested objects, this must be revisited rather than patched.
json_string() {
	# $1 = json fragment, $2 = key
	printf '%s' "$1" | sed -n 's/.*"'"$2"'"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -1
}

# Isolate one target's object from the "artifacts" map. Relies on those objects
# containing no nested braces, which the schema guarantees.
target_object() {
	printf '%s' "$1" | sed -n 's/.*"'"$2"'"[[:space:]]*:[[:space:]]*{\([^}]*\)}.*/\1/p'
}

sha256_of() {
	if command -v shasum >/dev/null 2>&1; then
		shasum -a 256 "$1" | cut -d' ' -f1
	elif command -v sha256sum >/dev/null 2>&1; then
		sha256sum "$1" | cut -d' ' -f1
	else
		err "no sha256 tool found (need shasum or sha256sum)."
	fi
}

main() {
	need curl
	need tar
	need uname
	need sed

	# Platform first, deliberately. An unsupported machine is refused before the
	# user is asked to paste a credential — being made to handle a secret for a
	# request that could never have succeeded is a poor way to meet a tool.
	target="$(detect_target)"

	# Token, in order of preference: environment, file, prompt. The prompt is the
	# path humans should take; the other two exist for automation, which has no
	# terminal to be asked at.
	token="${SPECCI_TOKEN:-}"

	if [ -z "$token" ] && [ -n "${SPECCI_TOKEN_FILE:-}" ]; then
		# Preferred for automation: unlike an environment variable, a file is not
		# visible to child processes or to `ps -E`, and never reaches shell history.
		if [ ! -r "$SPECCI_TOKEN_FILE" ]; then
			err "cannot read SPECCI_TOKEN_FILE ($SPECCI_TOKEN_FILE)."
		fi
		token="$(head -n 1 "$SPECCI_TOKEN_FILE" | tr -d '[:space:]')"
		if [ -z "$token" ]; then
			err "SPECCI_TOKEN_FILE ($SPECCI_TOKEN_FILE) is empty."
		fi
	fi

	if [ -z "$token" ]; then
		# stdin is the script itself under `curl | sh`, so the terminal is the only
		# place to ask. Writing the prompt *to* /dev/tty rather than stdout means a
		# non-interactive run fails this test silently and falls through to the
		# clear error below, instead of emitting a device error mid-install.
		if { printf 'Invite token: ' > /dev/tty; } 2>/dev/null; then
			# Echo off. A token typed in the clear lands in the terminal's
			# scrollback, and from there into screenshots and screen shares —
			# which is exactly how one has already been exposed. The saved
			# terminal state is restored on interrupt too: leaving someone's
			# terminal with echo disabled is a nasty parting gift.
			tty_state=""
			if tty_state="$(stty -g < /dev/tty 2>/dev/null)"; then
				trap 'stty "$tty_state" < /dev/tty 2>/dev/null; printf "\n" > /dev/tty; exit 130' INT TERM
				stty -echo < /dev/tty 2>/dev/null || true
			fi
			read -r token < /dev/tty 2>/dev/null || token=""
			if [ -n "$tty_state" ]; then
				stty "$tty_state" < /dev/tty 2>/dev/null || true
				trap - INT TERM
			fi
			printf '\n' > /dev/tty
		fi
	fi

	if [ -z "$token" ]; then
		err "no token supplied. Set SPECCI_TOKEN or SPECCI_TOKEN_FILE, or run in a terminal to be prompted."
	fi

	say "Resolving specci for $target …"

	manifest_url="$DL_BASE/latest.json?product=$PRODUCT&channel=$CHANNEL"
	manifest="$(curl -fsSL -H "Authorization: Bearer $token" "$manifest_url" 2>/dev/null)" || {
		# A failed manifest fetch is nearly always the token, so say so rather
		# than surfacing a bare HTTP code.
		err "could not read the release manifest. Check the token is valid and not revoked."
	}

	version="$(json_string "$manifest" version)"
	[ -n "$version" ] || err "malformed manifest: no version."

	entry="$(target_object "$manifest" "$target")"
	[ -n "$entry" ] || err "no $version build published for $target."

	path="$(json_string "$entry" path)"
	want_sha="$(json_string "$entry" sha256)"
	[ -n "$path" ] || err "malformed manifest: no path for $target."
	[ -n "$want_sha" ] || err "malformed manifest: no sha256 for $target."

	tmp="$(mktemp -d)"
	# shellcheck disable=SC2064
	trap "rm -rf '$tmp'" EXIT INT TERM

	say "Downloading specci $version …"
	curl -fsSL -H "Authorization: Bearer $token" -o "$tmp/specci.tar.gz" "$DL_BASE$path" \
		|| err "download failed."

	got_sha="$(sha256_of "$tmp/specci.tar.gz")"
	[ "$got_sha" = "$want_sha" ] || err "checksum mismatch — expected $want_sha, got $got_sha. Refusing to install."

	tar -xzf "$tmp/specci.tar.gz" -C "$tmp" || err "could not extract the archive."
	[ -f "$tmp/bin/specci" ] || err "archive did not contain bin/specci."

	mkdir -p "$INSTALL_DIR"
	# Everything in bin/ is installed, so the package can grow a second binary
	# without this script changing. Each lands via a temporary name and a rename,
	# so an interrupted install cannot leave a half-written file where a working
	# one used to be.
	installed=''
	for src in "$tmp"/bin/*; do
		[ -f "$src" ] || continue
		name="$(basename "$src")"
		chmod 755 "$src"
		mv "$src" "$INSTALL_DIR/.$name.new"
		mv "$INSTALL_DIR/.$name.new" "$INSTALL_DIR/$name"
		installed="$installed $name"
	done

	say ""
	say "Installed specci $version to $INSTALL_DIR ($(printf '%s' "$installed" | sed 's/^ //'))"

	# Hand the token to the installed binary so `specci setup upgrade` works
	# without asking for it again. Passed in the environment rather than as an
	# argument, so it does not appear in `ps` output.
	#
	# --no-verify because the token has already been used twice, successfully, to
	# fetch the manifest and the artefact; a third round trip would prove nothing.
	#
	# A failure here must not fail the install. The binary is on disk and works;
	# only the convenience of a stored licence is lost, and that is recoverable
	# with one command. Turning a successful install into a failure over it would
	# be a poor trade.
	if SPECCI_TOKEN="$token" "$INSTALL_DIR/specci" setup activate --no-verify >/dev/null 2>&1; then
		say "Licence stored — 'specci setup upgrade' will keep this install current."
	else
		say ""
		say "Note: the licence could not be stored automatically. To enable upgrades:"
		say "    specci setup activate"
	fi

	case ":$PATH:" in
		*":$INSTALL_DIR:"*) say "Run 'specci --help' to get started." ;;
		*)
			say ""
			say "$INSTALL_DIR is not on your PATH. Add it:"
			say "    export PATH=\"$INSTALL_DIR:\$PATH\""
			;;
	esac
}

main "$@"
