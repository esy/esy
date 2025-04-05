#! /bin/sh

print_usage () {
    echo ""
    echo "docker.sh"
    echo "--help              Show this help message"
    echo "--image             Set image name"
    echo "--tag               Set image tag"
    echo "--container-name    Set container name"
    echo "--dev-path          Set the development path inside the container"
    echo ""
}

del_container() {
    IMAGE="$1"
    TAG="$2"
    CONTAINER_NAME="$3"
    docker container stop "$CONTAINER_NAME" && docker container rm "$CONTAINER_NAME"
}

build() {
    IMAGE="$1"
    TAG="$2"
    docker buildx build . -f ./dockerfiles/alpine.Dockerfile -t "$IMAGE:$TAG"
}

run_container() {
    IMAGE="$1"
    TAG="$2"
    CONTAINER_NAME="$3"
    BUILD_CONTEXT="$4"
    docker container run --pull=never -itd --network=host --name "$CONTAINER_NAME" "$IMAGE:$TAG"
}

run_container_dev() {
    IMAGE="$1"
    TAG="$2"
    CONTAINER_NAME="$3"
    DEV_PATH="$4"
    del_container "$IMAGE_NAME" "$TAG" "$CONTAINER_NAME"
    docker exec -it -w "$DEV_PATH" "$CONTAINER_NAME" ./scripts/opam.sh install # Because the image doesn't contain opam dependencies installed. Only contains a switch
}

cp() {
    IMAGE="$1"
    TAG="$2"
    CONTAINER_NAME="$3"
    CONTAINER_PATH="$4"
    HOST_PATH="$5"
    docker cp "$CONTAINER_NAME:$CONTAINER_PATH" "$HOST_PATH"
}

cp_artifacts() {
    IMAGE="$1"
    TAG="$2"
    CONTAINER_NAME="$3"
    DEV_PATH="$4"
    HOST_RELEASE_PATH="$5"
    mkdir -p "$HOST_RELEASE_PATH/lib" "$HOST_RELEASE_PATH/bin"
    docker cp "$CONTAINER_NAME:/usr/local/lib/esy" "$HOST_RELEASE_PATH/lib/esy"
    docker cp "$CONTAINER_NAME:/usr/local/bin/esy" "$HOST_RELEASE_PATH/bin"
    docker cp "$CONTAINER_NAME:/usr/local/bin/esyInstallRelease.js" "$HOST_RELEASE_PATH/bin"
}

IMAGE_NAME="esydev/esy"
TAG="nightly-alpine-latest"
CONTAINER_NAME="esy-container"
DEV_PATH="/app"
HOST_RELEASE_PATH="$PWD/_container_release"
BUILD_CONTEXT="."
SUB_COMMAND=""

while test $# -ge 1
do
    case "$1" in
	"-h*" | "--help")
	    print_usage;
	    exit 0 ;;
	"--build-context")
	    shift;
	    BUILD_CONTEXT="$1"
	    shift;
	    ;;
	"--image")
	    shift;
	    IMAGE_NAME="$1"
	    shift;
	    ;;
	"--tag")
	    shift
	    TAG="$1"
	    shift;
	    ;;
	"--container-name")
	    shift;
	    CONTAINER_NAME="$1"
	    shift;
	    ;;
	"--host-release-path")
	    shift;
	    HOST_RELEASE_PATH="$1"
	    shift;
	    ;;
	"--dev-path")
	    shift;
	    DEV_PATH="$1"
	    shift;
	    ;;
	"build")
	    SUB_COMMAND="docker-build"
	    shift
	    ;;
	"run-container")
	    SUB_COMMAND="docker-run-container"
	    shift
	    ;;
	"run-container:dev")
	    SUB_COMMAND="docker-run-container:dev"
	    shift
	    ;;
	"cp")
	    SUB_COMMAND="docker-cp"
	    shift
	    break;
	    ;;
	"cp-artifacts")
	    SUB_COMMAND="docker-cp-artifacts"
	    shift
	    break;
	    ;;
	"exec")
	    SUB_COMMAND="docker-exec"
	    shift
	    break
	    ;;
	"del-container")
	    SUB_COMMAND="docker-del-container"
	    shift;
	    ;;
	*)
	    echo "Unrecognised command/args $1"
	    print_usage
	    exit -1
	    ;;
    esac
done

case "$SUB_COMMAND" in
    "docker-build")
	build "$IMAGE_NAME" "$TAG"
	break
	;;
    "docker-run-container")
	run_container "$IMAGE_NAME" "$TAG" "$CONTAINER_NAME" "$BUILD_CONTEXT"
	break
	;;
    "docker-run-container:dev")
	run_container_dev "$IMAGE_NAME" "$TAG" "$CONTAINER_NAME" "$DEV_PATH"
	break
	;;
    "docker-cp")
	cp "$IMAGE_NAME" "$TAG" "$CONTAINER_NAME" "$1" "$2"
	;;
    "docker-cp-artifacts")
	cp_artifacts "$IMAGE_NAME" "$TAG" "$CONTAINER_NAME" "$DEV_PATH" "$HOST_RELEASE_PATH"
	;;
    "docker-exec")
	docker exec -it -w "$DEV_PATH" "$CONTAINER_NAME"  $*
	;;
    "docker-del-container")
	del_container "$IMAGE_NAME" "$TAG" "$CONTAINER_NAME"
	;;
    "")
	print_usage
	exit -1;
	;;
    "*")
	echo "Unrecognised command: $1"
	exit -1
	;;
esac
