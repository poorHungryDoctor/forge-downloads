# Forge downloads

Packaged downloads of the Forge command-line tool (Windows x64 and Linux x64),
Forge Process Metrics, and Forge Branch Review for VS Code. No access to the
private source repository is needed.

Download a specific version from [Releases](https://github.com/jjolliff/forge-downloads/releases)
when you need a reproducible install. The examples below use the latest release.
Download the matching **sha256.txt** and verify each file before installing it.

## Windows: Forge CLI

In PowerShell:

```powershell
$base = 'https://github.com/jjolliff/forge-downloads/releases/latest/download'
curl.exe -fL "$base/forgeWindowsX64.zip" -o forgeWindowsX64.zip
curl.exe -fL "$base/sha256.txt" -o sha256.txt
Get-FileHash forgeWindowsX64.zip -Algorithm SHA256
# Compare the hash with the forgeWindowsX64.zip line in sha256.txt before extracting.
Expand-Archive forgeWindowsX64.zip -DestinationPath "$HOME\tools\forge" -Force
& "$HOME\tools\forge\forge.exe" --help
```

The ZIP contains **forge.exe**; no installer or clone is required. Add
`$HOME\tools\forge` to your `PATH` to invoke `forge` without its full path.

## Linux: Forge CLI

```bash
base=https://github.com/jjolliff/forge-downloads/releases/latest/download
curl -fL "$base/forgeLinuxX64.tar.gz" -o forgeLinuxX64.tar.gz
curl -fL "$base/sha256.txt" -o sha256.txt
grep ' forgeLinuxX64.tar.gz$' sha256.txt | sha256sum -c -
mkdir -p "$HOME/.local/bin"
tar -xzf forgeLinuxX64.tar.gz -C "$HOME/.local/bin"
"$HOME/.local/bin/forge" --help
```

The tarball contains a statically linked **forge** executable. Add
`$HOME/.local/bin` to `PATH` if needed. Some commands, such as `forge format`, also
need external tools (for example clang-format 23.1.1); `forge --help` lists the
available commands.

## Install a VS Code extension

Download the VSIX for the extension you need and the matching
[sha256.txt](https://github.com/jjolliff/forge-downloads/releases/latest/download/sha256.txt).
In PowerShell, use `Get-FileHash .\forge-branch-review.vsix -Algorithm SHA256`
(or the metrics filename) and compare it with that file's entry in **sha256.txt**.

In VS Code, run **Extensions: Install from VSIX...**, select the downloaded file,
and reload the window. No source checkout, Node.js, npm, or build step is needed.
To upgrade, install the newer VSIX and reload again.

## VS Code: Branch Review

Download [forge-branch-review.vsix](https://github.com/jjolliff/forge-downloads/releases/latest/download/forge-branch-review.vsix).
Requires VS Code 1.90 or newer, Git, the built-in Git extension, and a trusted
repository folder.

Run **Forge Branch Review: Compare Current Branch...**, choose a repository if
needed, and select a local branch, cached remote branch (such as `origin/main`),
tag, or commit as the base. **Source Control > Branch Review** lists added,
modified, deleted, and renamed files. Select a text file to open its read-only
native diff. Use the branch icon to change the base and the refresh icon after
commits, external branch switches, or an explicit fetch.

The comparison shows committed branch changes from the common ancestor to
current `HEAD`, equivalent to `git diff base...HEAD`. Staged edits, unstaged
edits, and untracked files are excluded. The extension never fetches or checks
out a branch; remote refs use the local cache. Binary files are listed with a
notice instead of a text diff. Missing refs and unavailable history show an
explanation. Partial clones require Git with `--no-lazy-fetch` support; older
Git can review full local clones.

If VS Code is configured for inline diffs, opening a file offers to enable
side-by-side diffs in user settings. The installed extension's README contains
the complete behavior and limitations.

## VS Code: Process Metrics

Download [forge-metrics.vsix](https://github.com/jjolliff/forge-downloads/releases/latest/download/forge-metrics.vsix).
Shows live CPU and resident memory for a process on the workspace machine.
Supports Windows and Linux.

For a local debug launch, press F5. The history view opens immediately and starts
sampling when the debugger reports the process ID. If it is waiting for a PID,
use **Select process...** in the view. For a process started in a terminal or
elsewhere, run **Forge Metrics: Monitor Process...** and select it by name or PID.
Use **Forge Metrics: Enter Process ID...** when the process is not listed.

The status bar shows live CPU and RAM; click it for up to 90 seconds of history.
The final graph stays visible after exit. CPU 100% means one fully busy logical
core, so multithreaded programs can exceed 100%. RAM is resident memory for the
selected process, not total allocations, GPU memory, or its child processes.
The installed extension's README also describes automatic monitoring for
opted-in direct process tasks.

### Windows memory capture

The same **forge.exe** also provides `forge memory`.
Use the Windows binary and Metrics VSIX from the same release. No second native
tool or Forge PDB is needed for monitor/window capture. Configure absolute local
paths and literal arguments in VS Code settings:

```json
{
    "forgeMetrics.forgePath": "C:\\Tools\\forge.exe",
    "forgeMetrics.memoryProfileTarget": {
        "executable": "C:\\Work\\bin\\program.exe",
        "args": ["input with spaces.dat", "--quality", "20"],
        "cwd": "C:\\Work",
        "intervalMs": 50,
        "timeoutMs": 60000,
        "durationMs": 100
    }
}
```

Run **Forge Metrics: Capture Memory Monitor...** for private commit and working
set without a debugger, ETW or symbols. Run **Forge Metrics: Capture Startup
Allocation Window...** for an intrusive startup-prefix heap-stack capture. That
mode requires the target's matching adjacent local PDB, can substantially slow
the target, and keeps a debugger attached until exit. It is not CPU profiling,
whole-run allocation accounting, or a leak detector. Windows ETW permissions
depend on the machine; no automatic elevation or symbol download occurs.

Capture requires a trusted local Windows workspace, not SSH/WSL. Choose a report
folder and confirm the target. Cancellation requests cooperative cleanup of the
launched PID, not its descendants, and waits for Forge to exit. Reports are
preserved; existing files are not overwritten. Normal F5 live metrics are unchanged.

### Saved memory profiles

Run **Forge Metrics: Open Memory Profile...** to view a saved Forge JSON report.
The viewer shows private-commit/working-set timelines and, where captured,
allocation traffic, request counts and observed live-byte flame graphs. Zoom,
search and sortable hotspots operate on aggregate allocation groups, not CPU
durations or a selected time range. Source locations are text only.

Reports remain local. Partial capture, lost events and missing symbols are shown
explicitly; oversized or malformed reports are rejected. Historical memoryProbe
reports remain supported. The installed extension's README has the full limits.