# Contributing to PWM

Thanks for your interest in improving PWM. This guide outlines how to get set up, report issues, and submit changes.

## Development setup
- Install the C3 compiler (v0.7.7 or later) and SQLCipher/SQLite3 headers and libraries. The default linker search path is `/opt/homebrew/opt/sqlcipher/lib`; adjust `project.json` if needed.
- Build from the repo root with `c3c build pwm`. Run the CLI with `c3c run pwm -- --help` or the compiled binary under `./build/`.
- Automated tests are not yet wired up. Please exercise manual flows relevant to your change (init a vault, add/get/remove entries) and note any gaps in your PR. Test additions are welcome under `test/`.

## Reporting bugs and requesting features
- Check for existing issues first. Include your OS, C3 compiler version, SQLCipher/SQLite version, PWM version (or commit), and any environment customizations.
- Provide clear repro steps and example command lines. Avoid sharing real secrets or production vaults.
- If the issue is security-sensitive, follow the guidance in `SECURITY.md` instead of filing a public issue.

## Pull request guidelines
- Use topic branches and keep PRs focused. Update docs/help text when behavior changes.
- Run `c3c build pwm` before opening a PR and verify the flows your change touches.
- Keep secrets, generated binaries, and local vault/database files out of commits. If you need fixtures, mock them.
- Match the existing code style and module structure; favor small, clear functions with explicit cleanup of sensitive data.
- Add context in the PR description: motivation, approach, and any follow-up TODOs.

## Documentation
- Update `README.md` for user-visible changes and `tech.md` for architectural or operational updates.
- Inline comments should stay minimal; prefer self-explanatory code and concise doc updates.

## Community expectations
Participation in this project is governed by the `CODE_OF_CONDUCT.md`. By contributing, you agree to uphold it.
