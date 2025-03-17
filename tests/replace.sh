#!/bin/bash
set -exuo pipefail

ARCH=$(uname -m)
TEMPDIR=$(mktemp -d)
trap 'rm -rf -- "$TEMPDIR"' EXIT

echo "$PATH"
printenv
which tmt-reboot
ls -al /usr/local/bin

# Get OS data.
source /etc/os-release
case ""${ID}-${VERSION_ID}"" in
    "centos-"*)
        TIER1_IMAGE_URL="quay.io/centos-bootc/centos-bootc:stream${VERSION_ID}"
        TEST_OS=$(echo "${ID}-${VERSION_ID}" | sed 's/-/-stream-/')
        ;;
    "fedora-"*)
        TIER1_IMAGE_URL="quay.io/fedora/fedora-bootc:${VERSION_ID}"
        TEST_OS="${ID}-${VERSION_ID}"
        ;;
    *)
        echo "Don't work with this distro"
        exit 1
        ;;
esac

if [ "$TMT_REBOOT_COUNT" -eq 0 ]; then
    # Running on Testing Farm
    if [[ -d "/var/ARTIFACTS" ]]; then
        cp -r /var/ARTIFACTS "$TEMPDIR"
        cp -r /root/.ssh "$TEMPDIR"
    # Running on local machine with tmt run
    else
        cp -r /var/tmp/tmt "$TEMPDIR"
    fi

    cp -r /usr/local/bin "$TEMPDIR"

    cp check-system.yaml "$TEMPDIR"

    CONTAINERFILE=${TEMPDIR}/Containerfile
    tee "$CONTAINERFILE" > /dev/null << REALEOF
FROM $TIER1_IMAGE_URL

RUN <<EORUN
set -xeuo pipefail

# Let's trust this cert
update-ca-trust
# For testing farm
mkdir -p -m 0700 /var/roothome
# Save inventory and files used in test
mkdir -p /var/tmp/bootc-test

mkdir -p /usr/lib/bootc/kargs.d/
cat <<KARGEOF >> /usr/lib/bootc/kargs.d/20-console.toml
kargs = ["console=ttyS0,115200n8"]
KARGEOF

tee -a "/var/tmp/bootc-test/inventory" >/dev/null <<INVENTORYEOF
[guest]
localhost

[guest:vars]
ansible_connection=local

[all:vars]
ansible_python_interpreter=/usr/bin/python3
INVENTORYEOF

tee -a "/var/tmp/bootc-test/ansible.cfg" >/dev/null <<ANSIBLECFGEOF
[defaults]
# human-readable stdout/stderr results display
stdout_callback=community.general.yaml
callbacks_enabled=ansible.posix.profile_tasks, ansible.posix.timer
ANSIBLECFGEOF

# cloud-init and rsync are required by TMT
dnf -y install cloud-init rsync ansible-core
ln -s ../cloud-init.target /usr/lib/systemd/system/default.target.wants
dnf -y clean all

# Install galaxy collection used by ansible
ansible-galaxy collection install https://storage.googleapis.com/ansible-collection/community-general-9.3.0.tar.gz https://storage.googleapis.com/ansible-collection/ansible-posix-1.5.4.tar.gz

rm -rf /var/cache /var/lib/dnf
EORUN

# COPY check-system.yaml
COPY check-system.yaml /var/tmp/bootc-test

# Some rhts-*, rstrnt-* and tmt-* commands are in /usr/local/bin
COPY bin /usr/local/bin
REALEOF

    if [[ -d "/var/ARTIFACTS" ]]; then
        # In Testing Farm, TMT work dir /var/ARTIFACTS should be reserved
        echo "COPY ARTIFACTS /var/ARTIFACTS" >> "$CONTAINERFILE"
        # In Testing Farm, all ssh things should be reserved for ssh command run after reboot
        echo "COPY .ssh /var/roothome/.ssh" >> "$CONTAINERFILE"
    else
        # In local machine, TMT work dir /var/tmp/tmt should be reserved
        echo "COPY tmt /var/tmp/tmt" >> "$CONTAINERFILE"
    fi

    cat "$CONTAINERFILE"
    podman build --tls-verify=false -t localhost/bootc:tmt -f "$CONTAINERFILE" "$TEMPDIR"
    podman images
    podman run \
        --rm \
        --tls-verify=false \
        --privileged \
        --pid=host \
        -v /:/target \
        -v /dev:/dev \
        -v /var/lib/containers:/var/lib/containers \
        -v /root/.ssh:/output \
        --security-opt label=type:unconfined_t \
        "localhost/bootc:tmt" \
        bootc install to-existing-root --target-transport containers-storage

    # Reboot
    tmt-reboot
elif [ "$TMT_REBOOT_COUNT" -eq 1 ]; then
    bootc status
    echo "$PATH"
    printenv
    if [[ -d "/var/ARTIFACTS" ]]; then
        ls -al /var/ARTIFACTS
    else
        ls -al /var/tmp/tmt
    fi
    ls -al /var/tmp/bootc-test
    ls -al /usr/local/bin
    echo "bootc install to-existing-root succeed"

    # Apply ansible.cfg
    export ANSIBLE_CONFIG="/var/tmp/bootc-test/ansible.cfg"
    # Run check-system.yaml
    ansible-playbook -v -i /var/tmp/bootc-test/inventory -e test_os="$TEST_OS" -e bootc_image="localhost/bootc:tmt" -e image_label_version_id="$VERSION_ID" -e running_on_tmt="enable" /var/tmp/bootc-test/check-system.yaml
    exit 0
fi
