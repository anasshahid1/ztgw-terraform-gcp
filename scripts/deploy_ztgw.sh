#!/usr/bin/env bash
#
# deploy_ztgw.sh — Terraform external data source helper
#
# Authenticates to Zscaler OneAPI, deploys a GCP ZTGW via the REST API,
# polls until healthy, and returns JSON to Terraform.
#
# Input (via stdin JSON from Terraform external data source):
#   client_id, client_secret, vanity_domain, cloud,
#   gateway_name, gcp_region, location_name, iam_principal_email
#
# Output (JSON to stdout for Terraform):
#   gateway_id, gateway_name, region, health_status,
#   intercept_deployment_group, intercept_endpoint_groups_count
#

set -eo pipefail

# ---------------------------------------------------------------------------
# Read input JSON from Terraform
# ---------------------------------------------------------------------------
INPUT=$(cat)

CLIENT_ID=$(echo "$INPUT" | python3 -c "import sys,json; print(json.load(sys.stdin)['client_id'])")
CLIENT_SECRET=$(echo "$INPUT" | python3 -c "import sys,json; print(json.load(sys.stdin)['client_secret'])")
VANITY_DOMAIN=$(echo "$INPUT" | python3 -c "import sys,json; print(json.load(sys.stdin)['vanity_domain'])")
CLOUD=$(echo "$INPUT" | python3 -c "import sys,json; print(json.load(sys.stdin)['cloud'])")
GATEWAY_NAME=$(echo "$INPUT" | python3 -c "import sys,json; print(json.load(sys.stdin)['gateway_name'])")
GCP_REGION=$(echo "$INPUT" | python3 -c "import sys,json; print(json.load(sys.stdin)['gcp_region'])")
LOCATION_NAME=$(echo "$INPUT" | python3 -c "import sys,json; print(json.load(sys.stdin)['location_name'])")
IAM_PRINCIPAL=$(echo "$INPUT" | python3 -c "import sys,json; print(json.load(sys.stdin)['iam_principal_email'])")

# ---------------------------------------------------------------------------
# Derive URLs from cloud name
# ---------------------------------------------------------------------------
if [ "$CLOUD" = "zscaler" ]; then
    LOGIN_DOMAIN="zslogin.net"
elif [ "$CLOUD" = "zscalerbeta" ]; then
    LOGIN_DOMAIN="zsloginbeta.net"
elif [ "$CLOUD" = "zscalerthree" ]; then
    LOGIN_DOMAIN="zsloginthree.net"
elif [ "$CLOUD" = "zscalerone" ]; then
    LOGIN_DOMAIN="zsloginone.net"
elif [ "$CLOUD" = "zscalertwo" ]; then
    LOGIN_DOMAIN="zslogintwo.net"
else
    LOGIN_DOMAIN="zslogin.net"
fi

TOKEN_URL="https://${VANITY_DOMAIN}.${LOGIN_DOMAIN}/oauth2/v1/token"
BASE_URL="https://connector.${CLOUD}.net/api/v1"

# ---------------------------------------------------------------------------
# Authenticate
# ---------------------------------------------------------------------------
TOKEN_RESPONSE=$(curl -sk -X POST "$TOKEN_URL" \
    -H "Content-Type: application/x-www-form-urlencoded" \
    -d "grant_type=client_credentials&client_id=${CLIENT_ID}&client_secret=${CLIENT_SECRET}")

ACCESS_TOKEN=$(echo "$TOKEN_RESPONSE" | python3 -c "import sys,json; print(json.load(sys.stdin).get('access_token',''))" 2>/dev/null)

if [ -z "$ACCESS_TOKEN" ]; then
    echo '{"error": "Authentication failed"}' >&2
    exit 1
fi

AUTH_HEADER="Authorization: Bearer $ACCESS_TOKEN"

# ---------------------------------------------------------------------------
# Check if ZTGW already exists by name
# ---------------------------------------------------------------------------
EXISTING=$(curl -sk "$BASE_URL/ztGateway?platform=GCP" -H "$AUTH_HEADER")
EXISTING_ID=$(echo "$EXISTING" | python3 -c "
import sys, json
data = json.load(sys.stdin)
gateways = data if isinstance(data, list) else data.get('list', data.get('gateways', []))
for gw in gateways:
    if gw.get('name') == '${GATEWAY_NAME}':
        print(gw['id'])
        break
" 2>/dev/null || true)

if [ -n "$EXISTING_ID" ] && [ "$EXISTING_ID" != "" ]; then
    GATEWAY_ID="$EXISTING_ID"
else
    # -----------------------------------------------------------------------
    # Get location template ID
    # -----------------------------------------------------------------------
    TEMPLATES=$(curl -sk "$BASE_URL/locationTemplate" -H "$AUTH_HEADER")
    TEMPLATE_ID=$(echo "$TEMPLATES" | python3 -c "
import sys, json
data = json.load(sys.stdin)
templates = data if isinstance(data, list) else data.get('list', data.get('templates', []))
for t in templates:
    print(t['id'])
    break
" 2>/dev/null)

    if [ -z "$TEMPLATE_ID" ]; then
        echo '{"error": "Could not retrieve location template"}' >&2
        exit 1
    fi

    # -----------------------------------------------------------------------
    # Create ZTGW
    # -----------------------------------------------------------------------
    CREATE_PAYLOAD=$(python3 -c "
import json
region = '${GCP_REGION}'
az_ids = [region + '-a', region + '-b']
payload = {
    'name': '${GATEWAY_NAME}',
    'platform': 'GCP',
    'region': region,
    'availabilityZoneIds': az_ids,
    'provData': {
        'locationName': '${LOCATION_NAME}',
        'locationTemplate': {'id': ${TEMPLATE_ID}},
    }
}
iam = '${IAM_PRINCIPAL}'
if iam:
    payload['provData']['iamPrincipals'] = [{'type': 'USER', 'value': iam}]
print(json.dumps(payload))
")

    CREATE_RESPONSE=$(curl -sk -X POST "$BASE_URL/ztGateway" \
        -H "$AUTH_HEADER" \
        -H "Content-Type: application/json" \
        -d "$CREATE_PAYLOAD")

    GATEWAY_ID=$(echo "$CREATE_RESPONSE" | python3 -c "import sys,json; print(json.load(sys.stdin).get('id',''))" 2>/dev/null)

    if [ -z "$GATEWAY_ID" ]; then
        echo "$CREATE_RESPONSE" >&2
        exit 1
    fi
fi

# ---------------------------------------------------------------------------
# Poll for health status (up to 10 minutes)
# ---------------------------------------------------------------------------
MAX_WAIT=600
INTERVAL=15
ELAPSED=0

while [ $ELAPSED -lt $MAX_WAIT ]; do
    GW_RESPONSE=$(curl -sk "$BASE_URL/ztGateway/$GATEWAY_ID" -H "$AUTH_HEADER")
    HEALTH=$(echo "$GW_RESPONSE" | python3 -c "import sys,json; print(json.load(sys.stdin).get('healthStatus','UNKNOWN'))" 2>/dev/null)

    if [ "$HEALTH" = "HEALTHY" ]; then
        break
    fi

    sleep $INTERVAL
    ELAPSED=$((ELAPSED + INTERVAL))
done

# ---------------------------------------------------------------------------
# Validate health and intercept deployment group
# ---------------------------------------------------------------------------
if [ "$HEALTH" != "HEALTHY" ]; then
    echo "{\"error\": \"ZTGW $GATEWAY_ID did not reach HEALTHY status within ${MAX_WAIT}s (current: $HEALTH). Re-run terraform apply after the gateway is healthy.\"}" >&2
    exit 1
fi

IDG=$(echo "$GW_RESPONSE" | python3 -c "import sys,json; print(json.load(sys.stdin).get('interceptDeploymentGroup',''))" 2>/dev/null)

if [ -z "$IDG" ]; then
    echo "{\"error\": \"ZTGW $GATEWAY_ID is HEALTHY but interceptDeploymentGroup is not yet populated. Re-run terraform apply in a few minutes.\"}" >&2
    exit 1
fi

# ---------------------------------------------------------------------------
# Extract outputs
# ---------------------------------------------------------------------------
RESULT=$(echo "$GW_RESPONSE" | python3 -c "
import sys, json
gw = json.load(sys.stdin)
print(json.dumps({
    'gateway_id': str(gw.get('id', '')),
    'gateway_name': gw.get('name', ''),
    'region': gw.get('region', ''),
    'health_status': gw.get('healthStatus', 'UNKNOWN'),
    'intercept_deployment_group': gw.get('interceptDeploymentGroup', ''),
    'intercept_endpoint_groups_count': str(gw.get('interceptEndpointGroupsCount', '0'))
}))
")

echo "$RESULT"
