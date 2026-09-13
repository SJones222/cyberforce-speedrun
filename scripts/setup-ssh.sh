#!/usr/bin/env bash
set -u
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
. "$ROOT/lib/common.sh"
require_root

have_cmd sshd || die "openssh-server is not installed. Run ./install-packages.sh first."
KEY_FILE="$ROOT/configs/ssh/scoring_authorized_keys"
DROPIN_SRC="$ROOT/configs/ssh/00-00-cyberforce-scoring.conf"
DROPIN_DIR=/etc/ssh/sshd_config.d
DROPIN="$DROPIN_DIR/00-00-cyberforce-scoring.conf"

if ! id ssh-user >/dev/null 2>&1; then
    log "Creating ssh-user..."
    useradd -m -s /bin/bash ssh-user
fi
usermod -s /bin/bash ssh-user
HOME_DIR="$(getent passwd ssh-user | cut -d: -f6)"
[ -n "$HOME_DIR" ] || die "Unable to determine ssh-user home directory."
mkdir -p "$HOME_DIR"
chown ssh-user:ssh-user "$HOME_DIR"
chmod go-w "$HOME_DIR"

# A newly useradd-created account can be password-locked, which can prevent SSH
# access on some PAM/account configurations even when public-key auth is used.
# If it is locked, unlock it with an unknown random password and then explicitly
# disable password authentication for ssh-user in the managed SSH drop-in.
ACCOUNT_STATE="$(passwd -S ssh-user 2>/dev/null | awk '{print $2}' || true)"
if [ "$ACCOUNT_STATE" = L ]; then
    RANDOM_PASSWORD="$(dd if=/dev/urandom bs=48 count=1 2>/dev/null | base64 | tr -d '\n')"
    printf 'ssh-user:%s\n' "$RANDOM_PASSWORD" | chpasswd
    unset RANDOM_PASSWORD
    log "Unlocked ssh-user with a random unknown password; password SSH is disabled for this account."
fi

install -d -m 0700 -o ssh-user -g ssh-user "$HOME_DIR/.ssh"
touch "$HOME_DIR/.ssh/authorized_keys"
chown ssh-user:ssh-user "$HOME_DIR/.ssh/authorized_keys"
chmod 0600 "$HOME_DIR/.ssh/authorized_keys"

SCORING_KEY="$(cat "$KEY_FILE")"
if ! grep -qxF "$SCORING_KEY" "$HOME_DIR/.ssh/authorized_keys" 2>/dev/null; then
    backup_file "$HOME_DIR/.ssh/authorized_keys"
    printf '%s\n' "$SCORING_KEY" >> "$HOME_DIR/.ssh/authorized_keys"
    log "Added scoring public key without deleting existing keys."
else
    log "Scoring public key already present."
fi

mkdir -p "$DROPIN_DIR"
install_managed_file "$DROPIN_SRC" "$DROPIN" 0644 root:root

if ! grep -Eq '^[[:space:]]*Include[[:space:]]+/etc/ssh/sshd_config\.d/\*\.conf' /etc/ssh/sshd_config; then
    die "Debian SSH drop-in Include is missing from /etc/ssh/sshd_config. Refusing to rewrite the main file automatically."
fi

sshd -t || die "sshd configuration validation failed."
EFFECTIVE="$(sshd -T 2>/dev/null)"
printf '%s\n' "$EFFECTIVE" | grep -qx 'port 22' || die "Effective SSH port is not 22. An earlier config value is overriding the managed drop-in."
printf '%s\n' "$EFFECTIVE" | grep -qx 'pubkeyauthentication yes' || die "Effective PubkeyAuthentication is not yes."

USER_EFFECTIVE="$(sshd -T -C user=ssh-user,host=localhost,addr=127.0.0.1 2>/dev/null || true)"
printf '%s\n' "$USER_EFFECTIVE" | grep -qx 'passwordauthentication no' || warn "Could not confirm PasswordAuthentication=no for ssh-user."
if printf '%s\n' "$USER_EFFECTIVE" | grep -q '^denyusers '; then
    printf '%s\n' "$USER_EFFECTIVE" | grep '^denyusers ' | grep -qw ssh-user && die "ssh-user is denied by DenyUsers. Review SSH access rules."
fi
if printf '%s\n' "$USER_EFFECTIVE" | grep -q '^allowusers '; then
    printf '%s\n' "$USER_EFFECTIVE" | grep '^allowusers ' | grep -qw ssh-user || die "AllowUsers exists but does not include ssh-user. Review SSH access rules."
fi

systemctl enable ssh >/dev/null 2>&1 || true
restart_checked ssh || die "SSH failed to restart. Check: journalctl -xeu ssh"
ss -lntH | awk '{print $4}' | grep -Eq '(^|:)22$' || die "sshd is not listening on TCP/22."
log "SSH scoring account/key and TCP/22 are locally prepared."
