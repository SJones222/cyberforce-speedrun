# Five-minute recovery flow

Use the same sequence for every red service.

```text
1. Reproduce remotely.
2. Check service state.
3. Check listener/address/protocol.
4. Validate configuration and required scoring data.
5. Check recent logs.
6. Check binding, permissions, authentication, and firewall.
7. Make the smallest corrective change.
8. Retest the actual remote transaction.
```

Universal commands:

```bash
systemctl status SERVICE
sudo ss -lntup
sudo journalctl -u SERVICE --since '10 minutes ago'
sudo nft list ruleset
```

Repair wrapper:

```bash
sudo ./repair.sh http
sudo ./repair.sh ssh
sudo ./repair.sh ftp
sudo ./repair.sh mariadb
sudo ./repair.sh dns
sudo ./repair.sh icmp
```

## Symptom shortcuts

| Symptom | First suspicion |
|---|---|
| Multiple services fail simultaneously | network/interface/firewall |
| Service is `failed` | configuration + logs |
| Port absent from `ss` | daemon/config/binding |
| Local works, remote fails | binding/firewall/network |
| SSH says `Permission denied (publickey)` | key, ownership/modes, SSH access rules |
| FTP login succeeds but file transfer hangs | passive/data connection |
| MariaDB local works but remote fails | bind address, `user@host`, firewall |
| SQL login works but query is denied | grants |
| DNS UDP works but TCP fails | TCP/53 path/firewall |
| DNS TCP works but UDP fails | UDP/53 path/firewall |
| Apache says `Syntax OK` but will not start | overlapping/specific `Listen` directives or another process owns TCP/80 |
| HTTP connects but scorer is red | exact response body |
| Ping fails but application ports work | ICMP-specific sysctl/firewall |
