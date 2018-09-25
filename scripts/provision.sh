#!/usr/bin/env bash
set -e

shopt -s nullglob

###### REST API requests

# Note: does not support namespaces named 'data' because of the way bash logic is written.
##
# $1 => path to be provisioned
# 
##
function configure_namespaces() {
    for namespace in $(find $1 -type d -name data | sed -e 's/data//g'); do
        echo ">>>>>>>>>>>>>>>>>> Configuring namespace: $namespace"
        echo ">>>>> Prepare templates for $namespace"
        prepare_templates $namespace
        echo ">>>>> Configure $namespace"
        configure $namespace
    done
}

##
# $1 => path to be provisioned
# $2 => namespace
##
function provision() {
  set +e
  pushd "$1" > /dev/null
  for f in $(ls "$1"/*.json); do
    p="$1/${f%.json}"
    echo "running curl  --header \"X-Vault-Token: ${VAULT_TOKEN}\" --header \"X-Vault-Namespace: $2\" --data @\"${f}\" \"${VAULT_ADDR}/v1/${p}\""
    curl --header "X-Vault-Token: ${VAULT_TOKEN}" --header "X-Vault-Namespace: $2" --data @"${f}" "${VAULT_ADDR}/v1/${p}"
  done
  popd > /dev/null
  set -e
}

##
# $1 => path to be provisioned
# $2 => namespace
##
function new_value() {
  set +e
  pushd "$1" > /dev/null
  for f in $(ls "$1"/*.json); do
    p="$1/${f%.json}"
    key=$(basename "${f%.json}")
    if get_value_list $1 $2 | grep $key > /dev/null; then
        echo "> Value exists at $p, skipping ..."
    else
        echo "> No value found at $p, provisioning ..."
        curl  --location --silent --fail --header "X-Vault-Token: ${VAULT_TOKEN}" --header "X-Vault-Namespace: $2" --data @"${f}" "${VAULT_ADDR}/v1/${p}"
    fi
  done
  popd > /dev/null
  set -e
}

# TODO make prettier bash
# This was needed because couldn't assign the output of a command to a var when inside a function
##
# $1 => path to be provisioned
# $2 => namespace
##
function get_value_list() {
    curl --silent --request LIST --header "X-Vault-Token: ${VAULT_TOKEN}" --header "X-Vault-Namespace: $2" ${VAULT_ADDR}/v1/$1
}

###### Validate Environment and prepare template files
##
# $1 => Namespace
# 
##
function prepare_templates() {
    namespace_path=$1

    # This will look into de database/config folder of each Namespace.
    # Template files:
    #   Ensure that the config file matches a file existing in the scripts/templates folder
    #   This allows you to use same templates on multiple Namespaces
    # Variables: 
    #   Connection string values should be set in environment variables or en.local 
    #   Child namespaces should not use "/" in the variable name
    #   Check example in scripts/.env.local.example
    if [ -d "$namespace_path/data/database/config/" ]; then
        echo "Applying env variables to config files"
        for f in $(ls "$namespace_path"data/database/config/*.json); do
            file_path="$namespace_path/${f%.json}"
            key=$(basename "${f%.json}")
            # Remove path prefix
            name=${namespace#*../namespaces/}
            # Remove "/" from namespace
            name=${name//\/}
            DB_USERNAME=${name}_${key}_DB_USERNAME
            DB_PASSWORD=${name}_${key}_DB_PASSWORD
            DB_URL=${name}_${key}_DB_URL

            sed -e "s/DATABASE_CONNECTION_STRING/${!DB_USERNAME}:${!DB_PASSWORD}@${!DB_URL}/g" \
            templates/$key.json > $f
        done
    fi 
}

###### Configure Vault endpoints
##
# $1 => namespace path
# 
##
function configure() {
    pushd $1/data >/dev/null
    namespace_path=$1
    # Remove path prefix
    name=${namespace#*../namespaces/}
    name=${name%/}
    if [ "$name" == "root" ]; then 
        name=""
    else
    # Ensure Namespace exists
        curl --header "X-Vault-Token: ${VAULT_TOKEN}" \
        --request POST \
        ${VAULT_ADDR}/v1/sys/namespaces/$name
    fi
    
    # Only provisions if folder exists in Namespace
    [ -d "sys/auth" ] && provision sys/auth $name
    [ -d "sys/policy" ] && provision sys/policy $name
    [ -d "sys/mounts" ] && provision sys/mounts $name
    [ -d "database/config" ] && provision database/config $name
    [ -d "database/roles" ] && provision database/roles $name
    [ -d "auth/github" ] && provision auth/github $name
    [ -d "auth/github/map/teams" ] && provision auth/github/map/teams $name
    [ -d "auth/github/map/users" ] && provision auth/github/map/users $name
    [ -d "auth/ldap" ] && provision auth/ldap $name
    [ -d "auth/ldap/groups" ] && provision auth/ldap/groups $name

    # Values that are only written if they don't already exist
    echo "Provisioning user/password stubs ..."
    [ -d "auth/userpass/users" ] && new_value auth/userpass/users
    echo "Provisioning secret stubs ..."
    for f in $(find secret -name '*.json'); do 
        p=$(dirname "${f}")
        new_value "$p" "$name"
    done
    
    popd > /dev/null

    echo "Restoring config files to remove secrets"
    [ $name = "" ] && name="root" 
    restore $name
}

###### Cleanup to remove secrets from code
##
# $1 => Namespace path
# 
##
function restore() {
    if [ -d ../namespaces/$namespace_path/data/database/config ]; then
        for file_path in $(find ../namespaces/$namespace_path/data/database/config/ -name '*.json'); do 
            filename=$(basename "${file_path}")
            cat templates/$filename > $file_path
        done
    fi
}

echo "-------------------------- Verifying Vault is unsealed"
OUTPUT=$(curl \
    --silent \
    $VAULT_ADDR/v1/sys/seal-status)

if echo $OUTPUT | grep "\"sealed\":false" > /dev/null; then
    echo SUCCESS - Vault is unsealed
else
    echo FAIL - Vault is sealed. Please unseal for provisioning and tests
    exit 1
fi


echo "-------------------------- Setting env variables"
# If not on CircleCI, apply env vars (for testing locally)
if [ -z "$CIRCLECI" ]; then
    echo "Applying local env vars"
    set -a
    [ -f .env.local ] && . .env.local
    set +a
fi

echo "-------------------------- Configuring namespaces"
configure_namespaces ../namespaces
