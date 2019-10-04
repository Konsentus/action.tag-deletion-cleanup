#!/bin/bash -l

if [ -z $GITHUB_EVENT_PATH ] || [ ! -f $GITHUB_EVENT_PATH  ]; then
    echo "No file containing event data found. Cannot continue"
    exit 2
fi

JSON=$(cat $GITHUB_EVENT_PATH | jq)
REF=$(echo -E $JSON | jq -r '.ref')
REF_TYPE=$(echo -e $JSON | jq -r '.ref_type')

if [ ! "$REF_TYPE" == "tag" ]; then
    echo "Not a tag, skipping"
    exit 0
fi
echo $JSON
git branch -a --contains tags/${REF}
git rev-list -n 1 ${REF}
