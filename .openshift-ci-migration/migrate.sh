#!/usr/bin/env bash

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")"/.. && pwd)"
source "$ROOT/.openshift-ci-migration/lib.sh"

info "ENV DUMP:"
env | sort
info "END ENV DUMP:"

info "Git history:"
(git log --oneline --decorate | head) || true

info "PR Details"
(get_pr_details | jq) || true

set -euo pipefail

openshift_ci_mods

gate_jobs "$@"

# Clone the target repo
cd /go/src/github.com/stackrox
git clone https://github.com/stackrox/stackrox.git
cd stackrox

# Checkout the PR branch if it is a PR
head_ref=$(get_pr_details | jq -r '.head.ref')
if [[ "$head_ref" != "null" ]]; then
    info "Will try to checkout a matching PR branch using: $head_ref"
    git checkout "$head_ref"
fi

# Handoff to target repo dispatch
.openshift-ci/dispatch.sh "$@"

info "nothing to see in stackrox-osci either"
