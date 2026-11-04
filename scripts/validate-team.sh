#!/usr/bin/env bash
# Checks a team file before it reaches Git: the contract Terraform enforces at
# plan time, plus the size limits in policy.yaml. It needs no network or cluster,
# because the reviewer agent runs it inside Codex's sandbox.
#
# Usage: scripts/validate-team.sh <teams/name.yaml> [policy.yaml]
# Prints one PASS/FAIL/WARN line per check and exits 1 if any check failed.
set -u

file=${1:?usage: validate-team.sh <team-file> [policy-file]}
root=$(cd "$(dirname "$0")/.." && pwd)
policy=${2:-$root/policy.yaml}
chart_values=$root/gitops/charts/team/values.yaml

fails=0
pass() { printf 'PASS  %s\n' "$*"; }
fail() { printf 'FAIL  %s\n' "$*"; fails=$((fails + 1)); }
warn() { printf 'WARN  %s\n' "$*"; }

# CPU in millicores, memory and storage in MiB. Anything else prints "bad".
cpu_m() {
  case $1 in *[!0-9.m]* | '' | m | .*) echo bad; return ;; esac
  awk -v q="$1" 'BEGIN { if (q ~ /m$/) { sub(/m$/, "", q); printf "%d", q } else printf "%d", q * 1000 }'
}
mib() {
  awk -v q="$1" 'BEGIN {
    n = q; u = q; sub(/[A-Za-z]+$/, "", n); sub(/^[0-9.]+/, "", u)
    f["Ki"] = 1 / 1024; f["Mi"] = 1; f["Gi"] = 1024; f["Ti"] = 1048576
    if (n == "" || n !~ /^[0-9]+(\.[0-9]+)?$/ || !(u in f)) { print "bad"; exit }
    printf "%d", n * f[u]
  }'
}
# Value from the team file, falling back to the team chart's default.
get() { yq -r "$1 // \"\"" "$file" | sed '/^null$/d'; }
default() { yq -r "$1" "$chart_values"; }
limit() { yq -r "$1" "$policy"; }

if ! yq -e '.' "$file" >/dev/null 2>&1 || [ "$(yq -r 'type' "$file")" != "!!map" ]; then
  fail "yaml: $file is not a YAML mapping"
  printf 'RESULT FAIL\n'
  exit 1
fi

# --- Contract (same rules as terraform/teams.tf) ---------------------------------
name=$(basename "$file" .yaml)
team=$(get .team)
if [ "$team" = "$name" ]; then pass "team: '$team' matches the file name"
else fail "team: '$team' must equal the file name '$name'"; fi

if ! printf '%s' "$name" | grep -Eq '^[a-z][a-z0-9-]{1,19}[a-z0-9]$'; then
  fail "name: '$name' must be 3-21 chars of a-z, 0-9 and '-', starting with a letter"
elif printf '%s' "$name" | grep -Eq '^(kube|gke|gmp)-|google|^(default|argocd|cert-manager|cnpg-system)$'; then
  fail "name: '$name' is reserved for the platform or the cloud provider"
else pass "name: '$name' is allowed"; fi

unknown=$(yq -r '(keys - ["team","owners","quota","postgres"]) + ((.quota // {}) | keys - ["cpu","memory","storage"] | map("quota." + .)) + ((.postgres // {}) | keys - ["enabled","instances","storage"] | map("postgres." + .)) | .[]' "$file")
if [ -z "$unknown" ]; then pass "keys: all known"
else fail "keys: unknown $(echo $unknown | tr ' ' ',') (the chart would silently ignore them)"; fi

owners_type=$(yq -r '.owners | type' "$file")
if [ "$owners_type" = "!!null" ] || [ "$(yq -r '.owners | length' "$file")" = 0 ]; then
  warn "owners: none, so nobody gets edit access to the namespace"
elif [ "$owners_type" != "!!seq" ]; then
  fail "owners: must be a list of email addresses"
else
  bad=$(yq -r '.owners[]' "$file" | grep -Ev '^[^@[:space:]]+@[^@[:space:]]+\.[a-z]{2,}$' || true)
  if [ -z "$bad" ]; then pass "owners: $(yq -r '.owners | join(", ")' "$file")"
  else fail "owners: not email addresses: $(echo $bad | tr ' ' ',')"; fi
fi

if [ -e "$root/teams/$name.yaml" ] && ! [ "$file" -ef "$root/teams/$name.yaml" ]; then
  warn "exists: teams/$name.yaml is already in this checkout; this would change that team"
fi

# --- Size (policy.yaml) -----------------------------------------------------------
cpu=$(get .quota.cpu); cpu=${cpu:-$(default .quota.cpu)}
mem=$(get .quota.memory); mem=${mem:-$(default .quota.memory)}
sto=$(get .quota.storage); sto=${sto:-$(default .quota.storage)}
cpu_q=$(cpu_m "$cpu"); mem_q=$(mib "$mem"); sto_q=$(mib "$sto")
cpu_max=$(limit .quota_max.cpu); mem_max=$(limit .quota_max.memory); sto_max=$(limit .quota_max.storage)

check_max() { # label value value_in_units max max_in_units
  if [ "$3" = bad ]; then fail "quota.$1: '$2' is not a Kubernetes quantity"
  elif [ "$3" -gt "$5" ]; then fail "quota.$1: $2 is above the standard tier ($4); ask the platform team"
  else pass "quota.$1: $2 (tier max $4)"; fi
}
check_max cpu "$cpu" "$cpu_q" "$cpu_max" "$(cpu_m "$cpu_max")"
check_max memory "$mem" "$mem_q" "$mem_max" "$(mib "$mem_max")"
check_max storage "$sto" "$sto_q" "$sto_max" "$(mib "$sto_max")"

if [ "$(yq -r '.postgres.enabled // false' "$file")" = true ]; then
  n=$(get .postgres.instances); n=${n:-$(default .postgres.instances)}
  pg_sto=$(get .postgres.storage); pg_sto=${pg_sto:-$(default .postgres.storage)}
  max_n=$(limit .postgres.max_instances)
  case $n in
    '' | *[!0-9]* | 0) fail "postgres.instances: '$n' must be a whole number from 1" ;;
    *) if [ "$n" -gt "$max_n" ]; then
         fail "postgres.instances: $n needs $n nodes (one per instance), the cluster has $max_n; use $max_n"
       else pass "postgres.instances: $n (max $max_n, one per node)"; fi ;;
  esac
  pg_q=$(mib "$pg_sto")
  if [ "$pg_q" = bad ]; then fail "postgres.storage: '$pg_sto' is not a Kubernetes quantity"
  elif [ "$sto_q" != bad ] && printf '%s' "$n" | grep -Eq '^[1-9][0-9]*$'; then
    # Each instance's volume, and its CPU and memory requests, count against the quota.
    if [ $((pg_q * n)) -gt "$sto_q" ]; then
      fail "postgres.storage: $n x $pg_sto doesn't fit in quota.storage $sto"
    else pass "postgres.storage: $n x $pg_sto fits in quota.storage $sto"; fi
    pi_cpu=$(cpu_m "$(limit .postgres.per_instance.cpu)"); pi_mem=$(mib "$(limit .postgres.per_instance.memory)")
    if [ "$cpu_q" != bad ] && [ "$mem_q" != bad ]; then
      if [ $((pi_cpu * n)) -gt "$cpu_q" ] || [ $((pi_mem * n)) -gt "$mem_q" ]; then
        fail "postgres.requests: $n instances request $((pi_cpu * n))m CPU and $((pi_mem * n))Mi, more than the quota"
      else pass "postgres.requests: $n instances fit in the CPU and memory quota"; fi
    fi
  fi
fi

if [ "$fails" -eq 0 ]; then printf 'RESULT PASS\n'; exit 0; fi
printf 'RESULT FAIL (%d)\n' "$fails"
exit 1
