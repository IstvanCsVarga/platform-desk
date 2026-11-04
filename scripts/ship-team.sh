#!/usr/bin/env bash
# Ships one reviewed team file: branch, PR, merge, Argo CD sync, then a check that
# the namespace and its Postgres are up. platform-ship runs it only after a person
# has allowed it in the room, so every change of state happens in this one command.
#
# Usage: scripts/ship-team.sh <team> < team.yaml
#   ROOM, APPROVER and REVIEW, if set, go into the PR description.
#   GitHub access comes from a fine-grained token that only works on this repo:
#   on macOS from the login keychain (service platform-desk-ship), which the
#   Codex reviewer's sandbox can't reach, otherwise from
#   ~/.config/platform-desk/ship-token (SHIP_TOKEN_FILE overrides the path).
#   Without either, it uses your own gh login.
#   The handover never prints the database password, only where to read it.
set -euo pipefail

team=${1:?usage: ship-team.sh <team> < team.yaml}
root=$(cd "$(dirname "$0")/.." && pwd)
ctx=${KUBE_CONTEXT:-kind-platform-local}
k() { kubectl --context "$ctx" "$@"; }
t0=$(date +%s)
step() { printf '[%4ss] %s\n' $(($(date +%s) - t0)) "$*"; }
die() { printf 'FAIL   %s\n' "$*"; exit 1; }

cd "$root"
token=$(security find-generic-password -s platform-desk-ship -w 2>/dev/null || true)
token_file=${SHIP_TOKEN_FILE:-$HOME/.config/platform-desk/ship-token}
if [ -z "$token" ] && [ -s "$token_file" ]; then token=$(cat "$token_file"); fi
if [ -n "$token" ]; then
  GH_TOKEN=$token; export GH_TOKEN
  access="a token that only works on this repo"
else
  echo "WARN   no ship token in the keychain or $token_file, so this uses your own gh login"
  access="the owner's gh login"
fi
git_auth() { # git over HTTPS with GH_TOKEN when there is one
  if [ -n "${GH_TOKEN:-}" ]; then
    git -c credential.helper= -c 'credential.helper=!f() { echo username=x-access-token; echo "password=$GH_TOKEN"; }; f' "$@"
  else git "$@"; fi
}

# --- Git: start from main as GitHub has it, and only add teams that are new ---------
git diff --quiet && git diff --cached --quiet || die "the working tree has changes; commit or stash them first"
git_auth fetch -q origin main
file=teams/$team.yaml
git cat-file -e "origin/main:$file" 2>/dev/null && die "$file already exists on main; changing an existing team isn't supported yet"

branch=request/$team
git switch -q -C "$branch" origin/main
trap 'git switch -q main 2>/dev/null || true' EXIT # back on main however this ends
cat >"$file"
if ! scripts/validate-team.sh "$file" | sed 's/^/       /'; then
  rm -f "$file"; git switch -q main; git branch -q -D "$branch"
  die "validation failed, nothing was pushed"
fi
git add "$file"
git commit -q -m "Add team $team" -m "Requested in: ${ROOM:-the platform desk}
Approved by: ${APPROVER:-the approver}"
# Forced: a request branch belongs to ship, and an earlier failed run may have left one.
git_auth push -q -f -u origin "$branch" 2>&1 | sed '/^remote:/d'
step "pushed $branch"

repo=$(gh repo view --json nameWithOwner -q .nameWithOwner)
body="Requested in ${ROOM:-the platform desk}.

Review: ${REVIEW:-platform-review ran make validate and it passed.}

Approved in the room by ${APPROVER:-the approver}. Opened and merged by platform-ship with $access."
pr=$(gh pr list --repo "$repo" --head "$branch" --state open --json url -q '.[0].url')
if [ -n "$pr" ]; then step "reusing $pr, left open by an earlier run"
else pr=$(gh pr create --repo "$repo" --base main --head "$branch" --title "Add team $team" --body "$body"); step "opened $pr"; fi
# Right after a push GitHub may still be working out whether the PR can merge, so retry briefly.
for _ in 1 2 3 4 5 6 7 8; do
  if out=$(gh api -X PUT "repos/$repo/pulls/${pr##*/}/merge" -f merge_method=squash 2>&1); then merged=1; break; fi
  sleep 3
done
[ -n "${merged:-}" ] || die "merging $pr failed: $(printf '%s\n' "$out" | tail -1 | sed 's/.*gh: //')"
gh api -X DELETE "repos/$repo/git/refs/heads/$branch" >/dev/null 2>&1 || true
git switch -q main
git_auth pull -q --ff-only origin main
git branch -q -D "$branch" 2>/dev/null || true
step "merged $pr"

# --- Argo CD: don't wait for its 3-minute poll -----------------------------------
# The refresh annotation makes the ApplicationSet re-read Git without its revision cache.
k -n argocd annotate applicationset teams argocd.argoproj.io/application-set-refresh=true --overwrite >/dev/null
k -n argocd wait --for=create "application/team-$team" --timeout=180s >/dev/null || die "Argo CD didn't create team-$team within 3 minutes"
step "Argo CD created application team-$team"
k -n argocd wait "application/team-$team" --for=jsonpath='{.status.sync.status}'=Synced --timeout=300s >/dev/null ||
  die "team-$team isn't Synced: $(k -n argocd get application "team-$team" -o jsonpath='{.status.conditions[*].message}')"
step "namespace $team synced"

pg=$(yq -r '.postgres.enabled // false' "$file")
if [ "$pg" = true ]; then
  k -n "$team" wait --for=create cluster.postgresql.cnpg.io/pg --timeout=120s >/dev/null
  if ! k -n "$team" wait --for=condition=Ready cluster.postgresql.cnpg.io/pg --timeout=600s >/dev/null; then
    k -n "$team" get pods -l cnpg.io/cluster=pg -o wide
    die "Postgres isn't ready after 10 minutes: $(k -n "$team" get cluster pg -o jsonpath='{.status.phase}')"
  fi
  step "Postgres ready"
fi

# --- Handover -------------------------------------------------------------------
q() { k -n "$team" get resourcequota team-quota -o jsonpath="{.spec.hard.requests\.$1}"; }
owners=$(yq -r '.owners // [] | join(", ")' "$file")
echo
echo "SHIPPED $team in $(($(date +%s) - t0))s"
echo "  PR         $pr (merged)"
echo "  Namespace  $team: quota $(q cpu) CPU, $(q memory) memory, $(q storage) storage; Pod Security baseline; ingress from its own namespace only"
echo "  Owners     ${owners:-none}${owners:+ (edit access)}"
if [ "$pg" = true ]; then
  echo "  Postgres   $(k -n "$team" get cluster pg -o jsonpath='{.status.readyInstances}/{.spec.instances} instances ready, primary {.status.currentPrimary}')"
  echo "             host pg-rw.$team.svc:5432, database app, user app"
  echo "             password: kubectl -n $team get secret pg-app -o jsonpath='{.data.password}' | base64 -d"
  echo "  Backups    none on the local cluster (on GKE: WAL and daily base backups to the team's bucket)"
fi
