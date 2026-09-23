# Release Process

This page documents how to ship a new version of ARMConfigKit. Unlike the PowerShell
kits (which carry a `ModuleVersion` in a `.psd1`), ARMConfigKit is a Terraform lab with
**no in-repo version field** — a release is defined entirely by a `v*` git tag, the
`CHANGELOG.md` entry and `RELEASE-NOTES.md`. Pushing the tag triggers the GitHub release
workflow.

## Versioning policy

ARMConfigKit follows [Semantic Versioning 2.0](https://semver.org/spec/v2.0.0.html).

| Bump | When |
|---|---|
| MAJOR (X.0.0) | Breaking change to the variable schema (renamed/removed variables, changed `vms_informations` object shape) or to the deployed topology in a way that forces resource replacement on existing labs. |
| MINOR (X.Y.0) | New backward-compatible capability (new optional variable, new resource/module, provider or AVM module bump that adds features without breaking existing configs). |
| PATCH (X.Y.Z) | Bug fix, provider/module patch bump, or documentation-only change. |

## Release checklist

### 1. Promote `[Unreleased]` in `CHANGELOG.md`

Move the accumulated `[Unreleased]` block to a dated section for the version being
released, and add a fresh empty `[Unreleased]` heading on top so future PRs have
somewhere to write to:

```markdown
## [Unreleased]

## [1.1.0] - 2026-MM-DD

### Added
...
### Changed
...
### Fixed
...
```

### 2. Replace `RELEASE-NOTES.md`

`RELEASE-NOTES.md` is used **verbatim** as the body of the GitHub Release. It must
contain **only the section of the version being released** (no `[Unreleased]` header, no
stacked history) plus the trailing `## Changelog` pointer.

### 3. Validate locally

```bash
cd terraform
terraform fmt -check -recursive
terraform init -backend=false -input=false
terraform validate
```

Run the helper-script tests as well:

```powershell
Invoke-Pester -Path .\tests
Invoke-ScriptAnalyzer -Path .\scripts -Recurse -Settings .\PSScriptAnalyzerSettings.psd1
```

> [!IMPORTANT]
> Terraform `validate` only checks the configuration is well-formed. Before tagging a
> release, deploy the lab **end to end on a fresh resource group** (`terraform apply`,
> confirm the VMs come up, then `terraform destroy`) so the tagged version is known to
> provision cleanly — not just to parse.

### 4. Commit on a release branch

```bash
git checkout -b release/1.1.0
git add -A
git commit -m "release: v1.1.0"
git push -u origin release/1.1.0
```

Open a Pull Request, review, and merge to `main`.

### 5. Tag from `main`

After the PR is merged:

```bash
git checkout main
git pull
git tag v1.1.0
git push origin v1.1.0
```

The `.github/workflows/release.yml` workflow runs automatically. It:

1. Packages `terraform/` and `scripts/` into `ARMConfigKit-v1.1.0.zip` (excluding
   `*.tfstate*`, `*/.terraform/*`, `*.tfvars` and `*.tfplan`).
2. Publishes a GitHub Release using `RELEASE-NOTES.md` as the body.
3. Attaches the ZIP and `LICENSE` to the release.

### 6. Verify

- **Releases**: <https://github.com/luigilink/ARMConfigKit/releases> — the new release is listed with the expected body and ZIP.
- **Actions**: <https://github.com/luigilink/ARMConfigKit/actions> — `release.yml` ran green.
- **Wiki**: <https://github.com/luigilink/ARMConfigKit/wiki> — `wiki.yml` synced any `wiki/` changes pushed in the same release.

## Undoing a release

If you tagged too early:

```bash
git tag -d v1.1.0
git push origin --delete v1.1.0
```

Then delete the auto-created Release on GitHub, fix what needs fixing, commit, and re-tag
from the new HEAD.

> ⚠️ **Don't move a published tag** that has been live for more than a few minutes.
> Prefer publishing a `vX.Y.(Z+1)` patch release instead of rewriting `vX.Y.Z`.

## See also

- [Keep a Changelog](https://keepachangelog.com/en/1.0.0/)
- [Semantic Versioning 2.0](https://semver.org/spec/v2.0.0.html)
- [Getting Started](Getting-Started)
- [Configuration](Configuration)
- [Usage](Usage)
