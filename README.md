# Bazsyi Sunshine

Run Sunshine **before login** on Bazzite KDE so a paired Moonlight client can reach the normal Plasma login screen after a cold boot—without enabling auto-login.

## What it does

- Layers the official native Sunshine RPM from `lizardbyte/stable` when needed.
- Migrates an existing Flatpak pairing and credentials when native state is missing.
- Uses KMS capture so the stream works at Plasma Login Manager and in the desktop.
- Runs Sunshine as your desktop user, not as root.
- Grants device access only to the systemd service with supplementary groups.
- Disables the Sunshine tray so one process survives logout and login transitions.
- Starts PipeWire, PipeWire-Pulse, and WirePlumber before Sunshine.
- Waits for `sink-sunshine-stereo` so the first cold-boot stream has audio.
- Leaves auto-login and Plasma Login Manager unchanged.
- Keeps the Flatpak installation available as a rollback copy.

## Support status

V1 officially targets:

- Bazzite 44
- KDE Plasma
- Plasma Login Manager (`plasmalogin.service`)
- A physical display or display emulator that remains connected during boot

The first verified system used an NVIDIA RTX 4070 SUPER, KMS capture, NVENC, PipeWire 1.6.8, and Sunshine `2026.516.143833`.

This is an unofficial community project. Bazzite officially recommends the Sunshine Flatpak for normal desktop-session use. Native RPM layering is an alternative and may require maintenance after major Bazzite or Sunshine changes.

## Before installing

You need:

- A Bazzite KDE host
- A Moonlight client
- A display connected to the host
- Internet access for the initial RPM installation
- A user with `sudo` access

Do **not** enable auto-login. Do **not** run native and Flatpak Sunshine simultaneously.

## Quick install

```bash
git clone https://github.com/proxsyi/bazsyi-sunshine.git
cd bazsyi-sunshine
./install.sh
```

If Sunshine is not already layered, the installer adds the RPM to a pending deployment and asks you to reboot. After reboot:

```bash
cd bazsyi-sunshine
./install.sh
./verify.sh
```

Then reboot once more and connect from Moonlight at the Plasma login screen.

The installer does not reboot automatically and does not change auto-login.

## Existing Sunshine users

When native Sunshine has no identity yet, the installer copies these from the Flatpak configuration when available:

- `sunshine_state.json`
- `credentials/`
- `apps.json`

This normally preserves the existing Moonlight pairing. The Flatpak service is disabled only after the native installation is ready.

## Adapter and monitor selection

The installer finds the DRM render node attached to the first connected display and uses monitor index `0` by default.

Override either value when needed:

```bash
./install.sh --adapter /dev/dri/renderD129 --output 0
```

Or use environment variables:

```bash
BAZSYI_ADAPTER=/dev/dri/renderD129 BAZSYI_OUTPUT_NAME=0 ./install.sh
```

## Verify

```bash
./verify.sh
```

The verifier checks the package, KMS configuration, audio graph, linger state, service state, process count, Flatpak conflict, and current-boot audio errors.

For full logs:

```bash
sudo journalctl -b -u bazsyi-sunshine-prelogin.service --no-pager
```

## Files installed

- `/etc/systemd/system/bazsyi-sunshine-prelogin.service`
- `/etc/bazsyi-sunshine/install-state`
- `~/.config/bazsyi-sunshine/sunshine.conf`
- `~/.local/share/bazsyi-sunshine/backups/`

Your native Sunshine identity remains in `~/.config/sunshine/`.

## Uninstall and rollback

Remove the integration while keeping the native RPM and identity:

```bash
./uninstall.sh
```

Also remove the RPM layer when this installer originally added it:

```bash
./uninstall.sh --remove-package
```

The default uninstall restores Flatpak Sunshine when it is installed and restores the previous linger state.

## Security model

- Sunshine runs as your normal desktop user.
- The service receives `input`, `video`, and `render` as service-scoped supplementary groups.
- KMS requires `CAP_SYS_ADMIN`; the official RPM installs the needed file capability.
- Auto-login remains disabled, so the desktop password is still required.
- Pairing credentials are never added to this repository.

`CAP_SYS_ADMIN` is powerful. Review the service and installer before using them on a machine you do not fully control.

## Known limitations

- Remote wake from sleep is not configured in v1. Moonlight cannot wake a sleeping host over Tailscale unless Wake-on-LAN/WoWLAN and a reachable relay are configured separately.
- V1 is not tested on GNOME, SDDM, other Linux distributions, handheld game mode, hybrid-GPU laptops, or headless systems without a persistent display.
- Multi-monitor systems may need an explicit `--adapter` or `--output` value.
- The native RPM is layered into Bazzite, so installing or removing it can require a reboot.

## Why the audio wait exists

A Pulse socket can exist before PipeWire and WirePlumber are actually ready. Sunshine initializes audio once per stream; if it starts too early, the stream remains silent even after login. The service starts the user audio daemons, waits for the Sunshine virtual sink, and gives the graph two extra seconds before launching Sunshine.

## References

- [Bazzite Sunshine documentation](https://docs.bazzite.gg/Advanced/sunshine/)
- [Bazzite package layering](https://docs.bazzite.gg/Installing_and_Managing_Software/rpm-ostree/)
- [Sunshine getting started](https://docs.lizardbyte.dev/projects/sunshine/latest/md_docs_2getting__started.html)
- [Sunshine configuration](https://docs.lizardbyte.dev/projects/sunshine/latest/md_docs_2configuration.html)

## License

GPL-3.0-only. See [LICENSE](LICENSE).
