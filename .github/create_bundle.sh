#!/bin/bash
set -e

CLUSTER_BUNDLE_FILE="bundle/manifests/manila-operator.clusterserviceversion.yaml"

echo "Creating manila operator bundle"
cd ..
echo "${GITHUB_SHA}"
echo "${BASE_IMAGE}"
skopeo --version

echo "Calculating image digest for docker://${REGISTRY}/${BASE_IMAGE}:${GITHUB_SHA}"
DIGEST=$(skopeo inspect docker://${REGISTRY}/${BASE_IMAGE}:${GITHUB_SHA} | jq '.Digest' -r)
# Output:
echo "Digest: ${DIGEST}"

RELEASE_VERSION=$(grep "^VERSION" Makefile | awk -F'?= ' '{ print $2 }')
OPERATOR_IMG_WITH_DIGEST="${REGISTRY}/${BASE_IMAGE}@${DIGEST}"

echo "New Operator Image with Digest: $OPERATOR_IMG_WITH_DIGEST"
echo "Release Version: $RELEASE_VERSION"

echo "Creating bundle image..."
VERSION=$RELEASE_VERSION IMG=$OPERATOR_IMG_WITH_DIGEST make bundle

echo "Bundle file images:"
cat "${CLUSTER_BUNDLE_FILE}" | grep "image:"
# FIXME: display any ENV variables once we have offline support implemented
#grep -A1 IMAGE_URL_DEFAULT "${CLUSTER_BUNDLE_FILE}"

# We do not want to exit here. Some images are in different registries, so
# error will be reported to the console.
set +e
for csv_image in $(cat "${CLUSTER_BUNDLE_FILE}" | grep "image:" | sed -e "s|.*image:||" | sort -u); do
    digest_image=""
    echo "CSV line: ${csv_image}"

    # case where @ is in the csv_image image
    if [[ "$csv_image" =~ .*"@".* ]]; then
        delimeter='@'
    else
        delimeter=':'
    fi

    base_image=$(echo $csv_image | cut -f 1 -d${delimeter})
    tag_image=$(echo $csv_image | cut -f 2 -d${delimeter})
    digest_image=$(skopeo inspect docker://${base_image}${delimeter}${tag_image} | jq '.Digest' -r)
    echo "Base image: $base_image"
    if [ -n "$digest_image" ]; then
        echo "$base_image${delimeter}$tag_image becomes $base_image@$digest_image"
        sed -i "s|$base_image$delimeter$tag_image|$base_image@$digest_image|g" "${CLUSTER_BUNDLE_FILE}"
    else
        echo "$base_image${delimeter}$tag_image not changed"
    fi
done

echo "Resulting bundle file images:"
cat "${CLUSTER_BUNDLE_FILE}" | grep "image:"

# FIXME: display any ENV variables once we have offline support implemented
#grep -A1 IMAGE_URL_DEFAULT "${CLUSTER_BUNDLE_FILE}"
