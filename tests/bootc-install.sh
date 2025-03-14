#!/bin/bash
set -exuo pipefail

if [ "$TMT_REBOOT_COUNT" -eq 0 ]; then
    ARCH=$(uname -m)
    TEMPDIR=$(mktemp -d)
    trap 'rm -rf -- "$TEMPDIR"' EXIT

    # Get OS data.
    source /etc/os-release
    case ""${ID}-${VERSION_ID}"" in
        "centos-9")
            TIER1_IMAGE_URL="quay.io/centos-bootc/centos-bootc:stream9"
            BOOTC_COPR_REPO_DISTRO="centos-stream-9-${ARCH}"
            ;;
        "centos-10")
            TIER1_IMAGE_URL="quay.io/centos-bootc/centos-bootc:stream10"
            BOOTC_COPR_REPO_DISTRO="centos-stream-10-${ARCH}"
            ;;
        "fedora-"*)
            TIER1_IMAGE_URL="quay.io/fedora/fedora-bootc:${VERSION_ID}"
            BOOTC_COPR_REPO_DISTRO="fedora-${VERSION_ID}-${ARCH}"
            ;;
        *)
            echo "Don't work with this distro"
            exit 1
            ;;
    esac

    ls -al /root/.ssh
    cat /root/.ssh/authorized_keys
    cp -r /root/.ssh "$TEMPDIR"

    if [[ "$VERSION_ID" == "43" ]]; then
        BOOTC_COPR_REPO_DISTRO="fedora-rawhide-${ARCH}"
    fi

    CONTAINERFILE=${TEMPDIR}/Containerfile
    tee "$CONTAINERFILE" > /dev/null << REALEOF
FROM $TIER1_IMAGE_URL

RUN <<EORUN
set -xeuo pipefail

mkdir -p -m 0700 /var/roothome

cat <<EOF >> /etc/yum.repos.d/bootc.repo
[bootc]
name=bootc
baseurl=https://download.copr.fedorainfracloud.org/results/rhcontainerbot/bootc/${BOOTC_COPR_REPO_DISTRO}/
enabled=1
gpgcheck=0
repo_gpgcheck=0
EOF

dnf -y update bootc
dnf -y install cloud-init rsync
ln -s ../cloud-init.target /usr/lib/systemd/system/default.target.wants
dnf -y clean all
rm -rf /var/cache /var/lib/dnf
EORUN
COPY .ssh /var/roothome/.ssh
REALEOF

    cat "$CONTAINERFILE"
    sudo podman build --tls-verify=false -t localhost/bootc:tmt -f "$CONTAINERFILE" "$TEMPDIR"
    sudo podman images
    sudo podman run \
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

    tmt-reboot
elif [ "$TMT_REBOOT_COUNT" -eq 1 ]; then
    bootc status
    echo "bootc install to-existing-root succeed"
    exit 0
fi
