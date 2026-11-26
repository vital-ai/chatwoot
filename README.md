# Vital's fork of Chatwoot

This is `vital-ai/chatwoot`, a fork of [chatwoot/chatwoot](https://github.com/chatwoot/chatwoot). Only Chatwoot's open-source code is used; nothing under `enterprise/`.

## Branches

| Branch | What it is | Who changes it |
|---|---|---|
| `fork-sync` (this branch, the default) | Only the upstream sync: `.github/workflows/upstream_sync.yml` and `upstream_sync.sh` | By hand, rarely |
| `develop`, `master`, release tags `v*` | Exact copies of upstream's, moved forward only | The daily sync, nothing else |
| `vital/main` | Vital's Chatwoot: an upstream release with our changes merged in. What our apps build from | By hand, only through the release scripts in `vital-ai/vital-saas-deploy` (`chatwoot_deploy/fork/`) |
| `vital/<topic>` | Our work in progress, merged into `vital/main` by those scripts | Us |
| `vital-keycloak-sso`, `vital-keycloak-auth` | Earlier branches, frozen as they are and still in use | Nobody |
| Our tags `vital-v<release>-<n>` | Releases of `vital/main` | The release scripts |

Other upstream branches in this fork are old copies and aren't kept up to date.

## The sync

`upstream_sync.yml` runs daily and by hand. It fast-forwards `develop` and `master`, pushes upstream's new `v*` tags, and disables any upstream workflow that becomes active here. It never forces, never deletes, and never touches `vital/` or the frozen branches. If a copy has diverged it fails and leaves it alone.

It needs the secret `UPSTREAM_SYNC_TOKEN`: a fine-grained token for this repo only, with Contents, Workflows and Actions write. It can also be run locally with your own credentials: `./upstream_sync.sh`, or `DRY_RUN=1 ./upstream_sync.sh` to only report.
