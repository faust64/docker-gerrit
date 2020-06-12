#!/bin/sh

if test "$DEBUG"; then
    set -x
fi

DB_DRIVER=${DB_DRIVER:-h2}
FORCE_REINDEX="${FORCE_REINDEX:-}"
GERRIT_AUTH_METHOD=${GERRIT_AUTH_METHOD:-DEVELOPMENT_BECOME_ANY_ACCOUNT}
GERRIT_BEHIND_PROXY=${GERRIT_BEHIND_PROXY:-}
GERRIT_MASTER=${GERRIT_MASTER:-}
GERRIT_HOSTNAME=${GERRIT_HOSTNAME:-gerrit.demo.local}
GERRIT_PACKED_GIT_LIMIT=${GERRIT_PACKED_GIT_LIMIT:-500m}
GERRIT_PUBLIC_PROTO=${GERRIT_PUBLIC_PROTO:-http}
GERRIT_STRICT_HOSTKEY_CHECKING=${GERRIT_STRICT_HOSTKEY_CHECKING:-true}
GIT_USERNAME=${GIT_USERNAME:-gitusr}
HTTP_LISTEN_PORT=${HTTP_LISTEN_PORT:-8080}
LDAP_ACCOUNT_SCOPE=${LDAP_ACCOUNT_SCOPE:-one}
LDAP_BASE="${LDAP_BASE:-dc=demo,dc=local}"
LDAP_BIND_DN_PREFIX="${LDAP_BIND_DN_PREFIX:-cn=gerrit,ou=services}"
LDAP_BIND_PASSWORD="${LDAP_BIND_PASSWORD:-secret}"
LDAP_DN_ATTR=${LDAP_DN_ATTR:-displayName}
LDAP_EMAIL_ATTR=${LDAP_EMAIL_ATTR:-mail}
LDAP_HOST=${LDAP_HOST:-openldap}
LDAP_PROTO=${LDAP_PROTO:-ldap}
LDAP_SSL_VERIFY=${LDAP_SSL_VERIFY:-true}
LDAP_START_TLS=${LDAP_START_TLS:-false}
MYSQL_DATABASE=${MYSQL_DATABASE:-gerrit}
MYSQL_HOST=${MYSQL_HOST:-mysql}
MYSQL_PASSWORD="${MYSQL_PASSWORD:-secret}"
MYSQL_USER=${MYSQL_USER:-mysql}
POSTGRES_DATABASE=${MYSQL_DATABASE:-gerrit}
POSTGRES_HOST=${MYSQL_HOST:-postgres}
POSTGRES_PASSWORD="${MYSQL_PASSWORD:-secret}"
POSTGRES_USER=${MYSQL_USER:-postgres}
SMTP_DOMAIN=${SMTP_DOMAIN:-demo.local}
SMTP_HOST=${SMTP_HOST:-smtp.demo.local}
SSH_LISTEN_PORT=${SSH_LISTEN_PORT:-29418}
SSH_IDLE_TIMEOUT="${SSH_IDLE_TIMEOUT:-240m}"
SSH_THREADS="${SSH_THREADS:-8}"
SSH_MAX_CON_PER_USER="${SSH_MAX_CON_PER_USER:-0}"
SSHD_LISTEN_PORT=${SSHD_LISTEN_PORT:-2222}

HOSTNAME=`hostname -s`
if test "`id -u`" -ne 0; then
    echo Setting up nswrapper mapping `id -u` to gerrit
    pwentry="gerrit:x:`id -u`:`id -g`:gerrit:/var/gerrit:/usr/sbin/nologin"
    sed "s|^gerrit:.*|$pwentry|" /etc/passwd >/tmp/gerrit-passwd
    export NSS_WRAPPER_PASSWD=/tmp/gerrit-passwd
    export NSS_WRAPPER_GROUP=/etc/group
    export LD_PRELOAD=/usr/lib/libnss_wrapper.so
fi
if test -z "$LDAP_PORT"; then
    if test "$LDAP_PROTO" = ldaps; then
	LDAP_PORT=636
    else
	LDAP_PORT=389
    fi
fi
if test -z "$ALLOWED_DOWNLOAD_SCHEMES"; then
    ALLOWED_DOWNLOAD_SCHEMES="ssh http anon_http anon_git repo_download"
fi
if test -z "$GERRIT_SERVER_ID"; then
    GERRIT_SERVER_ID=cef467b6-2cbc-42d4-b21e-e4c29d1df424
fi
if test -z "$LDAP_GROUPS_BASE"; then
    LDAP_GROUPS_BASE="ou=groups,$LDAP_BASE"
fi
if test -z "$LDAP_GROUPS_FILTER"; then
    LDAP_GROUPS_FILTER='(&(objectClass=groupOfNames)(member=\${dn}))'
fi
if test -z "$LDAP_USERS_BASE"; then
    LDAP_USERS_BASE="ou=users,$LDAP_BASE"
fi
if test -z "$LDAP_USERS_FILTER"; then
    LDAP_USERS_FILTER='(&(objectClass=inetOrgPerson)(uid=\${username})(!pwdAccountLockedTime=*))'
fi

gerrit_refresh_config()
{
    if test "$GERRIT_BEHIND_PROXY"; then
	LISTEN_PROTO=proxy-$GERRIT_PUBLIC_PROTO
    else
	LISTEN_PROTO=http
    fi
    cat <<EOF >/var/gerrit/etc/gerrit.config
[gerrit]
	basePath = git
	serverId = $GERRIT_SERVER_ID
	canonicalWebUrl = $GERRIT_PUBLIC_PROTO://$GERRIT_HOSTNAME/
[core]
	packedGitLimit = $GERRIT_PACKED_GIT_LIMIT
[index]
	type = LUCENE
[sendemail]
	enable = true
	smtpServer = $SMTP_HOST
	sslVerify = false
[sshd]
	advertisedAddress = $GERRIT_HOSTNAME:$SSH_LISTEN_PORT
	listenAddress = *:$SSH_LISTEN_PORT
	threads = $SSH_THREADS
	idleTimeout = $SSH_IDLE_TIMEOUT
	maxConnectionsPerUser = $SSH_MAX_CON_PER_USER
[httpd]
	listenUrl = $LISTEN_PROTO://*:$HTTP_LISTEN_PORT
[cache]
	directory = /var/gerrit/cache
[cache "web_sessions"]
	maxAge = 5d
[cache "ldap_groups"]
	maxAge = 60
[cache "accounts"]
	maxAge = 60
[cache "groups"]
	maxAge = 60
[cache "groups_byinclude"]
	maxAge = 60
[cache "groups_members"]
	maxAge = 60
[noteDB "changes"]
	automigrate = true
[plugins]
	allowRemoteAdmin = true
[container]
	javaHome = /usr/lib/jvm/java-11-openjdk-amd64
	javaOptions = "-Dflogger.backend_factory=com.google.common.flogger.backend.log4j.Log4jBackendFactory#getInstance"
	javaOptions = "-Dflogger.logging_context=com.google.gerrit.server.logging.LoggingContext#getInstance"
	javaOptions = -Djava.security.egd=file:/dev/urandom
	startupTimeout = 180
	user = gerrit
EOF
    if test "$GERRIT_HEAP_LIMIT"; then
	cat <<EOF >>/var/gerrit/etc/gerrit.config
	heapLimit = $GERRIT_HEAP_LIMIT
EOF
    fi
    if test "$GERRIT_IS_SLAVE"; then
	cat <<EOF >>/var/gerrit/etc/gerrit.config
	slave = true
	daemonOpt = --enable-httpd
EOF
    fi
    cat <<EOF >>/var/gerrit/etc/gerrit.config
[receive]
	enableSignedPush = false
[auth]
	type = $GERRIT_AUTH_METHOD
[gitweb]
	cgi = /usr/lib/cgi-bin/gitweb.cgi
[download]
EOF
    for scheme in $ALLOWED_DOWNLOAD_SCHEMES
    do
	echo "	scheme = $scheme"
    done >>/var/gerrit/etc/gerrit.config
    if test "$GERRIT_AUTH_METHOD" = LDAP; then
	cat <<EOF >>/var/gerrit/etc/gerrit.config
[ldap]
	accountBase = $LDAP_USERS_BASE
	accountEmailAddress = $LDAP_EMAIL_ATTR
	accountFullName = $LDAP_DN_ATTR
	accountPattern = $LDAP_USERS_FILTER
	accountScope = $LDAP_ACCOUNT_SCOPE
	groupBase = $LDAP_GROUPS_BASE
	groupMemberPattern = $LDAP_GROUPS_FILTER
	password = $LDAP_BIND_PASSWORD
	server = $LDAP_PROTO://$LDAP_HOST:$LDAP_PORT
	sslVerify = $LDAP_SSL_VERIFY
	startTls = $LDAP_START_TLS
	username = $LDAP_BIND_DN_PREFIX,$LDAP_BASE
EOF
    fi
    if test "$DB_DRIVER" = mysql; then
	cat <<EOF
[accountPatchReviewDb]
	url = jdbc:mysql://$MYSQL_HOST:3306/$MYSQL_DATABASE?user=$MYSQL_USER&password=$MYSQL_PASSWORD
EOF
    elif test "$DB_DRIVER" = postgres -o "$DB_DRIVER" = postgresql; then
	cat <<EOF
[accountPatchReviewDb]
	url = jdbc:postgresql://$POSTGRES_HOST:5432/$POSTGRES_DATABASE?user=$POSTGRES_USER&password=$POSTGRES_PASSWORD
EOF
    fi >>/var/gerrit/etc/gerrit.config
}

if test "$DB_DRIVER" = mysql; then
    echo -n "Waiting for database to become available: "
    cpt=0
    while :
    do
	if timeout 3 nc -z $MYSQL_HOST 3306 >/dev/null 2>&1; then
	    echo OK
	    break
	elif test $cpt -gt 20; then
	    echo timeout exceeded >&2
	    exit 1
	fi
	cpt=`expr $cpt + 1`
	echo -n .
	sleep 2
    done
elif test "$DB_DRIVER" = postgres -o "$DB_DRIVER" = postgresql; then
    echo -n "Waiting for database to become available: "
    cpt=0
    while :
    do
	if timeout 3 nc -z $POSTGRES_HOST 5432 >/dev/null 2>&1; then
	    break
	elif test $cpt -gt 20; then
	    echo OK
	    echo timeout exceeded >&2
	    exit 1
	fi
	cpt=`expr $cpt + 1`
	echo -n .
	sleep 2
    done
fi
if test "$GERRIT_AUTH_METHOD" = LDAP; then
    echo -n "Waiting for ldap to become available: "
    cpt=0
    while :
    do
	if timeout 3 nc -z $LDAP_HOST $LDAP_PORT >/dev/null 2>&1; then
	    break
	elif test $cpt -gt 20; then
	    echo OK
	    echo timeout exceeded >&2
	    exit 1
	fi
	cpt=`expr $cpt + 1`
	echo -n .
	sleep 2
    done
fi
if test -s /.ssh/id_rsa.pub -a -s /.ssh/id_rsa; then
    mkdir -p /var/gerrit/.ssh /var/gerrit/ssh-keys
    cat /.ssh/id_rsa >/var/gerrit/ssh-keys/id-admin-rsa
    cat /.ssh/id_rsa.pub >/var/gerrit/ssh-keys/id-admin-rsa.pub
    cat /.ssh/id_rsa.pub >/var/gerrit/.ssh/authorized_keys
    chmod 0600 /var/gerrit/ssh-keys/id-admin-rsa* \
	/var/gerrit/.ssh/authorized_keys
    cat /.ssh/id_rsa >/var/gerrit/.ssh/id_rsa
    cat /.ssh/id_rsa.pub >/var/gerrit/.ssh/id_rsa.pub
    chmod 0600 /var/gerrit/.ssh/id_rsa
    if test -z "$GERRIT_IS_SLAVE"; then
	IS_MASTER=true
	echo INFO: Gerrit is master
    else
	IS_MASTER=false
	echo INFO: Gerrit is slave
    fi
    chmod 0700 /var/gerrit/.ssh /var/gerrit/ssh-keys
    for f in config known_hosts authorized_keys;
    do
	if test -s /.ssh/$f; then
	    cat /.ssh/$f >/var/gerrit/.ssh/$f
	    chmod 0600 /var/gerrit/.ssh/$f
	fi
    done
else
    IS_MASTER=false
    echo INFO: Gerrit is standalone
fi
if ! test -s /var/gerrit/etc/gerrit-initialized; then
    echo INFO: Initializing Gerrit configuration and plugins directories
    for d in etc lib plugins
    do
	if ! cp -vfrp /var/gerrit/$d.orig/* /var/gerrit/$d/; then
	    echo Failed initializing gerrit ./$d >&2
	fi
    done
    if test -s /config/gerrit.config; then
	ln -sf /config/gerrit.config /var/gerrit/etc/
    else
	gerrit_refresh_config
    fi
    for f in replication gitiles security
    do
	if test -s /config/$f.config; then
	    ln -sf /config/$f.config /var/gerrit/etc/
	fi
    done
    if test -s /var/gerrit/.ssh/id_rsa -a "$GERRIT_MASTER"; then
	isdone=false
	for cpt in 1 2 3
	do
	    if ssh admin@$GERRIT_MASTER -i /var/gerrit/.ssh/id_rsa \
		-o StrictHostKeyChecking=no -p $SSH_LISTEN_PORT \
		gerrit plugin reload replication; then
		echo done reloading replication plugin on gerrit master
		isdone=true
		break
	    fi
	done
	if $isdone; then
	    isdone=false
	    for cpt in 1 2 3
	    do
		if ssh admin@$GERRIT_MASTER -i /var/gerrit/.ssh/id_rsa \
		    -o StrictHostKeyChecking=no -p $SSH_LISTEN_PORT \
		    replication start --url $HOSTNAME --wait --all --now; then
		    isdone=true
		    echo done syncing from gerrit master
		    break
		fi
	    done
	fi
    elif ! $IS_MASTER; then
	echo '"dumb" init'
	for d in All-Users All-Projects
	do
	    if ! test -d /var/gerrit/git/$d.git; then
		mkdir -p /var/gerrit/git/$d.git
		( cd /var/gerrit/git/$d.git ; git init )
		( cd /var/gerrit/git ; ln -sf $d.git $d )
	    fi
	done
    fi
    if ! java -jar /var/gerrit/bin/gerrit.war init --batch \
	--install-plugin replication --no-auto-start -d /var/gerrit; then
	echo Failed initializing gerrit >&2
    fi
    if ! java -jar /var/gerrit/bin/gerrit.war reindex -d /var/gerrit; then
	echo Failed re-indexing >&2
    fi
    date >/var/gerrit/etc/gerrit-initialized
else
    NOW=`date +%s`
    if test -s /config/gerrit.config; then
	ln -sf /config/gerrit.config /var/gerrit/etc/
    else
	if test -s /var/gerrit/etc/gerrit.config; then
	    echo INFO: backing up gerrit configuration "(gerrit.config.$NOW)"
	    cp -p /var/gerrit/etc/gerrit.config \
		/var/gerrit/etc/gerrit.config.$NOW
	fi
	echo INFO: refreshing gerrit configuration
	gerrit_refresh_config
	if test -s /var/gerrit/etc/gerrit.config.$NOW; then
	    if cmp /var/gerrit/etc/gerrit.config.$NOW /var/gerrit/etc/gerrit.config; then
		echo INFO: previous gerrit configuration matches latest copy
		echo INFO: dropping backup
		rm -f /var/gerrit/etc/gerrit.config.$NOW
	    fi
	fi
    fi
    for f in replication gitiles security
    do
	if test -s /config/$f.config; then
	    ln -sf /config/$f.config /var/gerrit/etc/
	fi
    done
fi

ssh_config_host()
{
    local remote port haskey

    haskey=false
    port=$2
    remote=$1
    if test -z "$remote" -o -z "$port"; then
	return 0
    fi
    cat <<EOF >>/var/gerrit/.ssh/config
Host $remote
    IdentityFile /var/gerrit/.ssh/id_rsa
    PreferredAuthentications publickey
    Port $port
    User admin
EOF
    if echo "$GERRIT_STRICT_HOSTKEY_CHECKING" \
	| grep -iE '(true|yes|yay|yep|oui|^1$)' >/dev/null; then
	if ssh-keygen -f $HOME/.ssh/known_hosts -F $remote >/dev/null 2>&1; then
	    echo INFO: $remote already trusted
	    continue
	fi
	cpt=0
	while :
	do
	    if ssh-keyscan -H -t ecdsa,rsa -p $port -T 10 $remote \
		| grep -vE '^(#|no hostkey alg)' >>$HOME/.ssh/known_hosts \
		2>/dev/null; then
		haskey=true
		echo INFO: added $remote to ssh known hosts
		break
	    fi
	    cpt=`expr $cpt + 1`
	    if test $cpt -lt 4; then
		echo Trying again in 3 seconds
		sleep 3
	    else
		echo Failed adding $remote to ssh known hosts >&2
		break
	    fi
	done
    fi
    if ! $haskey; then
	cat <<EOF >>/var/gerrit/.ssh/config
    StrictHostKeyChecking no
    UserKnownHostsFile /dev/null
EOF
    fi
}

for idx in $FORCE_REINDEX
do
    java -jar /var/gerrit/bin/gerrit.war reindex --index $idx || true
done
if test -s /var/gerrit/etc/replication.config; then
    if test "$SSHD_LISTEN_PORT" -ne "$SSH_LISTEN_PORT"; then
	awk '/^[ \t]*url = admin@/{print $3}' \
	    /var/gerrit/etc/replication.config \
	    | sed 's|^admin@\([^/:]*\).*$|\1|' | while read remote
		do
		    ssh_config_host $remote $SSHD_LISTEN_PORT
		done
    fi
    awk '/^[ \t]*adminUrl = gerrit\+ssh/{print $3}' \
	/var/gerrit/etc/replication.config \
	| sed 's|^gerrit+ssh://\([^/:]*\).*$|\1|' | while read remote
	    do
		ssh_config_host $remote $SSH_LISTEN_PORT
	    done
fi
if ! test -s /var/gerrit/.gitconfig; then
    cat <<EOF >/var/gerrit/.gitconfig
[user]
	email = $GIT_USERNAME@$SMTP_DOMAIN
	name = $GIT_USERNAME
[core]
    packedGitLimit = $GERRIT_PACKED_GIT_LIMIT
EOF
    for review in $GERRIT_REVIEW_HOSTS
    do
	cat <<EOF
[review "$review"]
    username = $GIT_USERNAME
EOF
    done >>/var/gerrit/.gitconfig
fi

for log in delete gc httpd replication sshd
do
    rm -f /var/gerrit/logs/${log}_log
    ln -sf /dev/stdout /var/gerrit/logs/${log}_log
done

if test "$DEBUG"; then
    cat /var/gerrit/etc/gerrit.config
fi
unset cpt MYSQL_HOST MYSQL_USER MYSQL_PASSWORD MYSQL_DATABASE pwentry NOW \
    SSH_LISTEN_PORT HTTP_LISTEN_PORT SMTP_HOST GERRIT_PUBLIC_PROTO LDAP_PORT \
    GERRIT_HOSTNAME POSTGRES_HOST POSTGRES_USER POSTGRES_PASSWORD LDAP_BASE \
    POSTGRES_DATABASE LDAP_HOST LDAP_PROTO LDAP_ACCOUNT_SCOPE haskey \
    LDAP_BIND_DN_PREFIX LDAP_BIND_PASSWORD LDAP_DN_ATTR LDAP_USERS_FILTER \
    LDAP_EMAIL_ATTR LDAP_GROUPS_BASE LDAP_GROUPS_FILTER LDAP_USERS_BASE \
    LDAP_START_TLS LDAP_SSL_VERIFY GERRIT_IS_SLAVE FORCE_REINDEX
exec /var/gerrit/bin/gerrit.sh run
