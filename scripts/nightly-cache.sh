#!/usr/bin/env bash
# Finds nightly Neovim builds of the `nightly` dev shell in nix-community.cachix.org.
#
#   scripts/nightly-cache.sh latest [count]
#       Prints the newest of the last `count` (default 10) neovim-nightly-overlay commits whose build for this system
#       is in the cache. Needs an authenticated `gh`.
set -euo pipefail

cache=https://nix-community.cachix.org
overlay=nix-community/neovim-nightly-overlay

usage() {
    echo "Usage: $0 latest [count]" >&2
    exit 2
}

# Prints the store path of the Neovim in the `nightly` shell for a system. More arguments go to `nix eval`.
neovim_path() {
    local system=$1
    shift
    nix eval --raw --no-write-lock-file ".#devShells.$system.nightly.neovim.outPath" "$@"
}

# Succeeds when the cache has the store path. Stops the script when the cache gives an unexpected response, so that
# a network error does not look like a missing build.
in_cache() {
    local hash status
    hash=$(basename "$1" | cut -d- -f1)
    status=$(curl --silent --output /dev/null --write-out '%{http_code}' "$cache/$hash.narinfo") || true
    case $status in
    200) return 0 ;;
    404) return 1 ;;
    *)
        echo "Cannot check $cache: HTTP status $status" >&2
        exit 1
        ;;
    esac
}

latest() {
    local count=${1:-10} system revs rev path
    system=$(nix eval --raw --impure --expr builtins.currentSystem)
    revs=$(gh api "repos/$overlay/commits?per_page=$count" --jq '.[].sha')
    for rev in $revs; do
        path=$(neovim_path "$system" --override-input neovim-nightly-overlay "github:$overlay/$rev")
        if in_cache "$path"; then
            echo "$rev"
            return 0
        fi
        echo "Not in the cache: $rev $path" >&2
    done
    echo "The cache has no build of the last $count $overlay commits for $system" >&2
    return 1
}

case ${1:-} in
latest)
    shift
    latest "$@"
    ;;
*) usage ;;
esac
