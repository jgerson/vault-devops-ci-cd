#!/usr/bin/env bash
set -e

shopt -s nullglob

function provision() {
  set +e
  pushd "$1" > /dev/null
  for f in $(ls "$1"/*.json); do
    p="$1/${f%.json}"
    echo "Provisioning $p"
    echo running curl --location --fail --header "X-Vault-Token: ${VAULT_TOKEN}" --data @"${f}" "${VAULT_ADDR}/v1/${p}"
    curl  --location --fail --header "X-Vault-Token: ${VAULT_TOKEN}" --data @"${f}" "${VAULT_ADDR}/v1/${p}"
  done
  popd > /dev/null
  set -e
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

echo database is `cat ../data/database/config/postgres-dev.json`

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
provision database/config/
provision database/roles
provision auth/userpass/users
provision secret/app1/dev
provision secret/app1/prod
provision secret/app2/dev
provision secret/app2/prod
popd > /dev/null

echo "Restoring config files"
cat templates/postgres-dev.json > ../data/database/config/postgres-dev.json
