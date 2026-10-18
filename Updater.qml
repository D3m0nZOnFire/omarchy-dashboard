import QtQuick
import Quickshell
import Quickshell.Io

// Backs the settings modal's About page. It tracks tagged releases on
// GitHub (vX.Y.Z), not raw `main`. The check is read-only git run from
// here; the update itself - fast-forward `main` to the newest release
// tag, then a full install.sh re-run (deps, the autostart hook) - runs in a
// detached terminal via omarchy-launch-terminal, so it survives the
// hot-reload the new files trigger. install.sh needs a password for the
// package installs. `-c core.hooksPath=/dev/null` keeps a tampered
// .git/hooks from running during any of it; `--ff-only` blocks history
// rewrites and rollbacks. See RELEASING.md for how tags are published.
Scope {
    id: updater

    // The SettingsModal whose About page shows the state (updateState,
    // updateError, latestVersion, incomingLog, commitsBehind, dirtyFiles).
    property var modal

    readonly property string _repoDir:   Quickshell.env("HOME") + "/.config/quickshell/dashboard"
    readonly property string _repoHttps: "https://github.com/D3m0nZOnFire/omarchy-dashboard.git"
    readonly property string repoWeb:    "https://github.com/D3m0nZOnFire/omarchy-dashboard"
    // Shared by the check and the update: newest vX.Y.Z tag, newest first.
    readonly property string _tagPick:
        "git tag -l --sort=-v:refname | grep -E '^v[0-9]+\\.[0-9]+\\.[0-9]+$' | head -n1"

    property string verName: ""      // installed release, e.g. "v1.0.0" (git describe)
    property string verSubject: ""
    property string verDate: ""

    function _readVersion() { versionProc.running = true }
    function checkForUpdate() {
        if (modal.updateState === "checking" || modal.updateState === "launching") return
        modal.updateError = ""
        modal.updateState = "checking"
        checkProc.running = true
    }
    function runUpdate() {
        if (modal.updateState === "checking" || modal.updateState === "launching") return
        modal.updateError = ""
        modal.updateState = "checking"
        statusProc.running = true
    }
    function _lines(s) {
        return String(s || "").split("\n").filter(function(l) { return l.trim() !== "" })
    }

    // Installed version line: `git describe` + the tip commit's subject / age.
    Process {
        id: versionProc
        running: false
        command: ["bash", "-c",
            "d=$1; git -C \"$d\" describe --tags --always 2>/dev/null || echo '?'; "
            + "git -C \"$d\" log -1 --format=%s%x1f%cr",
            "_", updater._repoDir]
        stdout: StdioCollector {
            id: versionOut
            onStreamFinished: {
                var ls = updater._lines(versionOut.text)
                updater.verName = ls[0] || "?"
                var meta = String(ls[1] || "").split("\x1f")
                updater.verSubject = meta[0] || ""
                updater.verDate    = meta[1] || ""
            }
        }
    }

    // ── check: fetch tags, report installed vs newest release + changelog ──
    // Output is line-prefixed so a partial read can't be misparsed:
    //   err-network        fetch failed
    //   cur <tag|>         nearest release tag reachable from HEAD
    //   new <tag|>         newest vX.Y.Z tag on the remote
    //   log <subject>      one per commit between cur and new
    Process {
        id: checkProc
        running: false
        command: ["bash", "-c",
            "d=$1; url=$2; "
            + "git -C \"$d\" -c core.hooksPath=/dev/null fetch --tags --quiet \"$url\" || { echo err-network; exit 0; }; "
            + "cur=$(git -C \"$d\" describe --tags --abbrev=0 2>/dev/null || true); "
            + "new=$(cd \"$d\" && " + updater._tagPick + "); "
            + "echo \"cur $cur\"; echo \"new $new\"; "
            + "if [ -n \"$new\" ] && [ \"$cur\" != \"$new\" ]; then "
            + "git -C \"$d\" log --format='log %s' \"${cur:+$cur..}$new\"; fi",
            "_", updater._repoDir, updater._repoHttps]
        stdout: StdioCollector {
            id: checkOut
            onStreamFinished: {
                var cur = "", neu = "", log = [], net = true
                updater._lines(checkOut.text).forEach(function(l) {
                    if (l === "err-network") net = false
                    else if (l.indexOf("cur ") === 0) cur = l.slice(4).trim()
                    else if (l.indexOf("new ") === 0) neu = l.slice(4).trim()
                    else if (l.indexOf("log ") === 0) log.push(l.slice(4))
                })
                if (!net) {
                    modal.updateError = "Couldn't reach GitHub. Check your connection and retry."
                    modal.updateState = "error"
                    return
                }
                modal.latestVersion = neu
                modal.incomingLog = log
                modal.commitsBehind = log.length
                modal.updateState = (neu !== "" && neu !== cur) ? "available" : "uptodate"
            }
        }
    }

    // ── run flow: dirty guard, then hand off to a detached terminal ──
    Process {
        id: statusProc
        running: false
        command: ["git", "-c", "core.hooksPath=/dev/null",
                  "-C", updater._repoDir, "status", "--porcelain", "--untracked-files=no"]
        stdout: StdioCollector {
            id: statusOut
            onStreamFinished: {
                var lines = updater._lines(statusOut.text)
                if (lines.length > 0) {
                    modal.dirtyFiles = lines.map(function(l) { return l.slice(3) })
                    modal.updateState = "dirty"
                    return
                }
                modal.updateState = "launching"
                termProc.startDetached()
                launchTimeout.restart()
            }
        }
    }
    // The whole update, in a terminal that outlives this shell's hot-reload:
    // fetch tags over HTTPS, fast-forward `main` to the newest release tag,
    // then install.sh for deps + the autostart hook. On success the
    // dashboard is restarted on the new release (`qs kill`, not a pgrep
    // pattern, which would also match this very command line) and the
    // terminal closes itself; on failure the prompt stays open on a `read`
    // so the error is visible. setsid + -d so the new instance outlives the
    // terminal's systemd scope - see the note in install.sh. The restart
    // polls `qs list` - waits for the old instance to go, then confirms the
    // new one is up - rather than sleeping a fixed time.
    //
    // Started with startDetached(), never `running = true`:
    // omarchy-launch-terminal exec()s all the way down into the terminal
    // itself, so an attached termProc *is* the terminal - and Quickshell
    // stops its running Processes on a clean exit, so the `qs kill` above
    // took the terminal (and the relaunch after it) down with the dashboard.
    // Detached, nothing reports back, so launchTimeout is the only net.
    Process {
        id: termProc
        running: false
        command: ["omarchy-launch-terminal", "bash", "-c",
            "d=$1; url=$2; cd \"$d\" || exit 1; "
            + "git -c core.hooksPath=/dev/null fetch --tags --quiet \"$url\" && "
            + "tag=$(" + updater._tagPick + ") && [ -n \"$tag\" ] && "
            + "echo \"Updating to $tag\" && "
            + "git -c core.hooksPath=/dev/null merge --ff-only \"$tag\" && "
            + "./install.sh; "
            + "ec=$?; "
            + "up() { qs list -c dashboard 2>/dev/null | grep -q '^Instance'; }; "
            + "if [ $ec -eq 0 ]; then "
            + "echo; echo 'Update finished - restarting the dashboard'; "
            + "qs kill -c dashboard >/dev/null 2>&1; "
            + "for i in $(seq 50); do up || break; sleep 0.2; done; "
            + "setsid qs -c dashboard -d -n >/dev/null 2>&1; "
            + "for i in $(seq 25); do up && exit 0; sleep 0.2; done; "
            + "echo 'The dashboard did not come back up - run: qs -c dashboard'; ec=1; fi; "
            + "echo; read -rp \"Something went wrong (exit $ec) - press Enter to close \" _",
            "_", updater._repoDir, updater._repoHttps]
    }
    Timer {
        id: launchTimeout
        interval: 8000
        onTriggered: {
            if (modal.updateState !== "launching") return
            modal.updateError = "The update terminal never appeared to open. Run it manually: "
                + updater._repoDir + "/install.sh"
            modal.updateState = "error"
        }
    }

    Component.onCompleted: updater._readVersion()
}
