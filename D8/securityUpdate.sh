#!/bin/bash
# Script expects emails to be passed along as paramters to notify about the state of the Security-Update
# bash ./securityUpdate.sh email@tonoti.fy anotheremail@tonoti.fy

set +e

updateTime=$(date +%Y%m%d-%H-%M-%S)
emails=$@
securityUserEmail="securityUser@ema.il"
securityUserName="Security User"
# this blacklist needs to contain the names of modules blacklisted,
# they are the the modules foldernames
blacklist=()
composerModuleNames=()

# Sends an Email to notify about the security-update-status
function sendEmailForUpdateStatus {
  mail -s "$1" ${emails[@]}
}

# Sends an email notifying that no Security-Update has been found.
function noUpdateFoundFunction {
    echo "Security-Update ran at $updateTime, no Updates found."|sendEmailForUpdateStatus "No Security-Update for Gopa-Intec"
}

# Sends an error notifying recipients that changes were not comittable.
function commitErrorHandling {
  exitStatus=$?
  if [[ $exitStatus -eq 1 ]] ; then
      noUpdateFoundFunction
  else
    # this is a special case of handleErrors().
    echo "Security-Update failed at $updateTime, git encountered problem."|sendEmailForUpdateStatus "Failed Security-Update for Gopa-Intec"
    exit $exitStatus
  fi
}

# Function for general error-handling.
# Terminates the script with the error-encountered
function handleErrors {
   exitStatus=$?
   echo "Security-Update failed at $updateTime"|sendEmailForUpdateStatus "Failed Security-Update Gopa-Intec"
   exit $exitStatus
}

# Function notifying recipients that the Security-Update went well.
function securityUpdateDone {
  echo "Security-Update successfully executed at $updateTime \n $composerModuleNames "|sendEmailForUpdateStatus "Successful Security-Update"
}

# Function deciding if a module is barred from upgrading.
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

trap handleErrors ERR

echo "Deploy new Artifact"
rm -fr dist||true
mkdir dist
# we expect the artifact we use for deployment to be present on the system already
tar xf archive.tar -C dist
rm archive.tar
pushd dist/web

echo "Importing Prod-DB"
../vendor/drush/drush/drush  sql-drop -y
# the DB-Dump needs to be put in place beforehand
cat  /tmp/securityDB.sql |../vendor/drush/drush/drush  sql-cli
rm  /tmp/securityDB.sql

#disabling trap because drush will throw a status-code 1 if it finds an update and wants to warn.
trap - ERR

echo "preparing to get update-message"
updateMessage=$(../vendor/drush/drush/drush pm:security -n  )
echo "prepare composer-packagenames"

for module in $(../vendor/bin/drush  pm:security --format=list --field=Name 2>/dev/null); do
  composerModuleNames+=($module)
done
cd ..

trap handleErrors ERR

echo "Prepping Git"
git checkout -b security
git config user.email $securityUserEmail
git config user.name $securityUserName

echo "Updating packages"

if [[ -n ${composerModuleNames[@]} ]]; then
  composer update ${composerModuleNames[@]}  --with-dependencies
  cd web/
  ../vendor/bin/drush updb -y
  ../vendor/bin/drush entup -y
  trap commitErrorHandling ERR
  cd ..
  git add .
  git commit -a -m "Security-Update ran successfully at $updateTime"
  # doing a force-push allows us to not having to worry about state.
  git push -u origin security -f
  securityUpdateDone
else
  noUpdateFoundFunction
fi
popd