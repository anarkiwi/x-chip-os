# armv7 build container: runs natively under qemu (same --platform linux/arm/v7
# + binfmt setup the rootfs flavors use), so the kernel builds with the same
# toolchain the target runs -- no cross-compiler needed.
FROM alpine:3.24

RUN apk update && apk add --no-cache \
        alpine-sdk \
        linux-headers \
        bash \
        bc \
        bison \
        flex \
        openssl-dev \
        elfutils-dev \
        perl \
        ncurses-dev \
        diffutils \
        findutils \
        kmod \
        xz \
        zstd \
        curl \
    # abuild refuses to run as root; the alpine-sdk 'abuild' group + a build
    # user is the standard convention. HOST_UID/GID are passed at `docker run`
    # so files written into the bind-mounted repo come back owned by the host
    # user, matching the live-build containers' HOST_UID/GID convention.
    && adduser -D -G abuild build
