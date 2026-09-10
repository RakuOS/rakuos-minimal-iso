# RakuOS Minimal ISO

This repository builds the minimal live ISO for RakuOS Linux.

It is the ISO-side companion to the `rakuos-minimal` image repository and is built in GitLab using [RakuForge](https://gitlab.com/rakuos/iso/rakuos-forge), the RakuOS-maintained fork of uBlue's Titanoboa.

## Purpose

This repo exists to keep ISO-specific logic separate from the desktop image repo.

It owns:

- Minimal ISO pipeline configuration
- live ISO customization hooks
- post-rootfs and pre-initramfs scripts
- edition-specific ISO naming and release behavior

It does not own the desktop container image itself. That comes from:

- `registry.gitlab.com/rakuos/images/rakuos-minimal`
- `registry.gitlab.com/rakuos/images/rakuos-minimal/nvidia`

## Branches

The pipeline is branch-aware and follows the same release lanes as the rest of RakuOS:

- `main` -> stable / `latest`
- `staging` -> next Fedora release lane
- `rawhide` -> rolling development lane
- `rakuosel` -> future enterprise / EL lane

## Pipeline Behavior

GitLab CI builds two ISO variants:

- standard
- nvidia

The pipeline currently supports:

- branch-aware image tag selection
- branch-aware builder distro selection
- optional upload to the RakuOS server
- optional upload to SourceForge
- checksum artifacts stored in GitLab

### Current Inputs

The manual pipeline form exposes these inputs:

- `rakuos-server-upload`
- `sourceforge-upload`

## RakuForge

The pipeline clones and uses:

- `https://gitlab.com/rakuos/iso/rakuos-forge.git`

RakuForge is used to assemble the live ISO from the corresponding RakuOS bootc image while carrying the RakuOS-specific CI behavior needed for GitLab.

The *installed* image is `rakuos-minimal` (no desktop environment), but the
*live environment* on this ISO is the RakuOS **KDE** image, so users get a full
Plasma session and the Qt installer. RakuForge is invoked with the KDE image as
its positional `image` argument and `--container-image quay.io/rakuos/rakuos-minimal:<tag>`,
which is what gets baked into `/usr/share/rakuos/image-store` and installed to
disk.

`--cli-installer true` is also passed: it adds a **"Text-Mode Installer"** GRUB
entry that boots this same live media to `multi-user.target`, where a TTY
autologin launches `rakuos-installer-cli`. The graphical Plasma session remains
the default boot entry.

Upstream credit:

- https://github.com/ublue-os/titanoboa

## Repo Layout

- [config/configure-iso.sh](config/configure-iso.sh)
- [config/pre_initramfs.sh](config/pre_initramfs.sh)
- [.gitlab-ci.yml](.gitlab-ci.yml)

## Local Notes

This repo is primarily intended to run through GitLab CI. For local debugging, the same hook scripts can be used with RakuForge directly through its `Justfile`.
