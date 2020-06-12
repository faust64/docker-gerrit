FROM debian:buster-slim

# Gerrit for OpenShift Origin

ENV DEBIAN_FRONTEND=noninteractive \
    GERRITVERSION=3.2.1-1

LABEL io.k8s.description="Gerrit." \
      io.k8s.display-name="Gerrit" \
      io.openshift.expose-services="8080:http,29418:ssh" \
      io.openshift.tags="gerrit,git" \
      io.openshift.non-scalable="true" \
      help="For more information visit https://github.com/faust64/docker-gerrit" \
      maintainer="Samuel MARTIN MORO <faut64@gmail.com>" \
      version="${GERRITVERSION}"

RUN set -x \
    && apt-get update \
    && mkdir -p /usr/share/man/man1 \
    && if test "$DO_UPGRADE"; then \
	apt-get -y upgrade; \
    fi \
    && apt-get -y install openjdk-11-jdk wget libnss-wrapper gnupg netcat \
	apt-transport-https ca-certificates sudo dumb-init \
    && apt-key adv --keyserver keyserver.ubuntu.com --recv-keys 847005AE619067D5 \
    && echo deb http://bionic.gerritforge.com/ gerrit contrib \
	>/etc/apt/sources.list.d/GerritForge.list \
    && apt-get update \
    && apt-get -y install gerrit=${GERRITVERSION} gitweb \
    && SUDO_FORCE_REMOVE=yes apt-get remove --purge -y gnupg \
	apt-transport-https sudo \
    && apt-get autoremove --purge -y \
    && apt-get clean \
    && mv /var/gerrit/etc/gerrit.config /var/gerrit/etc/gerrit.config.sample \
    && for d in etc lib plugins; do \
	mv /var/gerrit/$d /var/gerrit/$d.orig; \
    done \
    && for d in git index cache db etc lib logs plugins static tmp; do \
	mkdir -p /var/gerrit/$d; \
    done \
    && ( chown -R 1001:root /var/gerrit /run /run /tmp || echo nevermind ) \
    && ( chmod -R g=u /var/gerrit /run /run /tmp || echo nevermind ) \
    && rm -rf /var/gerrit/logs/* /var/lib/apt/lists/* /usr/share/doc \
	/usr/share/man

COPY config/* /
ENV HOME=/var/gerrit
WORKDIR /var/gerrit
USER 1001
ENTRYPOINT ["dumb-init","--","/run-gerrit.sh"]
