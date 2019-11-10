#!/bin/bash

############################################################
############################################################
################### Flags
############################################################
############################################################
shopt -s expand_aliases

############################################################
############################################################
################### Utils
############################################################
############################################################
function slugify() {
  echo "$1" | sed -r s/[^a-zA-Z0-9]+/-/g | sed -r 's/(-)\1+/-/g' | sed -r s/^-+\|-+$//g | tr A-Z a-z;
}

############################################################
############################################################
################### Prepare SSH
############################################################
############################################################
echo "------> Prepare SSH";
mkdir -p ~/.ssh;
touch ~/.ssh/known_hosts;
echo "$INPUT_SSH_KEY" > ~/.ssh/deployment;
chmod 600 ~/.ssh/known_hosts;
chmod 600 ~/.ssh/deployment;
chmod 700 ~/.ssh;
eval $(ssh-agent);
ssh-add ~/.ssh/deployment;
ssh-keyscan -t rsa $INPUT_SSH_HOST >> ~/.ssh/known_hosts;
alias dokku='ssh -o StrictHostKeyChecking=no -q -p $INPUT_SSH_PORT -A -tt $INPUT_SSH_USER@$INPUT_SSH_HOST -- dokku';

############################################################
############################################################
################### Prepare deployment name
############################################################
############################################################
echo "------> Prepare deployment names";
PROJECT_NAME=$(slugify $INPUT_PROJECT);
DEPLOYMENT_NAME=$GITHUB_REF;
DEPLOYMENT_NAME=${DEPLOYMENT_NAME#"refs/heads/"}
DEPLOYMENT_NAME=${DEPLOYMENT_NAME#"refs/tags/"}
DEPLOYMENT_NAME=$(slugify "$DEPLOYMENT_NAME");

if [[ "$DEPLOYMENT_NAME" == "master" ]]; then
  DEPLOYMENT_DOMAIN=$PROJECT_NAME.$INPUT_DOMAIN;
else
  DEPLOYMENT_DOMAIN=$DEPLOYMENT_NAME.$PROJECT_NAME.$INPUT_DOMAIN;
fi

DEPLOYMENT_NAME=$DEPLOYMENT_NAME.$PROJECT_NAME;

echo Deployment Name: $DEPLOYMENT_NAME;
echo Deployment Domain: $DEPLOYMENT_DOMAIN;

############################################################
############################################################
################### Prepare project
############################################################
############################################################
echo "------> Prepare project";
APP_EXISTS=$(dokku apps:exists "$DEPLOYMENT_NAME" 2>&1 | xargs || true);
echo $APP_EXISTS;
if [[ "$APP_EXISTS" == *"App does not exist"* ]]; then
    dokku apps:create "$DEPLOYMENT_NAME";
    dokku git:initialize "$DEPLOYMENT_NAME";
    dokku buildpacks:add --index 1 "$DEPLOYMENT_NAME" https://github.com/heroku/heroku-buildpack-php
    dokku config:set "$DEPLOYMENT_NAME" APP_ENV=prod;
    dokku config:set "$DEPLOYMENT_NAME" DOKKU_LETSENCRYPT_EMAIL=$INPUT_EMAIL;
    dokku domains:set "$DEPLOYMENT_NAME" "$DEPLOYMENT_DOMAIN";
fi

############################################################
############################################################
################### Actual deployment
############################################################
############################################################
echo "------> Deployment";
APP_LOCKED=$(dokku apps:locked "$DEPLOYMENT_NAME" 2>&1 | xargs || true);
echo $APP_LOCKED;
if [[ "$APP_LOCKED" = *"Deploy lock does not exist"* ]]; then
    dokku apps:lock "$DEPLOYMENT_NAME";
    git remote add deployment $INPUT_GIT_USER@$INPUT_GIT_HOST:$DEPLOYMENT_NAME;
    git push --force deployment HEAD:refs/heads/master;
    git remote remove deployment;
    dokku letsencrypt "$DEPLOYMENT_NAME";
    dokku apps:unlock "$DEPLOYMENT_NAME";
fi
