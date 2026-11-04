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

## Wed 4 Nov, late morning: first run in Switch

- **Intake really had no shell.** Asked to run `gh auth status`, it said it
  couldn't. Its session's tool list was Read, Grep and Glob plus Switch's tools.
- **But Read reaches the whole disk.** Asked to read `~/.config/gh/hosts.yml` and
  list `~/.switch/agents`, it did both, with no error. Claude Code limits where an
  agent writes, not where it reads. An agent anyone can talk to could have posted
  `~/.kube/config` or a token file to the room.
- **Switch's own `send_attachment` uploads any local file by path**, so taking
  Read away isn't enough on its own. Intake now has only Switch's tools, without
  the attachment tools or the ones that change other agents. One of those,
  `update_agent_detail`, changes who may address an agent without any special
  capability. Through intake, a requester could have made ship take orders from
  anyone, and then approved ship's command themselves.
- **Intake no longer reads POLICY.md.** It knows the file's shape and the
  defaults, and leaves every judgment to `make validate`, so a request for 3
  Postgres instances still reaches the reviewer and fails there.
- **Switch doesn't clone the repo on a server with agent management.** It tells
  the agent to clone it, which a Codex reviewer with no network can't do. `make
  agents-clone` does it for review and ship.
- **`{$creator}` stays unfilled in agent instructions** on 0.40.1 (it works in
  the room's `users`). The instructions now say "your owner".
- **Codex reviewed its first draft offline:** saved it, ran `make validate`,
  posted `RESULT PASS` and handed back to intake, in 32 seconds.
