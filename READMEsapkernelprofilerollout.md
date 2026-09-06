# SAP Fleet Kernel & Profile Rollout Assistant

An interactive Bash tool for rolling out SAP kernel checks and profile updates across a list of application servers — one controlled, logged, resumable run instead of manually logging into each host.

## What it does

Given a simple host file, the script walks each host in sequence and, for every one:

1. **Checks the current kernel version** (`disp+work -v`) via `pbrun`, so you can verify what's actually running before touching anything.
2. **Prompts you to confirm** whether to check the kernel and whether to update the profile on that specific host — nothing happens without an explicit yes.
3. **Applies the profile update** (`sapcpe`) if confirmed.
4. **Logs every command and result** to a timestamped log file, with pass/fail tracked per host.
5. **Prints a full run summary** at the end — hosts visited, kernel successes/failures/skips, profile successes/failures/skips.

It supports:
- **`--dry-run`** — walk the entire host list and show exactly what would run, without executing anything.
- **`--resume <hostname>`** — pick back up from a specific host if a previous run was interrupted, without repeating hosts already handled.
- **Abort at any point** — typing `abort` at any prompt stops the run cleanly and still prints the summary so far.

## Why it exists

Kernel and profile rollout cycles across a large SAP landscape are traditionally a manual, one-host-at-a-time process: log in, run a check, eyeball the output, run the update, log out, repeat — for every application server in scope. That's slow, easy to lose track of mid-way through a long list, and leaves no consistent audit trail unless someone keeps their own notes.

This script turns that into a single guided run: one host file, one command, a live decision point per host, and a complete log + summary at the end — while still keeping a human in the loop for every actual change (this is intentionally *not* a fully unattended, fire-and-forget tool).

## Prerequisites

- Bash
- `pbrun` (or adapt the remote-execution calls to your environment's privilege-access tool — e.g. `sudo`, `pbssh`, `ssh`)
- Standard SAP directory conventions (`/usr/sap/<SID>/<INST>/exe`, `/sapmnt/<SID>/profile`)
- A host file (see format below)

## Host file format

Plain text file, first line is the username to run as, each subsequent line is `<hostname> <profile_name>`:

```
sapadm
sapapp01 PRD_D00_sapapp01
sapapp02 PRD_D01_sapapp02
sapapp03 PRD_D02_sapapp03
```

## Usage

```bash
chmod +x sap-kernel-profile-rollout.sh

# Full interactive run
./sap-kernel-profile-rollout.sh hosts.txt

# Preview every action without executing anything
./sap-kernel-profile-rollout.sh hosts.txt --dry-run

# Resume a previously interrupted run starting from a specific host
./sap-kernel-profile-rollout.sh hosts.txt --resume sapapp02
```

You'll be prompted for the **SID** and **Instance number** at the start of the run, then walked through each host from the host file.

## Notes

- Always run with `--dry-run` first against a new host file to confirm the plan before making any live changes.
- The log file (`kernel_run_<timestamp>.log`) is written next to the script and captures every command's output — keep these for change records / audit purposes.
- Adapt the `pbrun` calls if your environment uses a different remote-execution or privileged-access tool.

## Background

This tool was built to bring a consistent, auditable process to large-scale SAP kernel and profile rollout cycles, replacing a manual, host-by-host workflow. Read the full case study →

## License

MIT — see [LICENSE](LICENSE).
