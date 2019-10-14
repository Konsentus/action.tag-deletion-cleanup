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

echo $JSON
printenv | grep GIT
printenv | grep INPUT

if [ ! "${REF_TYPE}" == "tag" ]; then
    echo "Not a tag, skipping"
    exit 0
fi

git config --global user.email "actions@github.com"
git config --global user.name "${GITHUB_ACTOR}"

# itterate through all branches in origin
# intent is to ensure the branch the tag was on has been reset back to the latest tag (ie code had been reverted)
# since the delete trigger doesnt inform us of the exact branch the tag was on, we need to apply to all branches
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

    # # github actions prevents itself from modifying actions, so if there have been changes to any actions
    # # between the tags, we need to preserve the current version, and not revert!
    # echo "${branch} : copy .github to temp location"
    # cp -a .github /tmp/

    # echo "${branch} : git checkout ${local_branch}"
    # git checkout ${local_branch}
    # # to revert the branch back to the last tag, we need to reset the branch and force push
    # echo "${branch} : git reset --hard ${latest_tag}"
    # git reset --hard ${latest_tag}

    # echo "${branch} : move .github back over"
    # rm -rf .github
    # mv /tmp/.github .

    # echo "${branch} : git add ."
    # git add .

    # if [ -n "$(git status --porcelain)" ]; then
    #     echo "${branch} : git commit -m 'Overlay current .github folder'"
    #     git commit -m 'Overlay current .github folder'
    # else
    #     echo "${branch} : No changes detected to .github, bypassing commit"
    # fi

    # echo "${branch} : git push --force ${remote_repo} ${local_branch}"
    # git push --force ${remote_repo} ${local_branch}
done

# todo:
# 1. disable/re-enable branch protection
# 2. what happens to branches that have been hotfixed ... wont they also be reset (unintentionally)?
