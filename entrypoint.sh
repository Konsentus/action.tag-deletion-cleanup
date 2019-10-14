#!/bin/bash -l

if [ -z "${GITHUB_EVENT_PATH}" ] || [ ! -f "${GITHUB_EVENT_PATH}" ]; then
    echo "No file containing event data found. Cannot continue"
    exit 2
fi

if [ -z "${INPUT_GITHUB_TOKEN}" ]; then
    echo "No Github token provided. Cannot continue"
    exit 2
fi

ORIGIN=${INPUT_REMOTE_NAME}
JSON=$(cat ${GITHUB_EVENT_PATH} | jq)
REF=$(echo -E ${JSON} | jq -r '.ref')
REF_TYPE=$(echo -e ${JSON} | jq -r '.ref_type')

if [ ! "${REF_TYPE}" == "tag" ]; then
    echo "Not a tag, skipping"
    exit 0
fi

git config --global user.email "${GITHUB_ACTOR}@users.noreply.github.com"
git config --global user.name "${GITHUB_ACTOR}"

# itterate through all branches in origin
for branch in $(git for-each-ref --format="%(refname:short)" | grep "${ORIGIN}/"); do
    local_branch=${branch/$ORIGIN\//}
    head_commit=$(git rev-list -n 1 ${branch})

    latest_tag=$(git describe --abbrev=0 --tags --first-parent ${branch} 2> /dev/null)
    # ignore branches with no existing tags (ignores feature branches and initial commits)
    if [ "$?" -ne "0" ]; then
        continue;
    fi

    latest_tag_commit=$(git rev-list -n 1 ${latest_tag} 2> /dev/null)
    # if the commit ids are identical, then latest tag is at head; no action to take
    if [ "${latest_tag_commit}" = "${head_commit}" ]; then
        continue;
    fi

    remote_repo="https://${GITHUB_ACTOR}:${INPUT_GITHUB_TOKEN}@github.com/${GITHUB_REPOSITORY}.git"

    echo "copy .github to temp location"
    cp -a .github /tmp/
    echo "hub checkout ${local_branch}"
    hub checkout ${local_branch}
    echo "hub reset --hard ${latest_tag}"
    hub reset --hard ${latest_tag}
    echo "move .github back over"
    rm -rf .github
    mv /tmp/.github .
    echo "hub commit -m 'Overlay current .github folder'"
    hub commit -m 'Overlay current .github folder'
    echo "hub push --force ${remote_repo} ${local_branch}"
    hub push --force ${remote_repo} ${local_branch}
done
