# This containerfile uses both Fedora and RHEL/EPEL to build the needed
# RPMs to install FlightGear on RHEL/EPEL. The RPM tooling makes this
# process simple. Use the following commands to build this container image.
#
#     DEPENDENCIES=flightgear-dependencies
#     mkdir -p $DEPENDENCIES
#     podman build -f Containerfile -t localhost/fg-rpms \
#         -v $(pwd)/$DEPENDENCIES:/flightgear-dependencies:Z \
#         --build-arg DEPENDENCIES=$DEPENDENCIES
#
# The build-arg is optional if using the default dependencies location
# (e.g. flightgear-dependencies).

# The first stage determines the needed runtimes by installing FlightGear
# and then gathering all of the required packages for the installation.

FROM fedora:40 AS fedora-rt

# Discover all the runtime dependencies by installing FlightGear. The
# awk/grep/cut parsing of the dnf output should identify all the
# dependency simple package names. The list of dependencies here includes
# all the runtime dependencies for FlightGear on Fedora which may already
# have existing counterparts for RHEL/EPEL.

RUN    dnf -y install FlightGear | \
           awk '/^Dependencies resolved/,/^Transaction Summary/' | \
           grep '^ ' | sed 's/  */ /g' | \
           grep -v 'Package Arch Version Repo Size' | \
           cut -d' ' -f2 | sort -u > fedora-runtime.txt

## The second stage determines the unique set of fedora runtimes not
## found in the RHEL/EPEL package repositories.

## TODO Change this to UBI 10 after GA
##FROM registry.redhat.io/ubi10/ubi:latest
FROM quay.io/centos/centos:stream10 AS rhel-rt

## Discover all the unique runtime dependencies not found in RHEL/EPEL.

COPY --from=fedora-rt /fedora-runtime.txt /

ARG DEPENDENCIES=flightgear-dependencies
RUN    mkdir -p $DEPENDENCIES \
    && mv /fedora-runtime.txt $DEPENDENCIES

ARG DEPENDENCIES=flightgear-dependencies
RUN    dnf -y install util-linux \
           https://dl.fedoraproject.org/pub/epel/epel-release-latest-10.noarch.rpm \
    && /usr/bin/crb enable \
    && dnf -y clean all \
    && dnf -y install --skip-broken $(cat $DEPENDENCIES/fedora-runtime.txt) | \
           grep '^No match for argument' | rev | cut -d' ' -f1 | rev | sort -u \
           > rhel-runtime.txt

## The third stage determines the unique set of fedora packages needed to
## rebuild the runtime packages missing in RHEL/EPEL.

FROM fedora:40 as fedora-bt

COPY --from=rhel-rt /rhel-runtime.txt /

ARG DEPENDENCIES=flightgear-dependencies
RUN    mkdir -p $DEPENDENCIES \
    && mv /rhel-runtime.txt $DEPENDENCIES

ARG DEPENDENCIES=flightgear-dependencies
RUN    dnf -y install 'dnf-command(download)' \
    && dnf -y clean all \
    && dnf -y download --source --archlist x86_64,noarch \
           $(cat $DEPENDENCIES/rhel-runtime.txt) \
    && dnf -y builddep --srpm $(ls *.src.rpm) | \
           awk '/^Dependencies resolved/,/^Transaction Summary/' | \
           grep '^ ' | sed 's/  */ /g' | \
           grep -v 'Package Arch Version Repo Size' | \
           cut -d' ' -f2 | sort -u \
           > fedora-buildtime.txt

## The fourth stage determines the unique buildtime dependencies not
## found in RHEL/EPEL

FROM quay.io/centos/centos:stream10 AS rhel-bt

COPY --from=fedora-bt /fedora-buildtime.txt /

ARG DEPENDENCIES=flightgear-dependencies
RUN    mkdir -p $DEPENDENCIES \
    && mv /fedora-buildtime.txt $DEPENDENCIES

ARG DEPENDENCIES=flightgear-dependencies
RUN    dnf -y install util-linux \
           https://dl.fedoraproject.org/pub/epel/epel-release-latest-10.noarch.rpm \
    && /usr/bin/crb enable \
    && dnf -y clean all \
    && dnf -y install --skip-broken $(cat $DEPENDENCIES/fedora-buildtime.txt) | \
           grep '^No match for argument' | rev | cut -d' ' -f1 | rev | sort -u \
           > intermediate-buildtime.txt \
    && sort -u intermediate-buildtime.txt > tmp.out \
    && mv tmp.out intermediate-buildtime.txt \
    && sort -u $DEPENDENCIES/rhel-runtime.txt > tmp.out \
    && mv tmp.out $DEPENDENCIES/rhel-runtime.txt \
    && comm -23 intermediate-buildtime.txt $DEPENDENCIES/rhel-runtime.txt \
           > rhel-buildtime.txt

## The fifth stage now downloads all the SRPMs for the various buildtime
## and runtime dependencies not found in RHEL/EPEL

FROM fedora:40 as fedora-sources

COPY --from=rhel-bt /rhel-buildtime.txt /

ARG DEPENDENCIES=flightgear-dependencies
RUN    mkdir -p $DEPENDENCIES \
    && mv /rhel-buildtime.txt $DEPENDENCIES

ARG DEPENDENCIES=flightgear-dependencies
RUN    dnf -y install 'dnf-command(download)' \
    && dnf -y clean all \
    && dnf -y download --source --archlist x86_64,noarch \
           $(cat $DEPENDENCIES/rhel-runtime.txt $DEPENDENCIES/rhel-buildtime.txt)

## The final stage attempts to build all the missing buildtime and
## runtime dependencies not found in RHEL/EPEL

FROM quay.io/centos/centos:stream10

COPY --from=fedora-sources *.src.rpm /

