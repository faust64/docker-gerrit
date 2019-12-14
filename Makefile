FRONTNAME = demo
ROOT_DOMAIN = example.com

.PHONY: genkey
genkey:
	@@if ! test -s ./ssh-keys/id_rsa.pub; then \
	    ( \
		mkdir -p ./ssh-keys; \
		cd ./ssh-keys; \
		ssh-keygen -t rsa -b 4096 -N '' -f id_rsa; \
	    ) \
	fi

.PHONY: ockey
ockey: genkey occheck
	@@if ! oc describe secret gerrit-ssh-$(FRONTNAME) >/dev/null 2>&1; then \
	    oc create secret generic gerrit-ssh-$(FRONTNAME) \
		--from-file=public-key=./ssh-keys/id_rsa.pub \
		--from-file=private-key=./ssh-keys/id_rsa; \
	fi

.PHONY: build
build:
	@@./hack/build.sh

.PHONY: ocbuild
ocbuild: occheck
	@@if ! oc describe is gerrit-$(FRONTNAME) >/dev/null 2>&1; then \
	    oc process -f openshift/imagestream.yaml -p FRONTNAME=$(FRONTNAME) \
		| oc apply -f-; \
	fi
	@@if test "$$GIT_TOKEN"; then \
	    oc process -f openshift/build-with-secret.yaml \
		-p "GIT_DEPLOYMENT_TOKEN=$$GIT_TOKEN" -p FRONTNAME=$(FRONTNAME) \
		| oc apply -f-; \
	else \
	    oc process -f openshift/build.yaml -p FRONTNAME=$(FRONTNAME) \
		| oc apply -f-; \
	fi

.PHONY: occheck
occheck:
	@@oc whoami >/dev/null 2>&1 || exit 42

.PHONY: occlean
occlean: occheck
	@@oc process -f openshift/run-persistent.yaml -p FRONTNAME=$(FRONTNAME) | oc delete -f- || true
	@@oc process -f openshift/run-master.yaml -p FRONTNAME=$(FRONTNAME) | oc delete -f- || true
	@@oc process -f openshift/run-slave-persistent.yaml -p FRONTNAME=$(FRONTNAME) | oc delete -f- || true
	@@oc process -f openshift/secret.yaml -p FRONTNAME=$(FRONTNAME) | oc delete -f- || true

.PHONY: ocdemoephemeral
ocdemoephemeral: occheck
	@@if ! oc describe secret gerrit-$(FRONTNAME) >/dev/null 2>&1; then \
	    oc process -f openshift/secret.yaml -p FRONTNAME=$(FRONTNAME) \
		| oc apply -f-; \
	fi
	@@oc process -f openshift/run-ephemeral.yaml -p FRONTNAME=$(FRONTNAME) \
	    -p ROOT_DOMAIN=$(ROOT_DOMAIN) \
	    -p GERRIT_IMAGE_FRONTNAME=$(FRONTNAME) | oc apply -f-

.PHONY: ocdemopersistent
ocdemopersistent: occheck
	@@if ! oc describe secret gerrit-$(FRONTNAME) >/dev/null 2>&1; then \
	    oc process -f openshift/secret.yaml -p FRONTNAME=$(FRONTNAME) \
		| oc apply -f-; \
	fi
	@@oc process -f openshift/run-persistent.yaml -p FRONTNAME=$(FRONTNAME) \
	    -p ROOT_DOMAIN=$(ROOT_DOMAIN) \
	    -p GERRIT_IMAGE_FRONTNAME=$(FRONTNAME) | oc apply -f-

.PHONY: ocdemo
ocdemo: ocdemoephemeral

.PHONY: ocpurge
ocpurge: occlean
	@@oc process -f openshift/build.yaml -p FRONTNAME=$(FRONTNAME) | oc delete -f- || true
	@@oc process -f openshift/imagestream.yaml -p FRONTNAME=$(FRONTNAME) | oc delete -f- || true
	@@oc delete -f gerrit-ssh-$(FRONTNAME) || true

.PHONY: ocldap
ocldap: occheck ockey
	oc process -f openshift/run-persistent-with-cm.yaml \
	    -p FRONTNAME=$(FRONTNAME) \
	    -p GERRIT_IMAGE_FRONTNAME=$(FRONTNAME) \
	    -p BASE_SUFFIX=dc=demo,dc=local \
	    -p LDAP_PASSWORD=secret \
	    -p LDAP_URI=ldaps://ldap.demo.local \
	    -p LDAP_USER=cn=gerrit,ou=services,dc=demo,dc=lan \
	    -p ROOT_DOMAIN=$(ROOT_DOMAIN) \
	    -p SMTP_RELAY=smtp.demo.local | oc apply -f-

.PHONY: ocmaster
ocmaster: occheck ockey
	@@if ! oc describe secret gerrit-$(FRONTNAME) >/dev/null 2>&1; then \
	    oc process -f openshift/secret.yaml -p FRONTNAME=$(FRONTNAME) \
		| oc apply -f-; \
	fi
	@@oc process -f openshift/run-master.yaml -p FRONTNAME=$(FRONTNAME) \
	    -p ROOT_DOMAIN=$(ROOT_DOMAIN) \
	    -p GERRIT_IMAGE_FRONTNAME=$(FRONTNAME) | oc apply -f-

.PHONY: ocslavepersistent
ocslavepersistent: occheck ockey
	@@if ! oc describe secret gerrit-$(FRONTNAME) >/dev/null 2>&1; then \
	    oc process -f openshift/secret.yaml -p FRONTNAME=$(FRONTNAME) \
		| oc apply -f-; \
	fi
	@@oc process -f openshift/run-slave-persistent.yaml -p FRONTNAME=$(FRONTNAME) \
	    -p ROOT_DOMAIN=$(ROOT_DOMAIN) \
	    -p GERRIT_IMAGE_FRONTNAME=$(FRONTNAME) \
	    -p GERRIT_SSHD_IMAGE_FRONTNAME=$(FRONTNAME) | oc apply -f-

.PHONY: ocslaveephemeral
ocslaveephemeral: occheck ockey
	@@if ! oc describe secret gerrit-$(FRONTNAME) >/dev/null 2>&1; then \
	    oc process -f openshift/secret.yaml -p FRONTNAME=$(FRONTNAME) \
		| oc apply -f-; \
	fi
	@@oc process -f openshift/run-slave-ephemeral.yaml -p FRONTNAME=$(FRONTNAME) \
	    -p ROOT_DOMAIN=$(ROOT_DOMAIN) \
	    -p GERRIT_IMAGE_FRONTNAME=$(FRONTNAME) \
	    -p GERRIT_SSHD_IMAGE_FRONTNAME=$(FRONTNAME) | oc apply -f-

.PHONY: ocslave
ocslave: ocslavepersistent
