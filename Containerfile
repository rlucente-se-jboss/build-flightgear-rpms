# This containerfile uses both Fedora and RHEL/EPEL to build the missing
# RPMs needed to install FlightGear on RHEL/EPEL. The RPM tooling makes this
# process simple, although several stages are involved. Use the following
# commands to build this container image.
#
#     DEPENDENCIES=flightgear-dependencies
#     BUILD_RPMS=flightgear-rpms
#
#     mkdir -p $DEPENDENCIES $BUILD_RPMS
#
#     podman build -f Containerfile -t localhost/fg-rpms \
#         -v $(pwd)/$DEPENDENCIES:/flightgear-dependencies:Z \
#         --build-arg DEPENDENCIES=$DEPENDENCIES \
#         --build-arg BUILD_RPMS=$BUILD_RPMS
#
# The build-arg parameters are optional if using the default path
# locations.

# *** STAGE 1 ***
#
# The first stage determines the full list of needed runtimes by
# installing FlightGear on Fedora and then gathering all of the required
# packages for the installation. This list will be whittled down by later
# stages to identify only the missing packages in RHEL/EPEL.

FROM fedora:40 AS fedora-rt

# Discover all the runtime dependencies by installing FlightGear. The
# awk/grep/cut parsing of the dnf output should identify all the
# dependency simple package names. The list of dependencies here includes
# all the runtime dependencies for FlightGear on Fedora which may already
# have existing counterparts for RHEL/EPEL.
#
# Output is sent to stdout for troubleshooting.

RUN    dnf -y install FlightGear 2>&1 | tee stage1.txt \
    && dnf -y clean all \
    && awk '/^Dependencies resolved/,/^Transaction Summary/' stage1.txt | \
           grep '^ ' | sed 's/  */ /g' | \
           grep -v 'Package Arch Version Repo Size' | \
           cut -d' ' -f2 | sort -u > fedora-runtime.txt

# *** STAGE 2 ***
#
# The second stage determines the unique set of fedora runtimes not
# found in the RHEL/EPEL package repositories.

# TODO Change this to UBI 10 after RHEL 10 GA
##FROM registry.redhat.io/ubi10/ubi:latest
FROM quay.io/centos/centos:stream10 AS rhel-rt

# The copy from a prior stage must be the first directive after the
# FROM otherwise it's ignored.

COPY --from=fedora-rt /fedora-runtime.txt /

# Preserve the output from the prior stage in the externally mounted
# DEPENDENCIES directory for later troubleshooting.

ARG DEPENDENCIES=flightgear-dependencies
RUN    mkdir -p $DEPENDENCIES \
    && mv /fedora-runtime.txt $DEPENDENCIES

# Discover all the missing runtime dependencies by trying to install the
# FlightGear runtime dependencies identified in stage 1. The grep/rev/cut
# parsing of the dnf output should identify all the simple package names
# for the missing dependencies. The list of dependencies here includes all
# the runtime dependencies for FlightGear on Fedora which do not have a
# counterpart in RHEL/EPEL. These will need to be built from SRPMs for RHEL.

# Output is sent to stdout for troubleshooting.

ARG DEPENDENCIES=flightgear-dependencies
RUN    dnf -y install util-linux \
           https://dl.fedoraproject.org/pub/epel/epel-release-latest-10.noarch.rpm \
    && /usr/bin/crb enable \
    && dnf -y install --skip-broken $(cat $DEPENDENCIES/fedora-runtime.txt) 2>&1 | \
           tee stage2.txt \
    && dnf -y clean all \
    && grep '^No match for argument' stage2.txt | rev | cut -d' ' -f1 | rev | \
           sort -u > rhel-runtime.txt

# *** STAGE 3 ***
#
# The third stage determines the unique set of buildtime fedora packages
# needed to rebuild the runtime packages missing in RHEL/EPEL that we
# identified in stage 2.

FROM fedora:40 as fedora-bt

# The copy from a prior stage must be the first directive after the
# FROM otherwise it's ignored.

COPY --from=rhel-rt /rhel-runtime.txt /

# Preserve the output from the prior stage in the externally mounted
# DEPENDENCIES directory for later troubleshooting.

ARG DEPENDENCIES=flightgear-dependencies
RUN    mkdir -p $DEPENDENCIES \
    && mv /rhel-runtime.txt $DEPENDENCIES

# Discover all the buildtime dependencies by downloading all of the
# SRPMs for the runtime dependencies identified in stage 2. This list is
# the buildtime dependencies for fedora and many of these packages will
# also exist in RHEL/EPEL already. We'll use this fedora buildtime list to
# identify the missing buildtime dependencies for RHEL/EPEL in the next
# stage. This stage also creates an archive of the runtime dependency SRPM
# files so we only have to download those once. The awk/grep/cut parsing
# of the dnf output should identify all the simple package names for the
# fedora buildtime dependencies.

# Output is sent to stdout for troubleshooting.

ARG DEPENDENCIES=flightgear-dependencies
RUN    dnf -y install 'dnf-command(download)' \
    && dnf -y download --source --archlist x86_64,noarch \
           $(cat $DEPENDENCIES/rhel-runtime.txt) \
    && tar zcvf missing-runtime-rpms.tgz *.src.rpm \
    && dnf -y builddep --srpm $(ls *.src.rpm) 2>&1 | tee stage3.txt \ 
    && dnf -y clean all \
    && awk '/^Dependencies resolved/,/^Transaction Summary/' stage3.txt | \
           grep '^ ' | sed 's/  */ /g' | \
           grep -v 'Package Arch Version Repo Size' | \
           cut -d' ' -f2 | sort -u > fedora-buildtime.txt

# *** STAGE 4 ***
#
# The fourth stage determines the unique set of buildtime dependencies
# not found in RHEL/EPEL. We will need the fedora SRPMs for these files
# in order to build the runtime dependencies on RHEL/EPEL in a later stage.

# TODO Change this to UBI 10 after RHEL 10 GA
##FROM registry.redhat.io/ubi10/ubi:latest
FROM quay.io/centos/centos:stream10 AS rhel-bt

# The copy from a prior stage must be the first directive after the
# FROM otherwise it's ignored.

COPY --from=fedora-bt /fedora-buildtime.txt /

# Preserve the output from the prior stage in the externally mounted
# DEPENDENCIES directory for later troubleshooting.

ARG DEPENDENCIES=flightgear-dependencies
RUN    mkdir -p $DEPENDENCIES \
    && mv /fedora-buildtime.txt $DEPENDENCIES

# Discover all the missing buildtime dependencies for RHEL/EPEL
# by attempting to install the fedora buildtime dependencies. The
# grep/rev/cut parsing finds all the simple package names for the missing
# build dependencies. The comm command finds all of the fedora buildtime
# dependencies that don't exist in RHEL/EPEL.

# Output is sent to stdout for troubleshooting.

ARG DEPENDENCIES=flightgear-dependencies
RUN    dnf -y install util-linux \
           https://dl.fedoraproject.org/pub/epel/epel-release-latest-10.noarch.rpm \
    && /usr/bin/crb enable \
    && dnf -y install --skip-broken $(cat $DEPENDENCIES/fedora-buildtime.txt) 2>&1 | \
           tee stage4.txt \
    && dnf -y clean all \
    && grep '^No match for argument' stage4.txt | rev | cut -d' ' -f1 | rev | \
           sort -u > intermediate-buildtime.txt \
    && sort -uo intermediate-buildtime.txt intermediate-buildtime.txt \
    && sort -uo $DEPENDENCIES/rhel-runtime.txt  $DEPENDENCIES/rhel-runtime.txt \
    && comm -23 intermediate-buildtime.txt $DEPENDENCIES/rhel-runtime.txt \
           > rhel-buildtime.txt

# *** STAGE 5 ***
#
# The fifth stage downloads the SRPMs for the buildtime dependencies
# not found in RHEL/EPEL.

FROM fedora:40 as fedora-sources

# The copy from a prior stage must be the first directive after the FROM
# otherwise it's ignored.

COPY --from=rhel-bt /rhel-buildtime.txt /

# Preserve the output from the prior stage in the externally mounted
# DEPENDENCIES directory for later troubleshooting.

ARG DEPENDENCIES=flightgear-dependencies
RUN    mkdir -p $DEPENDENCIES \
    && mv /rhel-buildtime.txt $DEPENDENCIES

# Download all the missing buildtime dependencies for RHEL/EPEL.
#
# Output is sent to stdout for troubleshooting.

ARG DEPENDENCIES=flightgear-dependencies
RUN    dnf -y install 'dnf-command(download)' \
    && dnf -y download --source --archlist x86_64,noarch \
           $(cat $DEPENDENCIES/rhel-buildtime.txt) \
    && dnf -y clean all \
    && tar zcvf missing-buildtime-rpms.tgz *.src.rpm

# *** STAGE 6 ***
#
# The sixth and final attempts to build all the missing buildtime and
# runtime dependencies not found in RHEL/EPEL.

# TODO Change this to UBI 10 after RHEL 10 GA
##FROM registry.redhat.io/ubi10/ubi:latest
FROM quay.io/centos/centos:stream10

# The copies from previous stages must be the first directives after
# the FROM otherwise it's ignored.

COPY --from=fedora-bt missing-runtime-rpms.tgz /
COPY --from=fedora-sources missing-buildtime-rpms.tgz /

# Install all the dependencies to build the missing RPMs. This can
# sometimes fail since some of the missing dependencies must be built
# themselves, so address all the dependencies in a for loop and skip any
# errors. The next loop will attempt to iteratively build each SRPM in
# turn until all dependencies are met.

RUN    dnf -y install rpmdevtools tcl findutils \
           https://dl.fedoraproject.org/pub/epel/epel-release-latest-10.noarch.rpm \
    && /usr/bin/crb enable \
    && mkdir -p srpms \
    && tar zxvf missing-runtime-rpms.tgz -C srpms \
    && tar zxvf missing-buildtime-rpms.tgz -C srpms \
    && for bd in $(ls srpms/*.src.rpm); \
       do \
           dnf -y builddep --skip-unavailable --srpm --skip-broken -v "$bd" || echo "*** ERROR ***" ; \
       done

# At this point, we need to attempt to build each SRPM and then install
# the resulting RPMs until they all eventually build. This could probably
# be more efficient

ARG FG_RPMS=flightgear-rpms
RUN    mkdir -p completed-srpms $FG_RPMS \
    && while [ ! -z "$(ls -A srpms)" ]; \
       do \
           for i in $(ls srpms/*.src.rpm); \
           do \
               if [ ! -z "$(ls -A $FG_RPMS)" ]; \
               then \
                   dnf -y install --skip-broken $FG_RPMS/*.rpm; \
               fi; \
               rm -fr /root/rpmbuild; \
	       OPTIONS=""; \
               echo $i | grep -qE 'fltk' && OPTIONS="--nodeps"; \
               rpmbuild --rebuild $OPTIONS $i || echo "*** BUILD ERROR ***"; \
               if [ ! -z "$(find /root/rpmbuild/RPMS -type f -name '*.rpm')" ]; \
               then \
                   mv $i completed-srpms; \
                   cp $(find /root/rpmbuild/RPMS/ -type f -name '*.rpm' | grep -vE 'debugsource|debuginfo') $FG_RPMS; \
               fi; \
           done; \
       done
