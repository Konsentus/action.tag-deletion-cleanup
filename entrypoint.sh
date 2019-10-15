#!/bin/bash -l

# check whether a string ($1) is in array ($2) using a grep pattern-matching search
# eg $2="foo/* hello/* test", $1=foo/bar (success), $1=hello/world (success), $1=test123 (fail)
is_in_pattern_list() {
    find=$1
    shift
    list=("$@")

    for pattern in "${list[@]}"; do
        if echo "$find" | grep -qe "$pattern"; then
           return 0
        fi
    done

    return 1
}

generate_branch_protection_from_result() {
    local original=$1

    local result=$(jq -n \
    --argjson required_status_checks_strict "$(echo -E $original | jq '.required_status_checks.strict')" \
    --argjson required_status_checks_contexts "[$(echo -E $original | jq '.required_status_checks.contexts[]?' -c | tr '\n' ',' | sed 's/,$//')]" \
    --argjson enforce_admins_enabled "$(echo -E $original | jq '.enforce_admins.enabled')" \
    --argjson required_pull_request_reviews_dismissal_restrictions_users "[$(echo -E $original | jq '.required_pull_request_reviews.dismissal_restrictions.users[]?.login' -c | tr '\n' ',' | sed 's/,$//')]" \
    --argjson required_pull_request_reviews_dismissal_restrictions_teams "[$(echo -E $original | jq '.required_pull_request_reviews.dismissal_restrictions.teams[]?.login' -c | tr '\n' ',' | sed 's/,$//')]" \
    --argjson required_pull_request_reviews_dismiss_stale_reviews "$(echo -E $original | jq '.required_pull_request_reviews.dismiss_stale_reviews')" \
    --argjson required_pull_request_reviews_require_code_owner_reviews "$(echo -E $original | jq '.required_pull_request_reviews.require_code_owner_reviews')" \
    --argjson required_pull_request_reviews_required_approving_review_count "$(echo -E $original | jq '.required_pull_request_reviews.required_approving_review_count')" \
    --argjson restrictions_users "[$(echo -E $original | jq '.restrictions.users[]?.login' -c | tr '\n' ',' | sed 's/,$//')]" \
    --argjson restrictions_teams "[$(echo -E $original | jq '.restrictions.teams[]?.slug' -c | tr '\n' ',' | sed 's/,$//')]" \
    --argjson restrictions_apps "[$(echo -E $original | jq '.restrictions.apps[]?.slug' -c | tr '\n' ',' | sed 's/,$//')]" \
    '{
        "required_status_checks": {
            "strict": $required_status_checks_strict,
            "contexts": $required_status_checks_contexts

        },
        "enforce_admins": $enforce_admins_enabled,
        "required_pull_request_reviews": {
            "dismissal_restrictions": {
            "users": $required_pull_request_reviews_dismissal_restrictions_users,
            "teams": $required_pull_request_reviews_dismissal_restrictions_teams
            },
            "dismiss_stale_reviews": $required_pull_request_reviews_dismiss_stale_reviews,
            "require_code_owner_reviews": $required_pull_request_reviews_require_code_owner_reviews,
            "required_approving_review_count": $required_pull_request_reviews_required_approving_review_count
        },
        "restrictions": {
            "users": $restrictions_users,
            "teams": $restrictions_teams,
            "apps": $restrictions_apps
        }
    }')

    if [ "$?" -ne 0 ]; then
        echo "Error when attempting to generate branch protection"
        exit 2
    fi

    echo $result
}

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
IGNORED_BRANCHES=(${INPUT_IGNORE_BRANCHES})

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

    # skip ignored branches
    if is_in_pattern_list $local_branch "${IGNORED_BRANCHES[@]}"; then
        continue;
    fi

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

    # github actions prevents itself from modifying actions, so if there have been changes to any actions
    # between the tags, we need to preserve the current version, and not revert!
    echo "${branch} : copy .github to temp location"
    cp -a .github /tmp/

    echo "${branch} : git checkout ${local_branch}"
    git checkout ${local_branch}
    # to revert the branch back to the last tag, we need to reset the branch and force push
    echo "${branch} : git reset --hard ${latest_tag}"
    git reset --hard ${latest_tag}

    echo "${branch} : move .github back over"
    rm -rf .github
    mv /tmp/.github .

    echo "${branch} : git add ."
    git add .

    if [ -n "$(git status --porcelain)" ]; then
        echo "${branch} : git commit -m 'Overlay current .github folder'"
        git commit -m 'Overlay current .github folder'
    else
        echo "${branch} : No changes detected to .github, bypassing commit"
    fi

    # todo: disable/reneable branch protection

    current_protection=$(hub api repos/${GITHUB_REPOSITORY}/branches/${branch}/protection)
    current_protection_status=$?

    if [ "$current_protection_status" -ne "0" ]; then
        echo "${branch} : Remove branch protection"
        hub api -X DELETE repos/${GITHUB_REPOSITORY}/branches/${branch}/protection
    fi

    echo "${branch} : git push --force ${remote_repo} ${local_branch}"
    git push --force ${remote_repo} ${local_branch}

    if [ "$current_protection_status" -ne "0" ]; then
        echo "${branch} : Re-enable branch protection"
        echo $(generate_branch_protection_from_result ${current_protection}) | \
            hub api -X PUT repos/${GITHUB_REPOSITORY}/branches/${branch}/protection --input -
    fi
done

# todo:
# 1. disable/re-enable branch protection
# 2. what happens to branches that have been hotfixed ... wont they also be reset (unintentionally)?
