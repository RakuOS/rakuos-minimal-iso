#!/usr/bin/env bash

set -exo pipefail

# The minimal ISO's live system is built from the minimal image itself (the
# image the ISO installs), with the KDE image's package set and system files
# layered on top for a graphical live session and the Qt installer. The live
# image and the installed image then share every layer but the live one, so
# the ISO's bootc store holds one image, not a full KDE image next to the
# minimal one. The KDE layer comes from the rakuos-kde repo's own build
# scripts at the branch matching the image tag, so it stays in step with the
# KDE image. The rest mirrors rakuos-kde-iso/config/configure-iso.sh, plus
# the text-mode installer for the "Text-Mode Installer" GRUB entry.

source /etc/os-release

# sudo requires drop-in files to be owned by root and not be writable by others
chown root:root /etc/sudoers.d
chmod 0750 /etc/sudoers.d
chown root:root /etc/sudoers.d/rakuos
chmod 0440 /etc/sudoers.d/rakuos
chown root:root /etc/sudoers.d/pwfeedback
chmod 0440 /etc/sudoers.d/pwfeedback
chown root:root /etc/sudoers.d/secure-path
chmod 0440 /etc/sudoers.d/secure-path

# Remove all versionlocks to avoid dependency issues
rum -qy versionlock clear

# Variables
# rakuos-forge passes the image this live system is built from (there is
# no container store to ask inside the live image build).
imageref="${RAKUOS_IMAGE_REF:?rakuos-forge sets RAKUOS_IMAGE_REF}"
imageref="${imageref##*://}"
imagetag="${imageref##*:}"
imageref="${imageref%:*}"

### KDE live session layer ###
# The rakuos-kde branch that builds the KDE image for this tag. Staging
# images install the -staging RakuOS packages (RAKUOS_STAGING=1), as the
# KDE image's CI does on its staging branch.
case "$imagetag" in
    staging) KDE_BRANCH=staging KDE_STAGING=1 ;;
    rakuosel) KDE_BRANCH=rakuosel KDE_STAGING=0 ;;
    latest) KDE_BRANCH=main KDE_STAGING=0 ;;
    *)
        echo "No rakuos-kde branch for image tag '$imagetag'; using main" >&2
        KDE_BRANCH=main KDE_STAGING=0
        ;;
esac
KDE_SRC=/root/rakuos-kde
rm -rf "$KDE_SRC"
# The minimal image only brands the boot (logos, Plymouth, GRUB theme,
# fastfetch). The KDE image gets the rest from rakuos-base: the
# rakuos-branding meta package (GTK and icon themes, fonts config) and
# rakuos-wallpapers. Add them here, before the KDE scripts, so the live
# Plasma session looks like the KDE edition. Live only: the installer
# installs the minimal image as it is.
rum install -qy rakuos-branding rakuos-wallpapers
git clone --depth 1 --quiet --branch "$KDE_BRANCH" https://gitlab.com/rakuos/images/rakuos-kde.git "$KDE_SRC"
# Same order as the KDE image's Containerfile: system files, the build
# scripts, system files again. Its overlay prebake (post-build-overlay.sh)
# and chunking (assign-components.sh) only matter for a shipped image.
cp -a "$KDE_SRC/system_files/." /
RAKUOS_STAGING="$KDE_STAGING" bash "$KDE_SRC/build_files/build.sh"
if [[ $imageref == *-nvidia* ]]; then
    bash "$KDE_SRC/build_files/nvidia.sh"
fi
bash "$KDE_SRC/build_files/post-build.sh"
cp -a "$KDE_SRC/system_files/." /
rm -rf "$KDE_SRC"

# Install RakuOS installer (Qt frontend for the KDE live session + common
# backend) and the text-mode CLI frontend (for the "Text-Mode Installer" GRUB
# entry, which boots this same media to multi-user.target -- see
# rakuos-forge's --cli-installer).
rum install -qy rakuos-installer-kirigami
rum install -qy rakuos-installer-cli

# Mask overlay services so they cannot be started or pulled in on the live ISO
systemctl mask rakuos-overlay-sync.service rakuos-overlay-mount.service

# Read packages into array and install
mapfile -t PACKAGES < <(
    grep -v '^\s*#' "/usr/share/rakuos/packages-live.list" \
    | grep -v '^\s*$' \
    | sed 's/\s*#.*//' \
    | tr -s ' \t' '\n' \
    | sed 's/^[[:space:]]*//;s/[[:space:]]*$//' \
    | grep -v '^$'
) || true

rum install -y --refresh "${PACKAGES[@]}"

# Reset RakuOS overlay state for live ISO
echo "Resetting RakuOS overlay state for live ISO..."
rm -rf /var/lib/rakuos
mkdir -p /var/lib/rakuos
if [[ -f /usr/share/rakuos/packages-live.list ]]; then
    cp /usr/share/rakuos/packages-live.list /var/lib/rakuos/packages.list
    sed -i -e '$a\' /var/lib/rakuos/packages.list
fi

echo "RakuOS release $VERSION_ID ($VERSION_CODENAME)" >/etc/system-release

# Get shared artwork and system files from iso-base
git clone --depth 1 --quiet https://gitlab.com/rakuos/iso/iso-base.git /root/packages

### Desktop-environment specific tweaks ###

# Use GSK_RENDERER=gl for NVIDIA — workaround for GTK apps not opening
if [[ $imageref == *-nvidia* ]]; then
    mkdir -p /etc/environment.d /etc/skel/.config/environment.d
    echo "GSK_RENDERER=gl" >>/etc/environment.d/99-nvidia-fix.conf
    echo "GSK_RENDERER=gl" >>/etc/skel/.config/environment.d/99-nvidia-fix.conf
fi

# Re-enable nouveau for the live session on NVIDIA images
if [[ $imageref == *-nvidia* ]]; then
    for pkg in nvidia-gpu-firmware mesa-vulkan-drivers; do
        rum -yq reinstall --allowerasing $pkg ||
            rum -yq install --allowerasing $pkg
    done
    # Ensure nouveau vulkan ICDs exist
    (
        shopt -u nullglob
        ls /usr/share/vulkan/icd.d/nouveau_icd.*.json >/dev/null
    ) || {
        echo >&2 "::error::No nouveau vulkan ICDs found at /usr/share/vulkan/icd.d/nouveau_icd.*.json"
        exit 1
    }
fi

# Don't show the motd verification notice
rm -vf /etc/profile.d/verify_motd.sh

echo "Copying shared system files..."
cp -af /root/packages/installer/system_files/shared/. /

echo "Copying KDE-specific system files..."
cp -a /root/packages/installer/system_files/kde/. /

# Change default pins for KDE
sed -i '/const allPanels/,$d' /usr/share/plasma/layout-templates/org.rakuos.plasma.desktop.defaultPanel/contents/layout.js
sed -i '$r /usr/share/plasma/shells/org.kde.plasma.desktop/contents/updates/rakuos-pins.js' /usr/share/plasma/layout-templates/org.rakuos.plasma.desktop.defaultPanel/contents/layout.js

# Remove rakuos-welcome autostart for the live environment
rm -f /etc/xdg/autostart/rakuos-welcome.desktop

rm -rf /root/packages
