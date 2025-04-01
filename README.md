THIS IS AN INCOMPLETE WORK-IN-PROGRESS

# Build FlightGear flight simulator for RHEL 10
Use a Containerfile with multi-stage builds to sort out all the missing
dependencies and build the RPMs.

Install RHEL 10 minimal. Make sure that you have allocated a lot of
storage to the /home mount as this build will grow the local container
storage to over 120GB. Clone this repository to your physical or virtual
guest instance of RHEL 10. Edit `demo.conf` to set SCA credentials. Next,
register with SCA and pull updates

    cd ~/build-flightgear-rpms
    sudo ./register-and-update.sh
    sudo reboot

Install podman

    cd ~/build-flightgear-rpms
    sudo dnf -y install podman

Prepare to build the RPMs. Login to the registry using your Red Hat
customer portal credentials.

    . demo.conf
    podman login -u $SCA_USER -p $SCA_PASS registry.redhat.io

    DEPENDENCIES=flightgear-dependencies
    FG_RPMS=flightgear-rpms

    mkdir -p $DEPENDENCIES $FG_RPMS

Build the FlightGear RPMs. The 'build-arg` parameters are optional if
using the default locations.

    podman build -f Containerfile -t localhost/fg-rpms \
        -v $(pwd)/$DEPENDENCIES:/flightgear-dependencies:Z \
        -v $(pwd)/$FG_RPMS:/flightgear-rpms:Z \
        --build-arg DEPENDENCIES=$DEPENDENCIES \
        --build-arg FG_RPMS=$FG_RPMS 2>&1 | \
        tee output.txt

The list of dependencies that were discovered will be in the
`flightgear-dependencies` directory so you know what to install for
FlightGear as well as to support troubleshooting. The built RPMs will be
in the `flightgear-rpms` directory when the container build finishes.

Not all of the RPMs are necessary to install FlightGear. You only need
the ones for the missing runtime dependencies.
