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

## Wed 4 Nov, midday: the first request through the agents

- **Second Mattermost account, `priya`, as the developer.** She asked
  `platform-requests` for inventory-api with 3 Postgres instances.
  - Intake asked for owners and size, created `req-inventory-api` with her, me and
    both agents, and handed the draft to review.
  - Codex failed it twice over: 3 instances need 3 nodes, and 3 × 5Gi doesn't fit
    the 10Gi quota. Intake explained it to her in plain words and proposed 2.
  - The second review passed.
- **Priya told ship to ship.** Switch answered before the model saw it: "I only take
  instructions from my owner".
- **My own order brought up the card**, with the full `make ship` command and the
  YAML. It sits in a thread under the order, which looks like silence from the
  channel view.
- **The first approved run opened PR #2, then failed to merge it**, and the script
  had thrown GitHub's reason away. GitHub had an open incident at the time (Pull
  Requests: partial outage, since 09:53 UTC).
  - `make ship` now merges through the REST API and retries for 24 seconds.
  - It prints GitHub's message when the merge still fails.
  - It reuses a PR an earlier run left open, and always returns to `main`.
  - Ship did what its instructions say: it posted the FAIL line and stopped, with
    no retry.
- **The token moved to the macOS keychain.** Inside Codex's sandbox, a file read
  worked, but a keychain lookup found nothing and the network was blocked.
- **The model's safeguards flagged my attack-style test prompt to intake** and fell
  back to an older model for that session. The tool list in the session log is the
  better proof anyway, so I tested that way after.
- **The keychain alone doesn't stop the reviewer.** Switch runs Codex in auto mode,
  where Codex's own automatic reviewer answers its requests to leave the sandbox. I
  asked the reviewer to read a dummy keychain item. It asked to leave the sandbox,
  the request was approved, and it printed the value.
  - Switch Console never picks the Codex mode in which those requests come to a
    person. Approval-required would ask about every command and tool call.
  - So the template now keeps the rooms apart. Developers talk to intake in
    `platform-requests`. `req-<team>` holds only the owner, review and ship. Review
    and ship are no longer members of `platform-requests`, so nothing a developer
    writes reaches an agent that can run commands, except the YAML intake drafted.

## Thu 5 Nov, morning: the first request shipped by the agents

- **GitHub's incident outlasted Wednesday.** The second approved run got
  `remote rejected … (Internal Server Error)` on the push, and the script exited
  with no FAIL line. Now it retries a push three times and ends with
  `FAIL pushing …`.
- **Thursday 09:59, third card, Allow once:** `inventory-api` was shipped in 52
  seconds.
  - It reused PR #2 from the first run, merged it at 8 s, and Argo CD had the app
    at 10 s.
  - Postgres reached 2/2 ready at 52 s, with the primary and replica on different
    workers.
  - The PR description names the room, the review result and the approver.
- **Intake never told priya.** Ship posted the handover without addressing anyone,
  and an agent only wakes when it's addressed. Ship now hands the handover to
  @platform-intake.
