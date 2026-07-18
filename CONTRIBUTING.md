# Contributing

## Scope

V1 targets Bazzite KDE with Plasma Login Manager. Keep changes focused on a secure pre-login Sunshine path that does not enable auto-login.

## Workflow

1. Create a branch from `main`.
2. Keep commits small and use conventional commit messages.
3. Run the shell syntax checks.
4. Test install, cold boot, login, audio, input, and uninstall behavior when changing system integration.
5. Open a pull request with the tested Bazzite, Sunshine, desktop, GPU, and audio versions.

## Checks

```bash
bash -n install.sh verify.sh uninstall.sh
./install.sh --help
./verify.sh --help
./uninstall.sh --help
```

Never commit Sunshine credentials, pairing state, private keys, logs containing private network details, or machine-specific backups.
