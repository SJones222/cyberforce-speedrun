# Validation report

Validation completed before handoff.

## Passed locally

- `bash -n` passed for every `.sh` file in the repository.
- Every shell script has its executable bit set.
- `git diff --check` found no whitespace errors.
- Repository scoring constants matched the tryout packet.
- HTTP known-good body was verified as exactly 12 bytes: `Hello World!`.
- Apache TCP/80 listener normalization regression tests passed for loopback-only, already-good wildcard, IPv4 wildcard, IPv6-only, overlapping/duplicate, and missing-listener cases. Each case was run twice to verify idempotency.
- The Apache setup now separates syntax validation from runtime validation: it runs `apache2ctl configtest`, restarts Apache, verifies `apache2.service` is active, confirms a non-loopback TCP/80 listener with `ss`, and checks the exact HTTP body.
- The supplied Ed25519 scoring public key was base64-decoded and structurally validated as a 32-byte Ed25519 public key.
- The BIND zone file was parsed with `dnspython`; `test.local` has the exact A record `10.10.10.10`.
- vsftpd and MariaDB managed key/value configs contain no duplicate managed keys.
- No CRLF line endings were found in shell/config/SQL files.
- No private-key headers or GitHub personal-access-token patterns were found.
- A destructive-action grep found no automatic `userdel`, `killall`, `rm -rf`, firewall flush/add/delete, or crontab-removal behavior.

## Debian 12 compatibility review

The managed paths, units, and directives were reviewed against Debian Bookworm package/manpage documentation for:

- OpenSSH (`ssh.service`, `/etc/ssh/sshd_config.d/*.conf`)
- vsftpd (`vsftpd.service`, `/etc/vsftpd.conf`)
- MariaDB 10.11 (`mariadb.service`, `/etc/mysql/mariadb.conf.d/`)
- BIND9 (`named.service`, `/etc/bind/`)
- Apache2 (`/etc/apache2/`, `apache2ctl configtest`, active include discovery, runtime TCP/80 listener verification)

The Debian package pages list arm64 builds for the relevant services; the scripts themselves do not contain architecture-specific binaries or paths.

## Validation limitations

ShellCheck was not installed in the build execution environment and could not be installed because that environment did not have package-download network access. `validate-repo.sh` automatically runs ShellCheck when it is available, and the included GitHub Actions workflow installs ShellCheck before running repository validation.

`named-checkzone` was also unavailable in the build execution environment. The zone was instead parsed with `dnspython`; on the actual Debian target, `setup-dns.sh` requires and runs both `named-checkzone` and `named-checkconf -z` before restarting BIND.

No static review can guarantee that an inherited competition host has not been modified in a way that conflicts with the toolkit. The setup scripts therefore validate effective state after changes. Apache TCP/80 is a deliberate exception where a conflicting or address-specific active `Listen` directive may be backed up and disabled so the scored HTTP service can bind one wildcard listener; BIND and SSH remain conservative about unrelated configuration.

A full runtime rehearsal on the practice Debian 12 VM is still strongly recommended before the live tryout.
