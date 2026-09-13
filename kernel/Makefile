.PHONY: all image

IMAGE := chip-kernel-alpine-armv7

all: image
	docker volume create chip-kernel-build >/dev/null
	docker run \
		--platform linux/arm/v7 \
		-e HOST_UID=$$(id -u) \
		-e HOST_GID=$$(id -g) \
		-v $$PWD:/build \
		-v chip-kernel-build:/home/build \
		-w /build \
		--rm $(IMAGE) ./build-apk.sh
	./verify-config.sh

image:
	docker build --platform linux/arm/v7 -t $(IMAGE) .
