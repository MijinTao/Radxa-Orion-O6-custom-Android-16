# Build environment for Android 16 on the Radxa Orion O6: CIX's Android 16 tree (github.com/cixtech/android-manifest)
# + the patches in ./patches. Ubuntu 22.04 with the AOSP host packages, plus the host tools CIX's build-android.sh
# uses for its bootloader (EDK2) and kernel steps. No system cross compiler: CIX's tree brings its own AArch64
# toolchains (and Ubuntu's gcc-multilib, needed for 32-bit host bits, conflicts with crossbuild-essential-arm64).
FROM ubuntu:22.04

ARG DEBIAN_FRONTEND=noninteractive
ARG REPO_URL=https://storage.googleapis.com/git-repo-downloads/repo

# Includes every package CIX's build-scripts/check_dep.sh requires (DEPS_debian + DEPS_android, checked with
# dpkg-query, and lsb_release itself); build-android.sh stops if one is missing.

RUN apt-get update \
 && apt-get install -y --no-install-recommends \
      ca-certificates curl wget git git-lfs gnupg locales sudo tzdata \
      build-essential gcc-multilib g++-multilib libc6-dev-i386 lib32ncurses-dev lib32z1-dev \
      flex bison gperf zip unzip zlib1g-dev libxml2-utils xsltproc fontconfig \
      python3 python3-pip python-is-python3 python3-pyelftools \
      rsync bc cpio kmod lz4 xz-utils zstd pigz file \
      libssl-dev libelf-dev libncurses-dev libncurses5 device-tree-compiler dwarves \
      uuid-dev nasm acpica-tools mtools dosfstools e2fsprogs \
      lsb-release x11proto-core-dev libx11-dev libgl1-mesa-dev liblz4-tool \
 && rm -rf /var/lib/apt/lists/* \
 && locale-gen en_US.UTF-8 \
 && curl -fsSL "$REPO_URL" -o /usr/local/bin/repo && chmod 0755 /usr/local/bin/repo \
 && git lfs install --system

ENV LANG=en_US.UTF-8 LC_ALL=en_US.UTF-8 USER=builder
# The build runs as an unprivileged user (AOSP and some CIX scripts don't expect root).
RUN useradd -m -u 1000 -s /bin/bash builder

COPY container-build.sh /usr/local/bin/build-android16
# Patches keep their exact bytes (see .gitattributes); the firmware patch is binary.
COPY patches/ /opt/android-patches/
COPY flash.ps1 flash.sh /opt/android-flash/
COPY manifest/ /opt/android-manifest/
# Strip Windows line endings from the scripts, in case they were edited on Windows.
RUN sed -i 's/\r$//' /usr/local/bin/build-android16 /opt/android-flash/flash.sh \
 && chmod +x /usr/local/bin/build-android16

VOLUME ["/work", "/out"]
WORKDIR /work
ENTRYPOINT ["/usr/local/bin/build-android16"]
