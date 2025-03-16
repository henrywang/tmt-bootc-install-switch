#!/bin/bash
set -exuo pipefail

if [ "$TMT_REBOOT_COUNT" -eq 0 ]; then
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

    # Running on Testing Farm
    if [[ -d "/var/ARTIFACTS" ]]; then
        cp -r /var/ARTIFACTS "$TEMPDIR"
    # Running on local machine with tmt run
    else
        cp -r /var/tmp/tmt "$TEMPDIR"
    fi

    cp -r /usr/local/bin "$TEMPDIR"

    if [[ "$VERSION_ID" == "43" ]]; then
        BOOTC_COPR_REPO_DISTRO="fedora-rawhide-${ARCH}"
    fi

    CONTAINERFILE=${TEMPDIR}/Containerfile
    tee "$CONTAINERFILE" > /dev/null << REALEOF
FROM $TIER1_IMAGE_URL

RUN <<EORUN
set -xeuo pipefail

cat <<EOF >> /etc/yum.repos.d/bootc.repo
[bootc]
name=bootc
baseurl=https://download.copr.fedorainfracloud.org/results/rhcontainerbot/bootc/${BOOTC_COPR_REPO_DISTRO}/
enabled=1
gpgcheck=0
repo_gpgcheck=0
EOF

dnf -y update bootc
# cloud-init and rsync are required by TMT
dnf -y install cloud-init rsync
ln -s ../cloud-init.target /usr/lib/systemd/system/default.target.wants
dnf -y clean all
rm -rf /var/cache /var/lib/dnf
EORUN
# Some rhts-*, rstrnt-* and tmt-* commands are in /usr/local/bin
COPY bin /usr/local/bin
REALEOF

    if [[ -d "/var/ARTIFACTS" ]]; then
        # TMT work dir /var/ARTIFACTS should be reserved
        echo "COPY ARTIFACTS /var/ARTIFACTS" >> "$CONTAINERFILE"
    else
        # TMT work dir /var/tmp/tmt should be reserved
        echo "COPY tmt /var/tmp/tmt" >> "$CONTAINERFILE"
    fi

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
    echo "$PATH"
    printenv
    if [[ -d "/var/ARTIFACTS" ]]; then
        ls -al /var/ARTIFACTS
    else
        ls -al /var/tmp/tmt
    fi
    ls -al /usr/local/bin
    echo "bootc install to-existing-root succeed"
    exit 0
fi
