.PHONY: all image

IMAGE := chip-os-alpine-armv7

# The kernel apk is built separately (../kernel) and bind-mounted read-only so
# this Makefile doesn't have to know how to build it -- `make -C ../kernel`
# first if ./../kernel/out/*.apk doesn't exist yet.
all: image
	docker run \
		--platform linux/arm/v7 \
		--privileged \
		-e HOST_UID=$$(id -u) \
		-e HOST_GID=$$(id -g) \
		-v /dev:/dev \
		-v /proc:/proc \
		-v /sys:/sys \
		-v $$PWD:/build \
		-v $$PWD/../kernel/out:/kernel-out:ro \
		-w /build \
		--rm $(IMAGE) ./build.sh

image:
	docker build --platform linux/arm/v7 -t $(IMAGE) .
