# Gerrit

## Build Locally

```
make build
```

## Build on OpenShift

```
make ocbuild
```

## Deploy Standalone Demo

```
make ocdemopersistent
```

Or ephemeral demo, that won't allow for container restarts:

```
make ocdemo
```

## Deploy LDAP-Based Standalone

```
make ocldap
```

## Deploy Master/Slave

Deploy the master components with:

```
make ocmaster
```

Eventually, deploy slaves:

```
make ocslave
```

And configure replication from the master Pod, and restart it:

```
oc rsh dc/gerrit-master-demo
cat <<EOF >>etc/replication.config
[remote "slave-demo"]
    url = admin@gerrit-slave-sshd-demo:/var/gerrit/git/\${name}.git
    push = +refs/*:refs/*
    timeout = 30
    replicationDelay = 1
    threads = 4
    replicateHiddenProjects = true
    replicateProjectDeletion = true
    mirror = true
EOF
exit
oc delete pod gerrit-master-demo-x-abcd
```

Then, on all slaves, make sure the initial /var/gerrit/git content was synced,
as SSH connections to Gerrit management interface would not work otherwise.

## OpenShift Considerations

Forcing clients to connect Gerrit using TLS, we would want to define an https://
prefixed URL in gerrit.config. Doing so, while setting up a listenUrl binding
on http, Jetty would expect for some X-Forwarded-Scheme header to be set, which
is not added by OpenShift routers.

Use the following, to patch OpenShift routers template, inserting those missing
headers:

```
make ocrouterprep
```

## Notes

Create a repository:

```
$ ssh localhost gerrit ls-groups
Warning: Permanently added '[localhost]:29418' (ECDSA) to the list of known hosts.
Administrators
Non-Interactive Users
$ ssh localhost gerrit create-project --require-change-id --owner=Administrators --description='"My Awesome Project"' global/awesome
```

Dealing with replication:

https://gerrit.googlesource.com/plugins/replication/+/refs/heads/master/src/main/resources/Documentation/config.md

```
$ ssh localhost gerrit plugin reload replication
$ ssh localhost replication start --all
$ ssh localhost replication start global/awesome
$ ssh localhost gerrit logging ls-level | grep replication
com.googlesource.gerrit.plugins.replication.AutoReloadConfigDecorator: DEBUG
com.googlesource.gerrit.plugins.replication.EventsStorage: DEBUG
com.googlesource.gerrit.plugins.replication.PushResultProcessing.GitUpdateProcessing: INFO
com.googlesource.gerrit.plugins.replication.ReplicationFileBasedConfig: DEBUG
replication_log: DEBUG
$ ssh localhost gerrit logging set-level DEBUG com.googlesource.gerrit.plugins.replication.PushResultProcessing.GitUpdateProcessing
$ ssh localhost replication start --wait --all --now
Replicate All-Projects ref ..all.. to gerrit-slave-sshd-demo, Succeeded! (OK)
Replication of All-Projects ref ..all.. completed to 1 nodes,
Replicate All-Users ref ..all.. to gerrit-slave-sshd-demo, Succeeded! (OK)
Replication of All-Users ref ..all.. completed to 1 nodes,
Replicate global/awesome ref ..all.. to gerrit-slave-sshd-demo, Succeeded! (OK)
Replication of global/awesome ref ..all.. completed to 1 nodes,
----------------------------------------------
Replication completed successfully!
```

Misc:

```
$ ssh localhost gerrit show-connections
$ ssh localhost gerrit show-caches
$ ssh localhost gerrit plugin ls
$ ssh localhost gerrit show-queue
$ ssh localhost ps
```

Gitweb?  see https://www.gerritcodereview.com/config-gitweb.html

Deaing with replication WITH ldap auth:

either create a dedicated LDAP user -- or use whoever first logged in, as it whould be gerrit admin already, quick/dirty/demo
Upload admin public key into corresponding gerrit account settings
Then, use that account connecting to gerrit ssh server:

```
$ . /prep-cli.sh
$ ssh faust@localhost gerrit plugin reload replication
$ ssh faust@localhost replication start --url gerrit-slave-demo-0 --all --now --wait
Warning: Permanently added '[localhost]:29418' (ECDSA) to the list of known hosts.
Replicate All-Projects ref ..all.. to gerrit-slave-demo-0.gerrit-slave-demo, Succeeded! (OK)
Replication of All-Projects ref ..all.. completed to 1 nodes,
Replicate All-Users ref ..all.. to gerrit-slave-demo-0.gerrit-slave-demo, Succeeded! (OK)
Replication of All-Users ref ..all.. completed to 1 nodes,
----------------------------------------------
Replication completed successfully!
$ ssh faust@localhost replication start --url gerrit-slave-demo-1 --all --now --wait
...
```

Syncing groups from LDAP: unclear, seems that when I create a group that exists in my LDAP, it
finally shows up in Gerrit groups listing. Meanwhile, gerrit doesn't seem to be scanning for
groups during login or otherwise

Working with bare repsitories: assuming I want to checkout sources out of a
folder in Gerrit, yet can not clone said repository:

```
$ mkdir /usr/src/<repository>
$ cp -rp /var/gerrit/git/<project-path>/<repository> /usr/src/<repository>/.git
$ cd /usr/src/<repository>
$ GIT_WORK_TREE=./ git checkout --
$ ls
...
```

Environment variables and volumes
----------------------------------

The image recognizes the following environment variables that you can set during
initialization by passing `-e VAR=VALUE` to the Docker `run` command.

|    Variable name                      |    Description                                | Default                                     |
| :------------------------------------ | --------------------------------------------- | ------------------------------------------- |
|  `ALLOWED_DOWNLOAD_SCHEMES`           | Gerrit Allowed Download Schemes               | `ssh http anon_http anon_git repo_download` |
|  `DB_DRIVER`                          | Gerrit Database Driver                        | `h2`                                        |
|  `FORCE_REINDEX`                      | Force Gerrit Reindex on boot                  | undef                                       |
|  `GERRIT_AUTH_METHOD`                 | Gerrit Authentication Method                  | `DEVELOPMENT_BECOME_ANY_ACCOUNT`            |
|  `GERRIT_BEHIND_PROXY`                | Gerrit is Behind an HTTP Proxy                | undef                                       |
|  `GERRIT_MASTER`                      | OpenLDAP CodiMD Password                      | `secret`                                    |
|  `GERRIT_HOSTNAME`                    | Gerrit Service Hostname                       | `gerrit.demo.local`                         |
|  `GERRIT_PACKED_GIT_LIMIT`            | Packed Git Size Limit                         | `500m`                                      |
|  `GERRIT_PUBLIC_PROTO`                | Gerrit Public Web Proto                       | `http`                                      |
|  `GERRIT_STRICT_HOSTKEY_CHECKING`     | Gerrit SSH Hostkey Strict Checking            | `true`                                      |
|  `GIT_USERNAME`                       | Git Default Username                          | `gitusr`                                    |
|  `HTTP_LISTEN_PORT`                   | Gerrit JVM HTTP Listen Port                   | `8080`                                      |
|  `LDAP_ACCOUNT_SCOPE`                 | LDAP Account Search Scope                     | `one`                                       |
|  `LDAP_BASE`                          | LDAP Search Base                              | `dc=demo,dc=local`                          |
|  `LDAP_BIND_DN_PREFIX`                | Gerrit LDAP Bind DN Prefix                    | `cn=gerrit,ou=services`                     |
|  `LDAP_BIND_PASSWORD`                 | Gerrit LDAP Bind Password                     | `secret`                                    |
|  `LDAP_DN_ATTR`                       | LDAP DisplayName Attribute                    | `displayName`                               |
|  `LDAP_EMAIL_ATTR`                    | LDAP Email Attribute                          | `mail`                                      |
|  `LDAP_HOST`                          | LDAP Host Address                             | `openldap`                                  |
|  `LDAP_PROTO`                         | LDAP Proto                                    | `ldap`                                      |
|  `LDAP_SSL_VERIFY`                    | LDAP SSL Verify                               | `true`                                      |
|  `LDAP_START_TLS`                     | LDAP Start TLS                                | `false`                                     |
|  `MYSQL_DATABASE`                     | Gerrit MySQL Database Name                    | `gerrit`                                    |
|  `MYSQL_HOST`                         | Gerrit MySQL Host Address                     | `mysql`                                     |
|  `MYSQL_PASSWORD`                     | Gerrit MySQL Database Password                | `secret`                                    |
|  `MYSQL_USER`                         | Gerrit MySQL Database Username                | `mysql`                                     |
|  `POSTGRES_DATABASE`                  | Gerrit Postgres Database Name                 | `gerrit`                                    |
|  `POSTGRES_HOST`                      | Gerrit Postgres Host Address                  | `postgres`                                  |
|  `POSTGRES_PASSWORD`                  | Gerrit Postgres Database Password             | `secret`                                    |
|  `POSTGRES_USER`                      | Gerrit Postgres Database Username             | `postgres`                                  |
|  `SMTP_DOMAIN`                        | Gerrit Mail Domain                            | `demo.local`                                |
|  `SMTP_HOST`                          | Gerrit SMTP Relay                             | `smtp.demo.local`                           |
|  `SSH_LISTEN_PORT`                    | Gerrit SSHD Server Listen Port                | `29418`                                     |
|  `SSH_IDLE_TIMEOUT`                   | Gerrit SSHD Server IDLE Timeout               | `240m`                                      |
|  `SSH_THREADS`                        | Gerrit SSHD Server Threads                    | `8`                                         |
|  `SSH_MAX_CON_PER_USER`               | Gerrit SSHD Server Max Connections per User   | `0`                                         |
|  `SSHD_LISTEN_PORT`                   | OpenSSH Replication SSHD Server Listen Port   | `29419`                                     |

You can also set the following mount points by passing the `-v /host:/container` flag to Docker.

|  Volume mount point    | Description                                |
| :--------------------- | ------------------------------------------ |
|  `/config`             | Gerrit Configuration - prevents generation |
|  `/var/gerrit/data`    | Gerrit Data                                |
|  `/var/gerrit/cache`   | Gerrit Cache                               |
|  `/var/gerrit/db`      | Gerrit DB                                  |
|  `/var/gerrit/etc`     | Gerrit Configuration                       |
|  `/var/gerrit/git`     | Gerrit Repositories                        |
|  `/var/gerrit/index`   | Gerrit Indexes                             |
|  `/var/gerrit/lib`     | Gerrit Libraries                           |
|  `/var/gerrit/plugins` | Gerrit Plugins                             |
|  `/var/gerrit/tmp`     | Gerrit Temp Directory                      |
|  `/.ssh/`              | Gerrit SSH Keys to Install during boot     |
