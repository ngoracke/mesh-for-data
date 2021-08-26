#!/bin/bash
server_url="$VAULT_SERVER/v1/auth/approle/login"

response=`curl -w "%{http_code}" -X POST --data "{\"role_id\":\"$VAULT_ROLE_ID\",\"secret_id\":\"$VAULT_SECRET_ID\"}" $server_url`
http_code=${response: -3}
if [[ "$http_code" -eq "200" ]]
then
	data=${response%???}
    client_token=$(echo $data | jq -r '.auth.client_token')
else
	exit 1
fi

response=`curl -w "%{http_code}" -X GET -H "X-Vault-Token:$client_token" $VAULT_SERVER/v1/$VAULT_PATH`
http_code=${response: -3}
if [[ "$http_code" -ne "200" ]]
then
	exit 1
fi

data=${response%???}
pg_certificate='postgres-DEV.crt'
echo $data | jq -r '.data.pg_certificate' | base64 --decode > $pg_certificate
# oc cp postgres-DEV.crt workspace-0:/workspace/source/postgres-DEV.crt

maven_settings='settings.xml'
echo $data | jq -r '.data.maven_settings' | base64 --decode > $maven_settings
# oc cp settings.xml workspace-0:/workspace/source/settings.xml

bootstrap_sensitive_config='bootstrap-sensitive-config.properties'
echo $data | jq -r '.data.bootstrap_sensitive_config' | base64 --decode > $bootstrap_sensitive_config
# oc cp bootstrap-sensitive-config.properties workspace-0:/workspace/source/bootstrap-sensitive-config.properties