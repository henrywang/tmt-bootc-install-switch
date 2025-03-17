#!/bin/bash
set -exuo pipefail

TEMPDIR=$(mktemp -d)
trap 'rm -rf -- "$TEMPDIR"' EXIT

# Get OS data.
source /etc/os-release
case ""${ID}-${VERSION_ID}"" in
    "centos-"*)
        TEST_OS=$(echo "${ID}-${VERSION_ID}" | sed 's/-/-stream-/')
        ;;
    "fedora-"*)
        TEST_OS="${ID}-${VERSION_ID}"
        ;;
    *)
        echo "Don't work with this distro"
        exit 1
        ;;
esac

if [ "$TMT_REBOOT_COUNT" -eq 0 ]; then
    # Copy booted image to container storage
    bootc image copy-to-storage

    CONTAINERFILE=${TEMPDIR}/Containerfile
    tee "$CONTAINERFILE" > /dev/null << REALEOF
FROM localhost/bootc:latest

RUN <<EORUN
set -xeuo pipefail

# Install one package for upgrade test
dnf -y install wget
dnf -y clean all

rm -rf /var/cache /var/lib/dnf
EORUN
REALEOF

    cat "$CONTAINERFILE"
    podman build --tls-verify=false -t localhost/bootc:tmt -f "$CONTAINERFILE" "$TEMPDIR"
    podman images
    bootc upgrade

    tmt-reboot
elif [ "$TMT_REBOOT_COUNT" -eq 1 ]; then
    bootc status
    # Apply ansible.cfg
    export ANSIBLE_CONFIG="/var/tmp/bootc-test/ansible.cfg"
    # Run check-system.yaml
    ansible-playbook -v -i /var/tmp/bootc-test/inventory -e test_os="$TEST_OS" -e bootc_image="localhost/bootc:tmt" -e image_label_version_id="$VERSION_ID" -e running_on_tmt="enable" -e upgrade="true" /var/tmp/bootc-test/check-system.yaml
    exit 0
fi
