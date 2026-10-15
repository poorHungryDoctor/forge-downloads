#!/usr/bin/env bash
# Public entry point. All other setup files come from one checksummed, pinned release.
set -euo pipefail

repo="${FORGE_RELEASE_REPO:-jjolliff/forge-downloads}"
version=""
update=0
configure=1
while [ "$#" -gt 0 ]; do
    case "$1" in
    --version) [ "$#" -ge 2 ] || { echo "forge install: --version needs vX.Y.Z" >&2; exit 1; }; version="$2"; shift ;;
    --update) update=1 ;;
    --no-configure) configure=0 ;;
    --help|-h)
        echo "usage: bash install.sh [--version vX.Y.Z] [--update] [--no-configure]"
        echo "Installs Forge, its pinned formatter, and both VS Code extensions when Code is found."
        echo "Adds user PATH, the forge-tools AI skill, and an automatic Claude SessionStart updater."
        echo "--update skips installed/newer versions. --no-configure leaves shell/AI/PATH settings alone."
        exit 0 ;;
    *) echo "forge install: unknown option: $1" >&2; exit 1 ;;
    esac
    shift
done
fail() { echo "forge install: $*" >&2; exit 1; }
[[ "$repo" =~ ^[A-Za-z0-9-]+/[A-Za-z0-9_.-]+$ ]] || fail "invalid release repository"
for tool in curl sha256sum unzip tar git; do
    command -v "$tool" >/dev/null || fail "$tool is required"
done
case "$(uname -s)" in
MINGW*|MSYS*)
    platform=windows
    command -v powershell.exe >/dev/null || fail "Windows PowerShell is required"
    [ -n "${LOCALAPPDATA:-}" ] || fail "LOCALAPPDATA is not set"
    root="$(cygpath -u "$LOCALAPPDATA")/Forge"
    asset=forgeWindowsX64.zip
    executable=forge.exe ;;
Linux)
    platform=linux
    command -v python3 >/dev/null || fail "python3 is required to safely merge existing AI settings"
    root="$HOME/.local/share/forge"
    asset=forgeLinuxX64.tar.gz
    executable=forge ;;
*) fail "supported platforms: Windows Git Bash and Linux x64" ;;
esac
case "$(uname -m)" in x86_64|amd64) ;; *) fail "only x64 releases are available" ;; esac
mkdir -p "$root"
if ! mkdir "$root/.install-lock" 2>/dev/null; then
    if [ "$update" -eq 1 ]; then
        echo "forge install: another install holds $root/.install-lock; skipping this session" >&2
        exit 0
    fi
    fail "another install holds $root/.install-lock; if interrupted, remove that empty directory before retrying"
fi
stage=""
cleanup() {
    if [ -n "$stage" ]; then rm -rf -- "$stage"; fi
    rmdir "$root/.install-lock"
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
download() {
    curl --fail --location --silent --show-error --retry 2 --connect-timeout 10 --max-time 180 \
        --proto '=https' --proto-redir '=https' "$1" -o "$2"
}
if [ -z "$version" ]; then
    latest="$(curl --fail --location --silent --show-error --head --connect-timeout 5 --max-time 20 \
        --proto '=https' --proto-redir '=https' --output /dev/null --write-out '%{url_effective}' \
        "https://github.com/$repo/releases/latest")"
    version="${latest##*/}"
fi
[[ "$version" =~ ^v(0|[1-9][0-9]{0,8})\.(0|[1-9][0-9]{0,8})\.(0|[1-9][0-9]{0,8})$ ]] || fail "expected a stable vX.Y.Z release, got $version"
if [ "$update" -eq 1 ] && [ -f "$root/installed-version" ]; then
    installed="$(cat "$root/installed-version")"
    [[ "$installed" =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ ]] || fail "invalid installed-version; run a manual install"
    if [ "$(printf '%s\n' "$version" "$installed" | sort -V | tail -1)" = "$installed" ]; then
        echo "forge install: $installed is current (latest $version)" >&2
        exit 0
    fi
fi
stage="$(mktemp -d "$root/.install-XXXXXXXX")"
base="https://github.com/$repo/releases/download/$version"
echo "forge install: downloading $version from $repo" >&2
download "$base/sha256.txt" "$stage/sha256.txt"
verifyDownload() {
    local name="$1" row
    download "$base/$name" "$stage/$name"
    row="$(grep -E "^[0-9a-fA-F]{64}  $name\$" "$stage/sha256.txt")" || fail "missing checksum: $name"
    [ "$(printf '%s\n' "$row" | wc -l)" -eq 1 ] || fail "duplicate checksum: $name"
    (cd "$stage" && printf '%s\n' "$row" | sha256sum --check --status) || fail "checksum mismatch: $name"
}
for name in "$asset" forge-setup.zip install.sh; do verifyDownload "$name"; done
[ "$(unzip -Z1 "$stage/forge-setup.zip" | sort)" = "$(printf '%s\n' SKILL.md configure.ps1 configure.py fetchLlvm.sh sessionStart.sh | sort)" ] ||
    fail "unexpected setup archive contents"
mkdir "$stage/setup"
for name in SKILL.md configure.ps1 configure.py fetchLlvm.sh sessionStart.sh; do
    unzip -p "$stage/forge-setup.zip" "$name" > "$stage/setup/$name"
done
if [ "$platform" = windows ]; then
    [ "$(unzip -Z1 "$stage/$asset")" = forge.exe ] || fail "unexpected Windows archive contents"
    unzip -p "$stage/$asset" forge.exe > "$stage/$executable"
else
    [ "$(tar -tzf "$stage/$asset")" = forge ] || fail "unexpected Linux archive contents"
    tar -xOzf "$stage/$asset" forge > "$stage/$executable"
fi
chmod +x "$stage/$executable"
"$stage/$executable" --help >/dev/null || fail "downloaded Forge failed its help check"

config() {
    local helper="${2:-$stage/setup}"
    if [ "$platform" = windows ]; then
        powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File "$(cygpath -w "$helper/configure.ps1")" \
            -Root "$(cygpath -w "$root")" -HomeDirectory "$(cygpath -w "$HOME")" \
            -BashPath "$(cygpath -w "$(command -v bash)")" -CheckOnly "$1"
    else
        python3 "$helper/configure.py" "$root" "$HOME" "$(command -v bash)" "$1"
    fi
}
if [ "$configure" -eq 1 ]; then config true; fi

formatterVersion=23.1.1
formatterPattern="${formatterVersion//./\\.}"
if [ "$platform" = windows ]; then
    cached="$(cygpath -u "$LOCALAPPDATA")/toolchains/llvm-$formatterVersion/bin/clang-format.exe"
else
    cached="${XDG_CACHE_HOME:-$HOME/.cache}/toolchains/llvm-$formatterVersion/bin/clang-format"
fi
formatterPresent=0
for formatter in "$cached" "$(command -v clang-format || true)"; do
    if [ -n "$formatter" ] && [ -x "$formatter" ] &&
        "$formatter" --version | grep -Eq "version $formatterPattern([^0-9.]|$)"; then
        formatterPresent=1
        break
    fi
done
if [ "$formatterPresent" -eq 0 ]; then
    echo "forge install: fetching pinned clang-format $formatterVersion (large LLVM archive; disk space is checked first)" >&2
    bash "$stage/setup/fetchLlvm.sh" --format-only
    "$cached" --version | grep -Eq "version $formatterPattern([^0-9.]|$)" ||
        fail "the installed clang-format did not report version $formatterVersion"
fi

code=""
for candidate in code code-insiders; do
    if command -v "$candidate" >/dev/null; then code="$(command -v "$candidate")"; break; fi
done
if [ -z "$code" ] && [ "$platform" = windows ]; then
    for directory in "$(cygpath -u "$LOCALAPPDATA")/Programs" \
        "$(cygpath -u "${PROGRAMFILES:-C:\\Program Files}")" \
        "/c/Program Files (x86)"; do
        for product in "Microsoft VS Code" "Microsoft VS Code Insiders"; do
            for launcher in code code-insiders; do
                if [ -f "$directory/$product/bin/$launcher" ]; then code="$directory/$product/bin/$launcher"; break 3; fi
            done
        done
    done
fi
if [ -n "$code" ]; then
    for extension in forge-metrics.vsix forge-branch-review.vsix; do verifyDownload "$extension"; done
    for extension in forge-metrics.vsix forge-branch-review.vsix; do
        "$code" --install-extension "$stage/$extension" --force ||
            fail "VS Code extension install failed: $extension; previous Forge binary/version retained, retry this installer"
    done
else
    echo "forge install: VS Code not found; extensions skipped. Install Code, then rerun this command." >&2
fi

mkdir -p "$root/bin" "$root/setup"
# Only these Forge-owned files are replaced; other Forge stores (including seek) are untouched.
mv -f "$stage/$executable" "$root/bin/$executable"
for name in configure.ps1 configure.py fetchLlvm.sh SKILL.md; do
    mv -f "$stage/setup/$name" "$root/setup/$name"
done
mv -f "$stage/setup/sessionStart.sh" "$root/sessionStart.sh"
mv -f "$stage/install.sh" "$root/install.sh"
printf '%s\n' "$repo" > "$root/release-repo"
if [ "$configure" -eq 1 ]; then
    config false "$root/setup"
    # A child process cannot change the invoking shell. New shells read this additive PATH entry.
    printf -v pathLine 'case ":$PATH:" in *:%q:*) ;; *) export PATH=%q:"$PATH" ;; esac' "$root/bin" "$root/bin"
    appendLine() {
        local file="$1" line="$2"
        if [ -e "$file" ] && [ ! -f "$file" ]; then fail "not a regular shell startup file: $file"; fi
        if ! grep -qxF "$line" "$file" 2>/dev/null; then
            if [ -f "$file" ] && [ ! -e "$file.forge-backup" ]; then cp -p "$file" "$file.forge-backup"; fi
            printf '\n%s\n' "$line" >> "$file"
        fi
    }
    appendLine "$HOME/.bashrc" "$pathLine"
    # Bash reads the first of these for login shells, not all three.
    profile="$HOME/.bash_profile"
    for candidate in .bash_profile .bash_login .profile; do
        if [ -e "$HOME/$candidate" ]; then profile="$HOME/$candidate"; break; fi
    done
    appendLine "$profile" "$pathLine"
fi
printf '%s\n' "$version" > "$stage/installed-version"
mv -f "$stage/installed-version" "$root/installed-version"
echo "forge install: installed $version in $root/bin" >&2
echo "Open a new terminal (and restart VS Code) to pick up PATH. Run: forge help" >&2
