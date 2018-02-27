#!/usr/bin/env bash
set -e

echo -e '\n ... Auth: Validate UserPass enabled'
if vault read sys/auth | grep userpass > /dev/null; then
    echo SUCCESS - UserPass enabled
else
    echo FAIL - Could not find UserPass enabled
fi

echo -e '\n ... Auth: User "me" exists'
AUTH_OUTPUT=$(curl \
    --silent \
    --header "X-Vault-Token: $VAULT_TOKEN" \
    $VAULT_ADDR/v1/auth/userpass/users/me)
if echo $AUTH_OUTPUT | grep policies > /dev/null; then
    echo SUCCESS - User \"me\" exists
else
    echo FAIL - Could not find user \"me\"
fi

echo -e '\n ... Postgres: Validate Postgresql mounted'
if vault read /sys/mounts | grep postgresql > /dev/null; then
    echo SUCCESS - postgresql mounted
else
    echo FAIL - Could not find postgresql mounted
fi

echo -e '\n ... Postgres: Can create user'
# Creates user and stores information in $CREATE_OUTPUT
CREATE_OUTPUT=$(curl \
    --silent \
    --header "X-Vault-Token: $VAULT_TOKEN" \
    $VAULT_ADDR/v1/postgresql/creds/readonly)

 if echo $CREATE_OUTPUT | grep username > /dev/null; then
    echo SUCCESS - Able to dynamically create postgresql user
else
    echo FAIL - Could not dynamically create postgresql user
fi

echo -e '\n ... Postgres: Can revoke user'
# Retrieves lease_id from $CREATE_OUTPUT
LEASE_ID=$(echo $CREATE_OUTPUT| jq -r '.lease_id')
REVOKE_OUTPUT=$(curl  \
    --silent \
    --header "X-Vault-Token: $VAULT_TOKEN"  \
    --request PUT  \
    --data "{\"lease_id\": \"$LEASE_ID\"}" \
    $VAULT_ADDR/v1/sys/leases/revoke)
LOOKUP_LEASE=$(curl \
    --silent \
    --header "X-Vault-Token: $VAULT_TOKEN" \
    --request PUT \
    --data "{\"lease_id\": \"$LEASE_ID\"}" \
    $VAULT_ADDR/v1/sys/leases/lookup)
if echo $LOOKUP_LEASE | grep "invalid lease" > /dev/null; then
    echo SUCCESS - Dynamic postgresql user revoked
else
    echo FAIL - Could not revoke dynamic postgresql user
fi

echo -e '\n ... Policy: Validate postgresql policy written'
if vault list sys/policies/acl | grep 'postgresql-readonly' > /dev/null; then
    echo SUCCESS - Policy postgresql-readonly enabled
else
    echo FAIL - Could not find policy postgresql-readonly
fi