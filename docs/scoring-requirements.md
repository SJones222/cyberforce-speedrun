# Scoring requirements

| Service | Requirement |
|---|---|
| ICMP | Target replies to ping |
| SSH | TCP/22; `ssh-user`; supplied Ed25519 public key authenticates |
| FTP | TCP/21; anonymous download of `/iloveftp.txt`; contents `iloveftp` |
| MariaDB | TCP/3306; `scoring-sql` / `password`; `cyberforce.supersecret.data`; value `7` |
| HTTP | TCP/80; `/` returns `Hello World!` |
| DNS | UDP/53 and TCP/53; `test.local` resolves to `10.10.10.10` |

The packet says the scoring engine checks every 60 seconds. Five consecutive failed checks trigger an SLA penalty.

## Preserve these intentionally insecure scoring requirements

Do not harden away:

- anonymous FTP,
- the fixed MariaDB scoring credential,
- remote MariaDB connectivity,
- the scoring SSH key,
- public-key SSH authentication,
- ICMP replies,
- TCP/53 or UDP/53,
- HTTP TCP/80.
