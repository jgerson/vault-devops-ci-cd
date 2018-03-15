#!/usr/bin/env bash
set -e

################################
##  Auth methods:
##  Userpass
##
################################

echo -e '\n ... Auth: Validate UserPass enabled'
OUTPUT=$(curl \
    --silent \
    --header "X-Vault-Token: $VAULT_TOKEN" \
    $VAULT_ADDR/v1/sys/auth)
if echo $OUTPUT | grep userpass > /dev/null; then
    echo SUCCESS - UserPass enabled
else
    echo FAIL - Could not find UserPass enabled
    #exit 1
fi

echo -e '\n ... Auth: Validate User "me" exists'
OUTPUT=$(curl \
    --silent \
    --header "X-Vault-Token: $VAULT_TOKEN" \
    $VAULT_ADDR/v1/auth/userpass/users/me)
if echo $OUTPUT | grep policies > /dev/null; then
    echo SUCCESS - User \"me\" exists
else
    echo FAIL - Could not find user \"me\"
    exit 1
fi

################################
##  Auth methods:
##  Github
##
################################

echo -e '\n ... Auth: Validate Github auth method enabled'
OUTPUT=$(curl \
    --silent \
    --header "X-Vault-Token: $VAULT_TOKEN" \
    $VAULT_ADDR/v1/sys/auth)
if echo $OUTPUT | grep github > /dev/null; then
    echo SUCCESS - Github enabled
else
    echo FAIL - Could not find Github enabled
    exit 1
fi

echo -e '\n ... Auth: Validate Github user "stenio123" registered'
OUTPUT=$(curl \
    --silent \
    --request LIST \
    --header "X-Vault-Token: $VAULT_TOKEN" \
    $VAULT_ADDR/v1/auth/github/map/users)
if echo $OUTPUT | grep stenio123 > /dev/null; then
    echo SUCCESS - Github user \"stenio123\" registered
else
    echo FAIL - Could not find record for Github user \"stenio123\"
    exit 1
fi

echo -e '\n ... Auth: Validate Github team "dev" registered'
OUTPUT=$(curl \
    --silent \
    --request LIST \
    --header "X-Vault-Token: $VAULT_TOKEN" \
    $VAULT_ADDR/v1/auth/github/map/teams)
if echo $OUTPUT | grep dev > /dev/null; then
    echo SUCCESS - Github team \"dev\" registered
else
    echo FAIL - Could not find record for Github team \"dev\"
    exit 1
fi
################################
##  Auth methods:
##  LDAP
##
################################
echo -e '\n ... Auth: Validate LDAP auth method enabled'
OUTPUT=$(curl \
    --silent \
    --header "X-Vault-Token: $VAULT_TOKEN" \
    $VAULT_ADDR/v1/sys/auth)
if echo $OUTPUT | grep ldap > /dev/null; then
    echo SUCCESS - LDAP enabled
else
    echo FAIL - Could not find LDAP enabled
    exit 1
fi

echo -e '\n ... Auth: LDAP group "dev" registered'
OUTPUT=$(curl \
    --silent \
    --request LIST \
    --header "X-Vault-Token: $VAULT_TOKEN" \
    $VAULT_ADDR/v1/auth/ldap/groups)
if echo $OUTPUT | grep dev > /dev/null; then
    echo SUCCESS - LDAP group \"dev\" registered
else
    echo FAIL - Could not find record for LDAP group \"dev\"
    exit 1
fi

echo -e '\n ... Auth: LDAP group "dev" associated with "app1-readonly-dev" policy'
OUTPUT=$(curl \
    --silent \
    --request GET \
    --header "X-Vault-Token: $VAULT_TOKEN" \
    $VAULT_ADDR/v1/auth/ldap/groups/dev)
if echo $OUTPUT | grep app1-readonly-dev > /dev/null; then
    echo SUCCESS - LDAP group \"dev\" associated with \"app1-readonly-dev\" policy
else
    echo FAIL - LDAP group \"dev\" not associated with \"app1-readonly-dev\" policy
    exit 1
fi

################################
##  Dynamic Secrets:
##  Database (postgres)
##
################################

echo -e '\n ... Database: Validate Database mounted'
OUTPUT=$(curl \
    --silent \
    --request GET \
    --header "X-Vault-Token: $VAULT_TOKEN" \
    $VAULT_ADDR/v1/sys/mounts)
if echo $OUTPUT | grep database > /dev/null; then
    echo SUCCESS - database mounted
else
    echo FAIL - Could not find database mounted
    exit 1
fi

echo -e '\n ... Database: Validate Dev-Postgres configured'
OUTPUT=$(curl \
    --silent \
    --request GET \
    --header "X-Vault-Token: $VAULT_TOKEN" \
    $VAULT_ADDR/v1/database/config/dev-postgres)
if echo $OUTPUT | grep "\"plugin_name\":\"postgresql-database-plugin\"" > /dev/null; then
    echo SUCCESS - database mounted
else
    echo FAIL - Could not find database mounted
    exit 1
fi

echo -e '\n ... Database: Validate readonly role exists'
OUTPUT=$(curl \
    --silent \
    --request LIST \
    --header "X-Vault-Token: $VAULT_TOKEN" \
    $VAULT_ADDR/v1/database/roles)
if echo $OUTPUT | grep readonly > /dev/null; then
    echo SUCCESS - \"readonly\" role exists
else
    echo FAIL - Could not find role \"readonly\"
    exit 1
fi

echo -e '\n ... Postgres: Can create user'
# Creates user and stores information in $CREATE_OUTPUT
CREATE_OUTPUT=$(curl \
    --silent \
    --header "X-Vault-Token: $VAULT_TOKEN" \
    $VAULT_ADDR/v1/database/creds/readonly)
echo create output is $CREATE_OUTPUT
if echo $CREATE_OUTPUT | grep username > /dev/null; then
    echo SUCCESS - Able to dynamically create postgresql user
else
    echo FAIL - Could not dynamically create postgresql user
    exit 1
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
    exit 1
fi

echo -e '\n ... Policy: Validate postgresql policy written'
OUTPUT=$(curl \
    --silent \
    --request LIST \
    --header "X-Vault-Token: $VAULT_TOKEN" \
    $VAULT_ADDR/v1/sys/policies/acl)
if echo $OUTPUT | grep "postgresql-readonly" > /dev/null; then
    echo SUCCESS - Policy postgresql-readonly enabled
else
    echo FAIL - Could not find policy postgresql-readonly
    exit 1
fi

################################
##  Policies:
##  
##
################################

echo -e '\n ... Policies are registered'
OUTPUT=$(curl \
    --silent \
    --request LIST \
    --header "X-Vault-Token: $VAULT_TOKEN" \
    $VAULT_ADDR/v1/sys/policies/acl)
for f in $(ls ../data/sys/policy/*.json); do
    # Removes file extension
    p=${f%.json}
    # Removes path
    p=${p##*/}
    if echo $OUTPUT | grep "$p" > /dev/null; then
        echo SUCCESS - Policy "$p" registered
    else
        echo FAIL - Could not find policy "$p"
        exit 1
    fi
done