#!/usr/bin/env bash

set -euo pipefail

info() {
    echo "INFO: $(date): $*"
}

die() {
    echo >&2 "$@"
    exit 1
}

is_CI() {
    [[ "${CI:-}" == "true" ]]
}

is_CIRCLECI() {
    [[ "${CIRCLECI:-}" == "true" ]]
}

is_OPENSHIFT_CI() {
    [[ "${OPENSHIFT_CI:-}" == "true" ]]
}

openshift_ci_mods() {
    # For ci_export(), override BASH_ENV from stackrox-test with something that is writable.
    BASH_ENV=$(mktemp)
    export BASH_ENV

    # These are not set in the binary_build_commands or image build envs.
    export CI=true
    export OPENSHIFT_CI=true

    # For gradle
    export GRADLE_USER_HOME="${HOME}"
}

pr_has_label() {
    if [[ -z "${1:-}" ]]; then
        die "usage: pr_has_label <expected label>"
    fi

    local expected_label="$1"
    local pr_details
    pr_details="${2:-$(get_pr_details)}"
    jq '([.labels | .[].name]  // []) | .[]' -r <<<"$pr_details" | grep -qx "${expected_label}"
}

get_pr_details() {
    local pull_request
    local org
    local repo

    if is_CIRCLECI; then
        [ -n "${CIRCLE_PULL_REQUEST}" ] || { echo "Not on a PR, ignoring label overrides"; exit 3; }
        [ -n "${CIRCLE_PROJECT_USERNAME}" ] || { echo "CIRCLE_PROJECT_USERNAME not found" ; exit 2; }
        [ -n "${CIRCLE_PROJECT_REPONAME}" ] || { echo "CIRCLE_PROJECT_REPONAME not found" ; exit 2; }
        pull_request="${CIRCLE_PULL_REQUEST}"
        org="${CIRCLE_PROJECT_USERNAME}"
        repo="${CIRCLE_PROJECT_REPONAME}"
    elif is_OPENSHIFT_CI; then
        if [[ -n "${JOB_SPEC:-}" ]]; then
            pull_request=$(jq -r <<<"$JOB_SPEC" '.refs.pulls[0].number')
            org=$(jq -r <<<"$JOB_SPEC" '.refs.org')
            repo=$(jq -r <<<"$JOB_SPEC" '.refs.repo')
        elif [[ -n "${CLONEREFS_OPTIONS:-}" ]]; then
            pull_request=$(jq -r <<<"$CLONEREFS_OPTIONS" '.refs[0].pulls[0].number')
            org=$(jq -r <<<"$CLONEREFS_OPTIONS" '.refs[0].org')
            repo=$(jq -r <<<"$CLONEREFS_OPTIONS" '.refs[0].repo')
        else
            die "not supported"
        fi
    else
        die "not supported"
    fi

    headers=()
    if [[ -n "${GITHUB_TOKEN:-}" ]]; then
        headers+=(-H "Authorization: token ${GITHUB_TOKEN}")
    fi

    url="https://api.github.com/repos/${org}/${repo}/pulls/${pull_request}"
    curl -sS "${headers[@]}" "${url}"
}

gate_jobs() {
    if [[ "$#" -ne 1 ]]; then
        die "missing arg. usage: gate_jobs <job>"
    fi

    local job="$1"

    info "Will determine whether to run: $job"

    local pr_details
    pr_details="$(get_pr_details)"

    if [[ "$(jq .id <<<"$pr_details")" == "null" ]]; then
        gate_pr_jobs "$pr_details"
    else
        die "next"
    fi
}

gate_pr_jobs() {
    local pr_details="$1"

    local run_with_labels=()
    local skip_with_label=()

    case "$job" in
        gke-upgrade-tests)
            run_with_labels=("ci-upgrade-tests")
            skip_with_label=("ci-no-upgrade-tests")
            ;;
        *)
            info "There are no gating labels for $job"
    esac

    for run_with_label in "${run_with_labels[@]}"; do
        if pr_has_label "${run_with_label}" "${pr_details}"; then
            info "$job will run because the PR has label $run_with_label"
            return
        fi
    done

    info "This job will not run"
    exit 0
}
