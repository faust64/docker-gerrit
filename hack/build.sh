#!/bin/sh -e

DOCKERFILE_PATH=
IMAGE_NAME=ci/gerrit

trap "rm -f $DOCKERFILE_PATH.version" INT QUIT EXIT

docker_build_with_version()
{
    local dockerfile="$1"
    DOCKERFILE_PATH=$(perl -MCwd -e 'print Cwd::abs_path shift' $dockerfile)
    cp $DOCKERFILE_PATH "$DOCKERFILE_PATH.version"
    git_version=$(git rev-parse --short HEAD)
    echo "LABEL io.openshift.builder-version=\"$git_version\"" >>"$dockerfile.version"
    docker build -t $IMAGE_NAME -f "$dockerfile.version" .
    if test "$SKIP_SQUASH" != "1"; then
	squash "$dockerfile.version"
    fi
    rm -f "$dockerfile.version"
}

squash()
{
    easy_install -q --user docker_py==1.6.0 docker-scripts==0.4.4
    base=$(awk '/^FROM/{print $2}' $1)
    $HOME/.local/bin/docker-scripts squash -f $base $IMAGE_NAME
}

if test "$TEST_MODE"; then
    IMAGE_NAME="$IMAGE_NAME-candidate"
fi
echo "-> Building $IMAGE_NAME ..."
docker_build_with_version Dockerfile
