#!/usr/bin/env bash
# Find the running Moodle container that mounts the given host path, environment-agnostic
# (no hardcoded container names or paths). Maps the host dirroot to its container path.
# Usage:  moodle-container.sh <host-path-inside-moodle>
# Prints: <container-name>\t<container-dirroot>   and exit 0, or nothing and exit 1.

host_path="${1:-$PWD}"
command -v docker >/dev/null 2>&1 || exit 1

# Host dirroot = where phpunit runs = the composer root holding vendor/bin/phpunit.
# Version-agnostic: this is repo root on 4.x/5.0 and still repo root on 5.1+ (code under
# public/). Keying on vendor/bin/phpunit avoids stopping at public/, which also has config.php
# under the 5.1 layout. Fallback: a Moodle root with both config.php and a vendor/ dir.
dirroot=""
d="$host_path"
for _ in $(seq 1 10); do
    [ -z "$d" ] && break
    if [ -f "$d/vendor/bin/phpunit" ] || { [ -f "$d/config.php" ] && [ -d "$d/vendor" ]; }; then
        dirroot="$d"; break
    fi
    [ "$d" = "/" ] && break
    d="$(dirname "$d")"
done
[ -z "$dirroot" ] && exit 1

# Find a running container that bind-mounts an ancestor of dirroot and has php.
for c in $(docker ps --format '{{.Names}}' 2>/dev/null); do
    while IFS=$'\t' read -r src dst; do
        [ -z "$src" ] && continue
        case "$dirroot/" in
            "$src/"*)
                rel="${dirroot#"$src"}"
                if docker exec "$c" sh -c 'command -v php' >/dev/null 2>&1; then
                    printf '%s\t%s\n' "$c" "${dst}${rel}"
                    exit 0
                fi
                ;;
        esac
    done < <(docker inspect -f '{{range .Mounts}}{{.Source}}{{"\t"}}{{.Destination}}{{"\n"}}{{end}}' "$c" 2>/dev/null)
done
exit 1
