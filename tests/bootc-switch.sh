#!/bin/bash
set -exuo pipefail

if [ "$TMT_REBOOT_COUNT" -eq 0 ]; then
    ARCH=$(uname -m)
    TEMPDIR=$(mktemp -d)
    trap 'rm -rf -- "$TEMPDIR"' EXIT

    # Get OS data.
    # source /etc/os-release
    ID=fedora
    VERSION_ID=42
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
dnf -y install rsync
dnf -y clean all
rm -rf /var/cache /var/lib/dnf
EORUN
REALEOF

    cat "$CONTAINERFILE"
    sudo podman build --tls-verify=false -t localhost/bootc:tmt -f "$CONTAINERFILE" "$TEMPDIR"
    sudo podman images
    sudo bootc switch --transport containers-storage localhost/bootc:tmt

    tmt-reboot
elif [ "$TMT_REBOOT_COUNT" -eq 1 ]; then
    bootc status
    echo "bootc switch succeed"
    exit 0
fi
