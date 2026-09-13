# Command cheat sheet

## Universal

```bash
ip -br addr
ip route
sudo ss -lntup
sudo ss -ntup
systemctl status SERVICE
sudo systemctl restart SERVICE
sudo journalctl -u SERVICE --since '10 minutes ago'
sudo journalctl -xeu SERVICE
sudo nft list ruleset
```

## HTTP / Apache

```bash
curl -v http://TARGET/
sudo apache2ctl configtest
sudo apache2ctl -S
cat /var/www/html/index.html
sudo ss -lntp | grep ':80'
```

## SSH

```bash
sudo sshd -t
sudo sshd -T
ssh -vvv -i KEY ssh-user@TARGET
id ssh-user
sudo ls -ld /home/ssh-user /home/ssh-user/.ssh
sudo ls -l /home/ssh-user/.ssh/authorized_keys
sudo cat /home/ssh-user/.ssh/authorized_keys
sudo ss -lntp | grep ':22'
```

## FTP / vsftpd

```bash
curl -v ftp://TARGET/iloveftp.txt
systemctl status vsftpd
grep -Ev '^[[:space:]]*(#|$)' /etc/vsftpd.conf
ls -l /srv/ftp/iloveftp.txt
cat /srv/ftp/iloveftp.txt
sudo ss -lntp | grep ':21'
```

If login works but transfer fails, think passive FTP/data ports.

## MariaDB

```bash
systemctl status mariadb
sudo ss -lntp | grep ':3306'
sudo mariadb
mariadb -h TARGET -u scoring-sql -ppassword
```

```sql
SHOW DATABASES;
SELECT User,Host FROM mysql.user WHERE User='scoring-sql';
SHOW GRANTS FOR 'scoring-sql'@'%';
SELECT * FROM cyberforce.supersecret;
```

## DNS / BIND

```bash
systemctl status named
sudo named-checkconf
sudo named-checkconf -z
sudo named-checkzone test.local /etc/bind/db.test.local
dig @TARGET test.local A +short
dig +tcp @TARGET test.local A +short
sudo ss -lntup | grep ':53'
```

## ICMP

```bash
ping TARGET
sysctl net.ipv4.icmp_echo_ignore_all
ip -br addr
ip route
sudo nft list ruleset
```

## Users / access

```bash
who
w
last
awk -F: '$3==0 {print}' /etc/passwd
awk -F: '$3>=1000 {print}' /etc/passwd
getent group sudo
sudo -l -U USER
sudo find /root /home -type f -name authorized_keys -print 2>/dev/null
```

## Processes / persistence

```bash
ps auxf
sudo ss -lntup
sudo ss -ntup
ps -fp PID
sudo readlink -f /proc/PID/exe
systemctl --type=service --state=running
systemctl list-unit-files --type=service --state=enabled
systemctl list-timers --all
sudo cat /etc/crontab
sudo crontab -l
sudo find /tmp /var/tmp /dev/shm -type f -executable -ls 2>/dev/null
sudo find / -xdev -type f -perm -4000 -ls 2>/dev/null
```

## Toolkit shortcuts

```bash
sudo ./status.sh
sudo ./repair.sh SERVICE
sudo ./audit-host.sh
./diff-config.sh
sudo ./integrity-check.sh
./collect-logs.sh SERVICE
```
