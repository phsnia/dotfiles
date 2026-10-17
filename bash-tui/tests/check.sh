#!/usr/bin/env bash
set -u
ROOT=$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd) || exit 1
status=0
while IFS= read -r -d '' file; do
    if bash -n "$file"; then
        printf '[PASS] syntax: %s\n' "${file#"$ROOT"/}"
    else
        printf '[FAIL] syntax: %s\n' "${file#"$ROOT"/}"
        status=1
    fi
done < <(find "$ROOT" -type f -name '*.sh' -print0)
exit "$status"
