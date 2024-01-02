#!/bin/bash
set -e

# login to the docker registry if we are going to publish the image
BUILD_ADDITIONAL_ARGS=""
if [ "$PUBLISH" = "true" ] ; then

  # ensure the registry host was provided
  if [ -z ${REGISTRY_HOST:+x} ]; then
    printf "ERROR: 'registryHost' must be specified in order to publish\n"
    exit 1
  fi

  # ensure the registry username was provided
  if [ -z ${REGISTRY_USERNAME:+x} ]; then
    printf "ERROR: 'username' must be specified in order to publish\n"
    exit 1
  fi

  # ensure the registry API key was provided
  if [ -z ${REGISTRY_API_TOKEN:+x} ]; then
    printf "ERROR: 'apiToken' must be specified in order to publish\n"
    exit 1
  fi

  # login to the docker registry
  printf "Logging in to the Docker registry host: ${REGISTRY_HOST}...\n"
  echo $REGISTRY_API_TOKEN | docker login $REGISTRY_HOST -u $REGISTRY_USERNAME --password-stdin

  # add additional args for the builder
  BUILD_ADDITIONAL_ARGS="--load"

fi

# if the image name is not provided, then set to repo name
if [ -z ${NAME:+x} ]; then
  NAME=$REPO
fi

# construct the registry image name
REGISTRY_IMAGE="${NAME}"
TAGGED_REGISTRY_IMAGE="${REGISTRY_IMAGE}:${PACKAGE_VERSION}${TAG_POSTFIX}"

# extract the build args
FLATTENED_BUILD_ARGS=""
IFS=',' read -ra ARGS <<< "${BUILD_ARGS}"
for arg in "${ARGS[@]}"; do
  FLATTENED_BUILD_ARGS="${FLATTENED_BUILD_ARGS} --build-arg=\"${arg}\""
done

# extract the tags
FLATTENED_TAGS=""
if [ "$PUBLISH" = "true" ] ; then
  FLATTENED_TAGS="-t ${REGISTRY_HOST}/${TAGGED_REGISTRY_IMAGE}"
else
  FLATTENED_TAGS="-t ${TAGGED_REGISTRY_IMAGE}"
fi
IFS=',' read -ra TAGS <<< "${ADDITIONAL_TAGS}"
for tag in "${TAGS[@]}"; do
  if [ "$PUBLISH" = "true" ] ; then
    FLATTENED_TAGS="${FLATTENED_TAGS} -t ${REGISTRY_HOST}/${REGISTRY_IMAGE}:${tag}"
  else
    FLATTENED_TAGS="${FLATTENED_TAGS} -t ${REGISTRY_IMAGE}:${tag}"
  fi
done

# build the image for each platform
IFS=',' read -ra PLATS <<< "${PLATFORMS}"
for platform in "${PLATS[@]}"; do

  # setup a multiplatform builder
  BUILDER=$(docker buildx create --use --buildkitd-flags '--allow-insecure-entitlement network.host')

  # build the image
  docker buildx build ${FLATTENED_TAGS} -f ${DOCKERFILE} ${CONTEXT} --network host --platform ${platform} --builder ${BUILDER} --progress plain ${BUILD_ADDITIONAL_ARGS}

  # publish the image
  if [ "$PUBLISH" = "true" ] ; then
    docker push ${REGISTRY_HOST}/${TAGGED_REGISTRY_IMAGE}
  fi

done
