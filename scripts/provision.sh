#!/usr/bin/env bash
set -e

shopt -s nullglob

function provision() {
  set +e
  pushd "$1" > /dev/null
  for f in $(ls "$1"/*.json); do
    p="$1/${f%.json}"
    echo "Provisioning $p"
    # echo running curl --location --fail --header "X-Vault-Token: ${VAULT_TOKEN}" --data @"${f}" "${VAULT_ADDR}/v1/${p}"
    curl  --location --silent --fail --header "X-Vault-Token: ${VAULT_TOKEN}" --data @"${f}" "${VAULT_ADDR}/v1/${p}"
  done
  popd > /dev/null
  set -e
}

function new_value() {
  set +e
  pushd "$1" > /dev/null
  for f in $(ls "$1"/*.json); do
    p="$1/${f%.json}"
    path=$(dirname "${f}")
    key=$(basename "${f%.json}")
    
    if get_value_list $1 | grep $key > /dev/null; then
        echo "> Value exists at $p, skipping ..."
    else
        echo "> No value found at $p, provisioning ..."
        curl  --location --silent --fail --header "X-Vault-Token: ${VAULT_TOKEN}" --data @"${f}" "${VAULT_ADDR}/v1/${p}"
    fi
  done
  popd > /dev/null
  set -e
}

function get_value_list() {
    curl --silent --request LIST --header "X-Vault-Token: ${VAULT_TOKEN}" ${VAULT_ADDR}/v1/$1
}

echo "If not on CircleCI, apply env vars (for testing locally)"
echo CircleCI is $CIRCLECI
if [ -z "$CIRCLECI" ]; then
    echo "Applying local env vars"
    source env.local
fi

echo "Applying env variables to config files"
sed -e "s/DATABASE_CONNECTION_STRING/$DB_USERNAME:$DB_PASSWORD@$DB_URL/g" \
  templates/postgres-dev.json > ../data/database/config/postgres-dev.json

echo "Verifying Vault is unsealed"
OUTPUT=$(curl \
    --silent \
    $VAULT_ADDR/v1/sys/seal-status)

if echo $OUTPUT | grep "\"sealed\":false" > /dev/null; then
    echo SUCCESS - Vault is unsealed
else
    echo FAIL - Vault is sealed. Please unseal for provisioning and tests
    exit 1
fi

pushd ../data >/dev/null
provision sys/auth
provision sys/mounts
provision sys/policy
provision database/config
provision database/roles
provision auth/github
provision auth/github/map/teams
provision auth/github/map/users
provision auth/ldap
provision auth/ldap/groups

# Values that are only written if they don't already exist
echo "Provisioning user/password stubs ..."
new_value auth/userpass/users
echo "Provisioning secret stubs ..."
for f in $(find secret -name '*.json'); do 
    p=$(dirname "${f}")
    new_value "$p"
done

popd > /dev/null

echo "Restoring config files"
cat templates/postgres-dev.json > ../data/database/config/postgres-dev.json
