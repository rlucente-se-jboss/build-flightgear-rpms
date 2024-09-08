# Build FlightGear flight simulator for RHEL 9
Use a Containerfile with multi-stage builds to sort out all the missing
dependencies and build the RPMs.

Install RHEL 9.4 minimal. Clone this repository to your physical
or virtual guest instance of RHEL 9.4. Edit `demo.conf` to set SCA
credentials. Next, register with SCA and pull updates

    cd ~/build-flightgear-rpms
    sudo ./register-and-update.sh
    sudo reboot

Install podman

    cd ~/build-flightgear-rpms
    sudo dnf -y install podman

Prepare to build the RPMs. Login to the registry using your Red Hat
customer portal credentials.

    mkdir -p flightgear-rpms
    podman login registry.redhat.io

Build the FlightGear RPMs

    podman build -f Containerfile -t built-fg-rpms -v $(pwd)/flightgear-rpms:/rpms:Z

The RPMs will be in the flightgear-rpms directory when the container
build finishes. You can discard the `-devel` RPMs as you will no longer
need those.

    rm -f flightgear-rpms/*-devel*

Not all of the RPMs are necessary to install FlightGear. You only need
the ones for missing runtime dependencies. With a little trial and error,
I narrowed the list to everything in `runtime-dependencies.txt`.
