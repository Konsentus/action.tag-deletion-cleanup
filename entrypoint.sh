#!/bin/bash -l

if [ -z "${GITHUB_EVENT_PATH}" ] || [ ! -f "${GITHUB_EVENT_PATH}" ]; then
    echo "No file containing event data found. Cannot continue"
    exit 2
fi

printenv | grep INPUT
printenv | grep GIT
exit

ORIGIN=${INPUT_REMOTE_NAME}
JSON=$(cat ${GITHUB_EVENT_PATH} | jq)
REF=$(echo -E ${JSON} | jq -r '.ref')
REF_TYPE=$(echo -e ${JSON} | jq -r '.ref_type')

if [ ! "${REF_TYPE}" == "tag" ]; then
    echo "Not a tag, skipping"
    exit 0
fi

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

    # git config --global user.name "${GITHUB_ACTOR}"
    # git config --global user.email "${GITHUB_ACTOR}@users.noreply.github.com"
    # git checkout ${local_branch}
    # git reset --hard ${latest_tag}
    # git push --force origin ${local_branch}
done
