#!/usr/bin/env bash
# Script expects emails to be passed along as paramters to notify about the state of the Security-Update
# bash ./securityUpdate.sh email@tonoti.fy anotheremail@tonoti.fy

set +e

updateTime=$(date +%Y%m%d-%H-%M-%S)
emails=$@
securityUserEmail="security@1xinternet.de"
securityUserName="Security User"
# this blacklist needs to contain the names of modules blacklisted,
# they are the the modules foldernames
blacklist=()
modulesToUpdate=()

# Sending an email using the systems mail-command.
# 1. Parameter is to be the subject of the email.
function sendEmailForUpdateStatus {
  mail -s "$1" ${emails[@]}
}

# Sends an email stating that no Sec-Updates have been found.
function noSecurityUpdateFound {
    echo "Security-Update ran at $updateTime, no Updates found."|sendEmailForUpdateStatus "No Security-Update found"
}

# Sends an email stating that no Sec-Updates have been found
# or that s.th. went wrong with committing the updates.
function noUpdatesCommitted {
 exitStatus=$?
  if [[ $exitStatus -eq 1 ]] ; then
      noSecurityUpdateFound
  else
    # this is a special case of handleErrors().
    echo "Security-Update failed at $updateTime, git encountered problem."|sendEmailForUpdateStatus "Failed Security-Update"
    exit $exitStatus
  fi
}

# A general method for Error-Handling.
# It sends an email and terminates the script with the
# errorcode encountered.
function handleErrors {
    exitStatus=$?
    echo "Security-Update failed at $updateTime"|sendEmailForUpdateStatus "Failed Security-Update"
    exit $exitStatus
}

# Sends an email notifying people that the Sec-Update went well.
function securityUpdateDone {
  # securityUpdateList is globally defined in function updateModules
  echo "Security-Update successfully executed at $updateTime \n $securityUpdateList "|sendEmailForUpdateStatus "Successful Security-Update"
}

# Function checking if the module encountered is blacklisted.
function isNotInBlacklist() {
  element=$1
  blacklist=$2

  for blackListedElement in $blacklist; do
    if [ $element == $blackListedElement ]; then
      return 1; # 1 is false in bash
    fi
  done

  return 0;# 0 is true in bash
}

# Function actually performing the update of security-modules
function updateModules() {
    drush rf # refreshing list of updates
    # drush returns a non-zero-status-code upon finding a core-update
    trap - ERR
    securityUpdateList=$(drush up --security-only -n)

    for moduleName in $(drush up --security-only --pipe); do
         if $(isNotInBlacklist $moduleName $blacklist); then
           modulesToUpdate+=($moduleName);
         fi
    done

    echo "Modules being updated"
    echo ${modulesToUpdate[@]}
    trap handleErrors ERR
    drush up -y ${modulesToUpdate[@]}
}

echo "Deploy new Artifact"
rm -fr dist||true
mkdir dist
# we expect the artifact we use for deployment to be present on the system already
tar xf archive.tar -C dist
rm archive.tar
pushd dist/web

pushd dist/
trap handleErrors ERR # only trapping errors here to ensure that git works propperly

echo "Prepping Git"
git config user.email $securityUserEmail
git config user.name $securityUserName
git config push.default simple
git checkout -b security

drush sql-drop -y
# The DB-Dump needs to be put into this location prior to executing this script
cat /tmp/SecurityJob.sql |drush sql-cli
rm /tmp/SecurityJob.sql
drush cc all
drush updatedb -y

echo "Running Security-update"
updateModules

# checking if we found modules to be updated.
if [[ -n ${modulesToUpdate[@]} ]]; then
  echo "Committing changes"
  trap noUpdatesCommitted ERR
  git add .
  git commit -a -m "Security-Update ran successfully at $updateTime"
  # doing a force-push allows us to not having to worry about state.
  git push -u origin security -f
  securityUpdateDone
else
  noSecurityUpdateFound
fi

popd
