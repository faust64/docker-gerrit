SSH_LISTEN_PORT=${SSH_LISTEN_PORT:-29418}

if test "`id -u`" -ne 0; then
    export NSS_WRAPPER_PASSWD=/tmp/gerrit-passwd
    export NSS_WRAPPER_GROUP=/etc/group
    export LD_PRELOAD=/usr/lib/libnss_wrapper.so
fi
if ! grep '^Host localhost' /var/gerrit/.ssh/config >/dev/null; then
    cat <<EOF >>/var/gerrit/.ssh/config
Host localhost
    User admin
    Port $SSH_LISTEN_PORT
    IdentityFile /var/gerrit/.ssh/id_rsa
    StrictHostKeyChecking no
    UserKnownHostsFile /dev/null
EOF
fi

echo "go ahead: ssh admin@localhost gerrit plugin reload replication"
