#!/bin/bash -l

printenv | grep GIT
echo '---'
cat $GITHUB_EVENT_PATH
