# Releasing

The dashboard updates itself from **tagged releases**, not from `main`. Both the
in-app updater (Dashboard Settings -> About) and `install.sh` look for the newest
tag matching `vX.Y.Z` and fast-forward the user's `main` to it.

So a commit on `main` is **not** live for anyone until you tag a release.

## Versioning

Semantic versioning, `vMAJOR.MINOR.PATCH`:

| Part  | Bump when                                                            |
| ----- | ------------------------------------------------------------------- |
| MAJOR | a change breaks existing setups (config format, Hypr wiring, deps) |
| MINOR | a new tile or user-facing feature, backwards compatible            |
| PATCH | bug fixes and polish only                                          |

Only tags of the exact form `v1.2.3` are offered to users. Anything else
(`v1.2.3-rc1`, `nightly`, ...) is ignored by the updater - use the `dev` branch
for pre-release testing instead (see below).

## Cutting a release

1. **Land everything on `main`** and push it. `main` must stay linear -
   never force-push, never rebase commits that are already pushed, or every
   user's `git merge --ff-only` will break on the next update.

2. **Smoke-test the exact commit you're about to tag:**
   ```sh
   cd ~/.config/quickshell/dashboard
   git switch main && git pull --ff-only
   qs -c dashboard            # foreground - must print "Configuration Loaded", no errors
   ```
   Open Dashboard Settings -> every page, especially **About**. Double-click a
   tile, drag one between edges, toggle a setting.

3. **Pick the version** by comparing what changed since the last tag:
   ```sh
   git describe --tags --abbrev=0          # last release
   git log --oneline "$(git describe --tags --abbrev=0)..HEAD"
   ```

4. **Tag it** (annotated, on `main` HEAD):
   ```sh
   git tag -a v1.2.0 -m "v1.2.0 - Google Tasks tile, weather retry fix"
   git push origin v1.2.0
   ```

5. **Write release notes** so the About page's "Read the release notes" link
   has something to show:
   ```sh
   gh release create v1.2.0 --title "v1.2.0" --generate-notes
   ```
   (Needs `gh auth login` once. No `gh`? Create the release from the tag on
   github.com and paste in the `git log` summary.)

6. **Verify** from a throwaway checkout:
   ```sh
   git clone --filter=blob:none https://github.com/D3m0nZOnFire/omarchy-dashboard /tmp/rel-check
   git -C /tmp/rel-check describe --tags        # should print the new tag
   rm -rf /tmp/rel-check
   ```
   Then in the running dashboard: About -> **Check for updates** should either
   say you're current (if your local `main` fast-forwarded to the tag) or offer
   the new version.

## Hotfix on an old release

```sh
git switch -c hotfix-v1.2.1 v1.2.0
# ... fix, commit ...
git tag -a v1.2.1 -m "v1.2.1 - crash on empty weather response"
git push origin v1.2.1
git switch main && git merge hotfix-v1.2.1 && git push      # carry the fix forward
```

## Testing changes before a release

Users (or you) can track a branch tip instead of releases:

```sh
BRANCH=dev bash <(curl -fsSL https://raw.githubusercontent.com/D3m0nZOnFire/omarchy-dashboard/dev/install.sh)
```

That checkout follows `dev`'s HEAD and ignores tags until it's moved back onto
`main`.

## Rules

- **Never delete or move a published tag.** Users who already fetched it will
  see their `main` "diverge" and the updater will refuse to fast-forward.
- **Never rewrite pushed `main` history** (rebase, amend, force-push) for the
  same reason.
- A release tag should point at a commit that's an ancestor of, or equal to,
  `main` - so `git merge --ff-only <tag>` always works from an older release.

## Optional hardening (not set up yet)

- **Signed tags:** `git config user.signingkey <key>` then `git tag -s`. The
  updater would need a `git verify-tag` step against a key pinned in the repo
  (separate from your GitHub account) to actually defend against a stolen
  GitHub token. See the updater block in `shell.qml`.
- **Repo size:** the theme screenshots in `assets/*.png` dominate `git`
  history (~50 MB). Moving them to the GitHub Release assets or a separate
  `media` branch and BFG-cleaning history would shrink clones a lot - but it's
  a history rewrite, so every existing clone would need re-cloning.
