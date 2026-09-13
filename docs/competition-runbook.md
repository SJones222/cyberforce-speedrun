# Competition runbook

## Initial minutes

```bash
whoami
hostname
date
ip -br addr
ip route
sudo ss -lntup
systemctl --failed
who
w
```

Open the scoreboard immediately and record which services are green/red.

If service setup is required:

```bash
sudo ./preflight.sh
sudo ./setup-all.sh
sudo ./status.sh
```

Then establish a post-setup integrity baseline:

```bash
sudo ./integrity-baseline.sh
```

## Defensive triage

```bash
sudo ./audit-host.sh
sudo ss -ntup
ps auxf
awk -F: '$3==0 {print}' /etc/passwd
getent group sudo
sudo find /root /home -type f -name authorized_keys -print 2>/dev/null
systemctl --type=service --state=running
systemctl list-timers --all
sudo cat /etc/crontab
sudo crontab -l
```

Do not automatically remove something merely because it is unfamiliar. Determine whether it belongs to Debian, SSH, Apache, vsftpd, MariaDB, BIND, or competition infrastructure first.

## During the event

When a scored service turns red, switch immediately to availability recovery:

```bash
sudo ./status.sh
sudo ./repair.sh SERVICE
sudo ./status.sh
```

Then return to defensive triage.
