#!/usr/bin/env bash

emit_output() {
    if [[ -n "${GITHUB_OUTPUT:-}" ]]; then
        printf '%s\n' "$1" >> "${GITHUB_OUTPUT}"
    fi
}

emit_summary() {
    if [[ -n "${GITHUB_STEP_SUMMARY:-}" ]]; then
        cat >> "${GITHUB_STEP_SUMMARY}"
    else
        cat > /dev/null
    fi
}

fail() {
    if [[ -n "${GITHUB_ACTIONS:-}" ]]; then
        echo "::error::$*"
    else
        echo "error: $*" >&2
    fi
    exit 1
}
