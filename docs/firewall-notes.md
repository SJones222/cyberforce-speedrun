# Firewall notes

This repo does not install firewall rules because the scoring-engine source IP/network is unknown before the tryout.

At minimum, preserve the paths required by the packet:

- ICMP echo
- TCP/21 FTP control
- TCP/22 SSH
- UDP/53 DNS
- TCP/53 DNS
- TCP/80 HTTP
- TCP/3306 MariaDB

The repo's known-good vsftpd config constrains passive FTP data connections to TCP/30000-30010. If you later use a restrictive firewall, that range must also remain reachable for the scored file transfer.

Before changing firewall policy:

```bash
sudo nft list ruleset
sudo ss -lntup
sudo ./status.sh
```

After every firewall change, retest from another host. Local tests cannot prove remote reachability.
