#! /bin/sh

del_container() {
    IMAGE="$1"
    TAG="$2"
    CONTAINER_NAME="$3"
    docker container stop "$CONTAINER_NAME" && docker container rm "$CONTAINER_NAME"
}
# TODO explain the differences and purpose of *-builder image.
build_dev() {
    IMAGE="$1"
    TAG="$2"
    docker build . -f ./dockerfiles/alpine.dev.Dockerfile -t "$IMAGE-builder:$TAG"
}

build() {
    IMAGE="$1"
    TAG="$2"
    docker build . -f ./dockerfiles/alpine.dev.Dockerfile -t "$IMAGE-builder:$TAG"
    docker build . -f ./dockerfiles/alpine.Dockerfile -t "$IMAGE:$TAG"
}

run_container() {
    IMAGE="$1"
    TAG="$2"
    CONTAINER_NAME="$3"
    docker container run --pull=never -itd --network=host --name "$CONTAINER_NAME" "$IMAGE:$TAG"
}

run_container_dev() {
    IMAGE="$1"
    TAG="$2"
    CONTAINER_NAME="$3"
    DEV_PATH="$4"
    del_container "$IMAGE_NAME" "$TAG" "$CONTAINER_NAME"
    docker container run  --pull=never -itd --network=host --name "$CONTAINER_NAME" -v "$PWD:$DEV_PATH" "$IMAGE-builder:$TAG"
    docker exec -it -w "$DEV_PATH" "$CONTAINER_NAME" ./scripts/opam.sh install # Because the image doesn't contain opam dependencies installed. Only contains a switch
}

cp() {
    IMAGE="$1"
    TAG="$2"
    CONTAINER_NAME="$3"
    DEV_PATH="$4"
    HOST_RELEASE_PATH="$5"
    mkdir -p "$HOST_RELEASE_PATH/lib" "$HOST_RELEASE_PATH/bin"
    docker exec -it -w "$DEV_PATH" "$CONTAINER_NAME" ./scripts/opam.sh build
    docker exec -it -w "$DEV_PATH" "$CONTAINER_NAME" ./scripts/opam.sh install-artifacts
    docker cp "$CONTAINER_NAME:/usr/local/lib/esy" "$HOST_RELEASE_PATH/lib/esy"
    docker cp "$CONTAINER_NAME:/usr/local/bin/esy" "$HOST_RELEASE_PATH/bin"
    docker cp "$CONTAINER_NAME:/usr/local/bin/esyInstallRelease.js" "$HOST_RELEASE_PATH/bin"
}

IMAGE_NAME="esydev/esy"
TAG="nightly-alpine-latest"
CONTAINER_NAME="esy-container"
DEV_PATH="/root/app"

case "$1" in
    "build")
	build "$IMAGE_NAME" "$TAG"
	;;
    "build:dev")
	build_dev "$IMAGE_NAME" "$TAG"
	;;
    "run-container")
	run_container "$IMAGE_NAME" "$TAG" "$CONTAINER_NAME"
	;;
    "run-container:dev")
	run_container_dev "$IMAGE_NAME" "$TAG" "$CONTAINER_NAME" "$DEV_PATH"
	;;
    "cp")
	HOST_RELEASE_PATH="$2"
	if [ -z "$HOST_RELEASE_PATH" ]
	then
	    HOST_RELEASE_PATH="$PWD/_container_release"
	fi
	cp "$IMAGE_NAME" "$TAG" "$CONTAINER_NAME" "$DEV_PATH" "$HOST_RELEASE_PATH"
	;;
    "exec")
	shift
	docker exec -it -w "$DEV_PATH" "$CONTAINER_NAME"  $*
	;;
    "del-container")
	del_container "$IMAGE_NAME" "$TAG" "$CONTAINER_NAME"
	;;
esac
