# Security policy

## Reporting a vulnerability

Please report vulnerabilities privately through GitHub:
**[Report a vulnerability](https://github.com/D3m0nZOnFire/omarchy-dashboard/security/advisories/new)**
(repository → Security → Report a vulnerability).

Don't open a public issue or pull request for a security problem until a fix is released.

Include what you found, how to reproduce it, the version or commit you tested, and the impact you expect.
You'll get a reply as soon as possible. Once a fix is released, you'll be credited in the advisory unless you'd rather not be.

## Supported versions

Only the latest release gets security fixes. Update from Dashboard Settings → About → **Update now**, or re-run the install command.

## Scope

In scope: the dashboard, `install.sh`, `uninstall.sh` and the in-app updater, which installs the newest `vX.Y.Z` tag
and re-runs `install.sh` on your machine. Anything that could make the updater run code that isn't a release from this
repository is especially welcome.

Out of scope: bugs in Quickshell, Hyprland, Omarchy or wttr.in themselves. Report those upstream.
