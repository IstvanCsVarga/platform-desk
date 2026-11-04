#!/usr/bin/env bash
# Runs validate-team.sh over tests/validate: every file in pass/ and teams/ must
# pass, and every file in fail/ must fail with the reason in its "# expect:" line.
set -u
root=$(cd "$(dirname "$0")/.." && pwd)
v=$root/scripts/validate-team.sh
bad=0

for f in "$root"/tests/validate/pass/*.yaml "$root"/teams/*.yaml; do
  if out=$("$v" "$f"); then echo "ok    pass  ${f#"$root"/}"
  else echo "NOT OK pass  ${f#"$root"/}"; echo "$out" | sed 's/^/      /'; bad=$((bad + 1)); fi
done

for f in "$root"/tests/validate/fail/*.yaml; do
  want=$(sed -n 's/^# expect: //p' "$f")
  out=$("$v" "$f"); code=$?
  if [ "$code" -eq 1 ] && echo "$out" | grep '^FAIL' | grep -qF "$want"; then
    echo "ok    fail  ${f#"$root"/}  ($want)"
  else
    echo "NOT OK fail  ${f#"$root"/}  (exit $code, wanted a FAIL with '$want')"; echo "$out" | sed 's/^/      /'; bad=$((bad + 1))
  fi
done

[ "$bad" -eq 0 ] && echo "all validator tests passed" || { echo "$bad validator test(s) failed"; exit 1; }
