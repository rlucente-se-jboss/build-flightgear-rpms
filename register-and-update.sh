#!/usr/bin/env bash

. $(dirname $0)/demo.conf

[[ $EUID -ne 0 ]] && exit_on_error "Must run as root"

subscription-manager register \
    --username $SCA_USER --password $SCA_PASS || exit 1
subscription-manager syspurpose role --set="RHEL Workstation"
subscription-manager syspurpose service-level --set="Self-Support"
subscription-manager syspurpose usage --set="Development/Test"

# some packages in EPEL require packages in the codeready-builder repo
# so enable that repo so it's available to the later container multi-stage
# build
subscription-manager repos --enable codeready-builder-beta-for-rhel-10-x86_64-rpms

dnf -y update
dnf -y clean all
