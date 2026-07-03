# ARMConfigKit - Contributing

Thanks for your interest in improving ARMConfigKit!

## Workflow

1. **Open an issue first.** Use one of the issue templates (bug, feature,
   documentation, improvement) to describe the change before you start.
2. **Branch from `main`** and keep commits atomic (one logical change per commit).
3. **Reference the issue** in your commits and close it from the pull request with
   a closing keyword (e.g. `Fixes #123`).
4. **Update `CHANGELOG.md`** under the `[Unreleased]` section — an entry is
   mandatory for every PR.
5. **Open a Pull Request** using the PR template and complete the task list.

## Style

- Terraform: run `terraform fmt -recursive` and `terraform validate` before
  committing.
- PowerShell (`scripts/`): follow the existing formatting (2-space indent,
  approved verbs); scripts target PowerShell 7+.

See the [Wiki](https://github.com/luigilink/ARMConfigKit/wiki) for setup and usage
details.
