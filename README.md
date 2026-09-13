# CyberForce Speedrun Toolkit

Competition-focused Debian 12 toolkit for rapidly establishing, validating, repairing, and auditing the six scored DOE CyberForce tryout services:

- ICMP echo replies
- SSH TCP/22 (`ssh-user` + scoring public key)
- Anonymous FTP TCP/21 (`/iloveftp.txt` -> `iloveftp`)
- MariaDB TCP/3306 (`scoring-sql` / `password` -> `cyberforce.supersecret.data` -> `7`)
- HTTP TCP/80 (`Hello World!`)
- DNS UDP+TCP/53 (`test.local` -> `10.10.10.10`)

This repo is designed for Debian 12 on both amd64 and arm64. It uses ordinary Debian packages and architecture-independent shell/config files.

## Safety model

The toolkit is deliberately conservative around the pre-compromised host:

- No script automatically kills suspicious processes.
- No script deletes users, SSH keys, cron jobs, or persistence.
- No script deploys a firewall policy.
- `audit-host.sh` is report-only.
- Live files are backed up before managed changes.
- SSH uses a Debian `sshd_config.d` drop-in and **adds** the scoring public key without deleting other keys.
- MariaDB uses a dedicated drop-in rather than editing Debian's `50-server.cnf`.
- DNS uses a dedicated zone fragment included from `named.conf.local`; it refuses to overwrite an unrelated existing `test.local` zone automatically.
- FTP is the main service for which a complete known-good daemon config is intentionally installed.

The explicitly scored MariaDB table and scoring account are rebuilt to a known-good state. An existing `cyberforce` database is dumped first when possible.

## Fastest competition workflow

If Git is not already installed:

```bash
sudo apt-get update && sudo apt-get install -y git
```

Then:

```bash
git clone YOUR_REPO_URL
cd cyberforce-speedrun
sudo ./preflight.sh
sudo ./setup-all.sh
sudo ./status.sh
```

`setup-all.sh` does the following:

1. Captures a pre-change baseline under `/root/cyberforce-backups/`.
2. Installs any missing packages.
3. Configures all six scored services.
4. Validates each service locally.

After all services are green, establish an integrity baseline and collect a defensive audit:

```bash
sudo ./integrity-baseline.sh
sudo ./audit-host.sh
```

## Rapid repair

Repair only the service that is failing:

```bash
sudo ./repair.sh http
sudo ./repair.sh ssh
sudo ./repair.sh ftp
sudo ./repair.sh mariadb
sudo ./repair.sh dns
sudo ./repair.sh icmp
```

Then immediately validate again:

```bash
sudo ./status.sh
```

## Remote scoring-style validation

Local health does **not** prove remote scoring reachability. From another Linux host with the needed clients installed:

```bash
./verify-remote.sh TARGET_IP
```

If you have a private key matching the scoring public key (normally only in your practice lab):

```bash
./verify-remote.sh TARGET_IP /path/to/private_key
```

Without a matching private key, the SSH transaction is reported as `SKIP`, not `PASS`.

## Monitoring

Local checks every 60 seconds:

```bash
sudo ./watch-score.sh local
```

Practice at a five-second cadence:

```bash
sudo INTERVAL=5 ./watch-score.sh local
```

Remote checks:

```bash
./watch-score.sh remote TARGET_IP /path/to/private_key
```

## Defensive triage

Generate a read-only host audit:

```bash
sudo ./audit-host.sh
```

Compare scored files to repo-known-good copies:

```bash
./diff-config.sh
```

Check whether scored files changed since your post-setup baseline:

```bash
sudo ./integrity-check.sh
```

Collect focused troubleshooting evidence:

```bash
./collect-logs.sh http
./collect-logs.sh ssh
./collect-logs.sh ftp
./collect-logs.sh mariadb
./collect-logs.sh dns
./collect-logs.sh icmp
```

Inspect, but do not change, firewall state:

```bash
sudo ./firewall-audit.sh
```

## Important FTP firewall note

The known-good vsftpd configuration uses passive TCP ports `30000-30010` in addition to TCP/21. A restrictive firewall that permits only TCP/21 can allow FTP login while breaking the scored file transfer.

No firewall rules are installed by this repository.

## DNS conflict behavior

`setup-dns.sh` refuses to silently overwrite another `test.local` zone definition. If it reports a conflict, inspect the path it prints. This is intentional: blindly replacing `named.conf.local` could destroy legitimate competition DNS configuration.

## SSH behavior

The scoring key is stored in the repository because it is a **public** key supplied by the tryout packet. No private key is included.

The toolkit:

- creates `ssh-user` if needed,
- ensures a usable home and shell,
- appends the scoring public key if missing,
- uses correct `.ssh` ownership/modes,
- requires TCP/22 and public-key authentication,
- disables password authentication specifically for `ssh-user`.

It does not automatically remove unexplained extra keys; use `audit-host.sh` to review them before removing anything.

## Repository validation

Run before relying on the toolkit:

```bash
./validate-repo.sh
```

It runs `bash -n` on every shell script, scoring-constant checks, duplicate-directive checks, CRLF checks, a secret/private-key guard, and ShellCheck when ShellCheck is installed.

GitHub Actions also runs the validator with ShellCheck on every push and pull request.

## Repository layout

```text
.
├── setup-all.sh
├── preflight.sh
├── install-packages.sh
├── status.sh
├── verify-local.sh
├── verify-remote.sh
├── repair.sh
├── restore-config.sh
├── backup-state.sh
├── audit-host.sh
├── diff-config.sh
├── collect-logs.sh
├── firewall-audit.sh
├── integrity-baseline.sh
├── integrity-check.sh
├── watch-score.sh
├── validate-repo.sh
├── scripts/
│   ├── setup-http.sh
│   ├── setup-ssh.sh
│   ├── setup-ftp.sh
│   ├── setup-mariadb.sh
│   ├── setup-dns.sh
│   └── setup-icmp.sh
├── configs/
│   ├── apache/
│   ├── ssh/
│   ├── vsftpd/
│   ├── mariadb/
│   └── bind/
└── docs/
```

## Do not commit

Do not add any of the following to this repo:

- competition root/user passwords,
- VPN or SDC credentials,
- SSH private keys,
- GitHub access tokens,
- API tokens,
- generated host backups or audit output.

The `.gitignore` blocks common secret/private-key filenames, but do not depend on `.gitignore` as your only secret-control measure.

## Practice recommendation

Before tryouts, run `setup-all.sh` on a disposable Debian 12 VM, deliberately break one service at a time, and recover it with `repair.sh`. Practice until the sequence feels automatic:

```text
remote symptom -> systemctl -> ss -> service validator/state -> journalctl -> repair -> remote retest
```
