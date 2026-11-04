# Platform policy

What a team gets from the platform, and the limits a request has to meet.
`make validate FILE=teams/<team>.yaml` checks every rule here. The numbers live in
`policy.yaml`.

## Names

- **One file per team.** The file is `teams/<team>.yaml`, and `team:` matches the
  file name. The name is also the namespace.
- **Format.** 3 to 21 characters of `a-z`, `0-9` and `-`. It starts with a letter
  and doesn't end with `-`.
- **Reserved names.** It can't be a platform or provider namespace: `kube-*`,
  `gke-*`, `gmp-*`, `default`, `argocd`, `cert-manager`, `cnpg-system`, or anything
  containing `google`.

## Owners

- **Email addresses only.** Owners get `edit` in the namespace. On GKE they can also
  fetch cluster credentials.
- **Ask for at least one owner.** With none, only the platform team can work in the
  namespace.

## Size: the standard tier

| Quota | Maximum | Default if left out |
|---|---|---|
| CPU requests | 4 | 2 |
| Memory requests | 8Gi | 4Gi |
| Storage requests | 50Gi | 10Gi |

Anything bigger needs a conversation with the platform team, not a request.

## Postgres

- **Optional:** `postgres: { enabled: true, instances: N, storage: S }`.
- **At most 2 instances.** Each instance runs on its own node. The local cluster has
  two workers, so a third instance never schedules: its pod stays Pending with
  "didn't match pod anti-affinity rules". Two instances means a primary and an
  asynchronous streaming replica.
- **Storage counts against the quota.** Each instance's volume is part of the team's
  storage, so `instances x storage` must fit in `quota.storage`.
- **CPU and memory count too.** Each instance requests 100m CPU and 256Mi of memory
  from the team's quota.
- **No backups locally.** On GKE, WAL and daily base backups go to the team's
  bucket.

## What a team gets

- A namespace with Pod Security `baseline` enforced, and `restricted` as a warning.
- A quota and default requests. No LoadBalancers or NodePorts.
- Ingress from its own namespace only.
- `edit` for the owners.
- With Postgres: the cluster `pg`, with services `pg-rw` (primary), `pg-ro` and
  `pg-r`, database `app`, user `app`, and the password in the secret `pg-app`.
  Nobody posts the password. The handover says where to read it.
