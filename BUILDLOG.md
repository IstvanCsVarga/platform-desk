# Build log

What broke and what was decided, session by session. The hackathon started on Tue
3 Nov at 19:31 CET. Everything up to commit `9403735` is the earlier
`gke-platform` project.

## Wed 4 Nov, morning

- **Switch Console 0.40.1** (arm64, notarized) is running a local server. Only
  Mattermost runs in Docker; the Switch server itself doesn't.
- **Moved the GitHub work from intake to ship.** Intake takes instructions from
  anyone in the room. With a shell, it would also have had the owner's GitHub login,
  so only its prompt would have kept it from merging. Now:
  - intake gets `tools: Read, Grep, Glob` and no shell;
  - ship does the branch, PR and merge in one approved command, using a token that
    only works on this repo.
- **`make validate`:** offline checks with bash and yq, because Codex's sandbox has
  no network. It has 12 tests: 3 files that must pass and 9 that must fail for a
  named reason.
- **The 3-instance case is real.** A Postgres with `instances: 3` on the local
  cluster stayed at 2 of 3 ready for more than 6 minutes. The scheduler said "0/3
  nodes are available: 1 node(s) had untolerated taint(s), 2 node(s) didn't match pod
  anti-affinity rules". The validator now rejects it before it reaches Git.
- **First `make ship`, from the terminal before the agents existed:** team
  `orders-api` with 2 Postgres instances went from push to ready in 52 seconds.
  - It opened and merged PR #1.
  - Argo CD created the app 2 seconds after the merge, because `make ship` sets the
    ApplicationSet's `application-set-refresh` annotation instead of waiting for
    its 3-minute poll.
