#!/bin/bash
# This tool retrieves all of the commits in a RH Downstream OPM Version.
# This can then be used to identify what upstream OPM version most closely aligns with it.

# Requirements:
#  Latest version of `oc`.  You can get it from:
#   https://mirror.openshift.com/pub/openshift-v4/clients/ocp/
#  jq
#   Used to parse the JSON payloads.
#  git
#   Used to find the commits from the operator-framework git repositories.

# Example usage:
# ./opminfo.sh 4.8.5 4.9.0
#  Shows all the upstream commits that were pulled into 4.9.0 since 4.8.5
#  To check for OLM insted of operator-registry, change all of the calls to oc adm info to filter on "operator-lifecycle-manager" instead of "operator-registry"

BASEDIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
GITDIR="$BASEDIR/temp/git"

#COMPONENT="operator-registry"
#COMPONENT="operator-lifecycle-manager"

UPSTREAM_GIT_REPO_PREFIX="$GITDIR/upstream"

DOWNSTREAM_GIT_REPO="$GITDIR/downstream"
DOWNSTREAM_GIT_REPO_OLM_ORIGIN="https://github.com/openshift/operator-framework-olm"

UPSTREAM_GIT_REPO_OLM="${UPSTREAM_GIT_REPO_PREFIX}-operator-lifecycle-manager"
UPSTREAM_GIT_REPO_OLM_ORIGIN="https://github.com/operator-framework/operator-lifecycle-manager"

UPSTREAM_GIT_REPO_REGISTRY="${UPSTREAM_GIT_REPO_PREFIX}-operator-registry"
UPSTREAM_GIT_REPO_REGISTRY_ORIGIN="https://github.com/operator-framework/operator-registry"

UPSTREAM_GIT_REPO_API="${UPSTREAM_GIT_REPO_PREFIX}-api"
UPSTREAM_GIT_REPO_API_ORIGIN="https://github.com/operator-framework/api"

# For 4.8 and later:
# - Retrieve the repo and commit for the current version of OPM
# - Retrieve the repo and commit for a previous version of OPM (optional)
# - Retrieve all of the downstream commit ids for the delta
# - For each downstream commit
#     - Pull out the Upstream details
#     - Retrieve the short description

OPM_BASE_VER="$1"
OPM_VER="$2"

function getTagsForCommit() {
  git tag --contains "$1" | tr '\n' ' '
}

function getFirstVersionTagForCommit() {
  tags=$(git tag --contains "$1")
  while read -r tag; do
    if [[ $tag = v* ]]; then
        echo "$tag"
      return
    fi
  done <<< "$tags"
}

if [ ! -z "$OPM_VER" ];then
  echo "Retrieving downstream commits between versions: $OPM_BASE_VER and $OPM_VER"
else
  echo "Retrieving all downstream commits up to version: $OPM_BASE_VER"
fi

# In 4.8, the downstream git repo is in a separate repository.
# In 4.0-4.7, the downsteram git repo is the same as upstream.

REFTAG=$(oc adm release info ${OPM_BASE_VER} --commits -o jsonpath='{.references.spec.tags[?(@.name=="operator-registry")].annotations}')

  # Example output
  # {
  #   "io.openshift.build.commit.id": "2b803dd1e5e3160b6a53ce4808079bddd72283e9",
  #   "io.openshift.build.commit.ref": "",
  #   "io.openshift.build.source-location": "https://github.com/openshift/operator-framework-olm"
  # }
OPM_VER_BASE_COMMIT_ID=$(echo $REFTAG | jq -r '.["io.openshift.build.commit.id"]')
OPM_VER_BASE_SOURCE_LOCATION=$(echo $REFTAG | jq -r '.["io.openshift.build.source-location"]')

if [ -z "$OPM_VER_BASE_COMMIT_ID" ];then
  echo "Tag not found for version: ${OPM_BASE_VER}"
  exit 1
fi

if [ ! -z "$OPM_VER" ];then
  REFTAG=$(oc adm release info ${OPM_VER} --commits -o jsonpath='{.references.spec.tags[?(@.name=="operator-registry")].annotations}')
  OPM_VER_COMMIT_ID=$(echo $REFTAG | jq -r '.["io.openshift.build.commit.id"]')
  OPM_VER_SOURCE_LOCATION=$(echo $REFTAG | jq -r '.["io.openshift.build.source-location"]')

  if [ -z "$OPM_VER_COMMIT_ID" ];then
    echo "Tag not found for version: ${OPM_VER}"
    exit 1
  fi
fi

if [ ! -z "$OPM_VER_COMMIT_ID" ];then
  echo "Commit range: ${OPM_VER_BASE_COMMIT_ID}-${OPM_VER_COMMIT_ID}"
  echo "Origin: $OPM_VER_SOURCE_LOCATION"
else
  echo "Commit: ${OPM_VER_BASE_COMMIT_ID}"
  echo "Origin: $OPM_VER_SOURCE_LOCATION"
fi

#rmdir -rf $GITDIR
mkdir -p $GITDIR &> /dev/null
cd $GITDIR

if [ -d "$DOWNSTREAM_GIT_REPO" ]
then
  cd $DOWNSTREAM_GIT_REPO
  git checkout master &> /dev/null
  git pull &> /dev/null
else
  git clone $OPM_VER_SOURCE_LOCATION $DOWNSTREAM_GIT_REPO &> /dev/null
fi

cd $GITDIR
if [ -d "$UPSTREAM_GIT_REPO_OLM" ]
then
  cd $UPSTREAM_GIT_REPO_OLM
  git checkout master &> /dev/null
  git pull &> /dev/null
else
  git clone $UPSTREAM_GIT_REPO_OLM_ORIGIN $UPSTREAM_GIT_REPO_OLM &> /dev/null
fi

cd $GITDIR
if [ -d "$UPSTREAM_GIT_REPO_REGISTRY" ]
then
  cd $UPSTREAM_GIT_REPO_REGISTRY
  git checkout master &> /dev/null
  git pull &> /dev/null
else
  git clone $UPSTREAM_GIT_REPO_REGISTRY_ORIGIN $UPSTREAM_GIT_REPO_REGISTRY &> /dev/null
fi

cd $GITDIR
if [ -d "$UPSTREAM_GIT_REPO_API" ]
then
  cd $UPSTREAM_GIT_REPO_API
  git checkout master &> /dev/null
  git pull &> /dev/null
else
  git clone $UPSTREAM_GIT_REPO_API_ORIGIN $UPSTREAM_GIT_REPO_API &> /dev/null
fi

# Retreive all of the downstream commits
#git log --format=%H 11b568e4ba69ff2a476370a463d089fcde85838d...2b803dd1e5e3160b6a53ce4808079bddd72283e9

if [ "$DOWNSTREAM_GIT_REPO_OLM_ORIGIN" != "$OPM_VER_BASE_SOURCE_LOCATION" ]; then
  # 4.6-4.7
  echo "Processing legacy pre-4.8 repository"
  UPSTREAM_REPO_NAME=$(echo ${OPM_VER_BASE_SOURCE_LOCATION##*/})
  DOWNSTREAM_GIT_REPO="${UPSTREAM_GIT_REPO_PREFIX}-${UPSTREAM_REPO_NAME}"

  cd $DOWNSTREAM_GIT_REPO
  upstreamTags=$(getTagsForCommit $OPM_VER_BASE_COMMIT_ID)
  if [ -z $OPM_VER_COMMIT_ID ]; then
    commitId=$(git log --format='%H' --no-merges $OPM_VER_BASE_COMMIT_ID)
  else
    commitId=$(git log --format='%H' --no-merges $OPM_VER_BASE_COMMIT_ID...$OPM_VER_COMMIT_ID)
  fi

  for commitId in ${DOWNSTREAM_COMMIT_IDS}; do
    # Show only the operator-registry and API entries, since this is where OPM lives
    if [ ! -z "$commitId" ];then
      upstreamTags=$(getTagsForCommit $commitId)
      echo $(git show -s --format='%h %s' -n 1 $commitId) "($upstreamTags)"
    fi
  done
 
else
  # 4.8+
  cd $DOWNSTREAM_GIT_REPO
  if [ -z $OPM_VER_COMMIT_ID ]; then
    DOWNSTREAM_COMMIT_IDS=$(git log --format=%H  --no-merges $OPM_VER_BASE_COMMIT_ID  | tr ' ' '\n' )
  else
    DOWNSTREAM_COMMIT_IDS=$(git log --format=%H  --no-merges $OPM_VER_BASE_COMMIT_ID...$OPM_VER_COMMIT_ID  | tr ' ' '\n' )
  fi
  # echo $DOWNSTREAM_COMMIT_IDS

  echo "Locating all upstream commits that match..."
  # For each commit grab it's upstream commit id.
  for DOWNSTREAM_COMMIT_ID in ${DOWNSTREAM_COMMIT_IDS}; do
    cd $DOWNSTREAM_GIT_REPO
    #echo "git show -s --format=%B -n 1 $DOWNSTREAM_COMMIT_ID | grep Upstream-commit  | awk '{print 2}'"

    commitInfo=$(git show -s --format=%B -n 1 $DOWNSTREAM_COMMIT_ID)

    # echo "git show -s --format=%B -n 1 $DOWNSTREAM_COMMIT_ID"
    # echo $commitInfo
    # Red Hat downstream commits use a special comment to tie the commit to an upstream commit.
    upstreamCommitId=$(echo "$commitInfo" | grep "Upstream-commit"  | awk '{print $2}')
    upstreamRepoName=$(echo "$commitInfo" | grep "Upstream-repository"  | awk '{print $2}')
    # echo "upstreamCommitId=$upstreamCommitId"
    # echo "upstreamRepoName=$upstreamRepoName"

    # Show only the operator-registry and API entries, since this is where OPM lives
    if [ ! -z "$upstreamCommitId" ] && [ ! -z "$upstreamRepoName" ];then
      if [ "$upstreamRepoName" = "operator-registry" ] || [ "$upstreamRepoName" = "api" ]; then
        upstreamGitRepoPath="${UPSTREAM_GIT_REPO_PREFIX}-${upstreamRepoName}"
        cd $upstreamGitRepoPath
        upstreamTags=$(getTagsForCommit $upstreamCommitId)
        echo "${upstreamRepoName}" $(git show -s --format='%h %s' -n 1 $upstreamCommitId) "($upstreamTags)"
      fi
    fi
  done
fi