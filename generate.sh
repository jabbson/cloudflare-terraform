#!/usr/bin/env bash
set -euo pipefail

: "${CLOUDFLARE_API_TOKEN:?CLOUDFLARE_API_TOKEN must be set}"
: "${ZONE_ID:?ZONE_ID must be set}"
: "${ACCOUNT_ID:?ACCOUNT_ID must be set}"

auth_header="Authorization: Bearer ${CLOUDFLARE_API_TOKEN}"

# Load names already managed by dns_extra_records so we can exclude them from the generated pool
extra_names="[]"
if [[ -f dns_extra.auto.tfvars.json ]]; then
  extra_names="$(jq '[.dns_extra_records[].name] // []' dns_extra.auto.tfvars.json)"
fi

extra_tunnel_names="[]"
if [[ -f tunnels_extra.auto.tfvars.json ]]; then
  extra_tunnel_names="$(jq '[.tunnels_extra[].name] // []' tunnels_extra.auto.tfvars.json)"
fi

extra_emails="[]"
extra_rule_names="[]"
if [[ -f email_routing_extra.auto.tfvars.json ]]; then
  extra_emails="$(jq '[.email_routing_addresses_extra[].email] // []' email_routing_extra.auto.tfvars.json)"
  extra_rule_names="$(jq '[.email_routing_rules_extra[].name] // []' email_routing_extra.auto.tfvars.json)"
fi

echo "Fetching DNS records for zone ${ZONE_ID} ..."
dns_json="$(curl -fsS -H "${auth_header}" \
  "https://api.cloudflare.com/client/v4/zones/${ZONE_ID}/dns_records?per_page=500")"

# Tunnels endpoint varies a bit across CF surfaces; try the common one first, then fallback.
echo "Fetching tunnels for account ${ACCOUNT_ID} ..."
if tunnels_json="$(curl -fsS -H "${auth_header}" \
  "https://api.cloudflare.com/client/v4/accounts/${ACCOUNT_ID}/cfd_tunnel?per_page=500" 2>/dev/null)"; then
  :
else
  tunnels_json="$(curl -fsS -H "${auth_header}" \
    "https://api.cloudflare.com/client/v4/accounts/${ACCOUNT_ID}/zero_trust/tunnels?per_page=500")"
fi


echo "Fetching email routing rules/catch-all/addresses (zone ${ZONE_ID}) ..."
curl -fsS -H "${auth_header}" \
  "https://api.cloudflare.com/client/v4/zones/${ZONE_ID}/email/routing/rules?per_page=500" \
  > .email_rules.json

curl -fsS -H "${auth_header}" \
  "https://api.cloudflare.com/client/v4/zones/${ZONE_ID}/email/routing/rules/catch_all" \
  > .email_catchall.json

echo "Fetching email routing destination addresses (account ${ACCOUNT_ID}) ..."
curl -fsS -H "${auth_header}" \
  "https://api.cloudflare.com/client/v4/accounts/${ACCOUNT_ID}/email/routing/addresses?per_page=500" \
  > .email_addresses.json

jq -e '.success == true' .email_rules.json     >/dev/null
jq -e '.success == true' .email_catchall.json  >/dev/null
jq -e '.success == true' .email_addresses.json >/dev/null


echo "Writing email_routing.auto.tfvars.json ..."
jq -n \
  --slurpfile rules     .email_rules.json \
  --slurpfile catchall  .email_catchall.json \
  --slurpfile addresses .email_addresses.json \
  --argjson extra_emails "${extra_emails}" \
  --argjson extra_rule_names "${extra_rule_names}" \
  '{
    email_routing_addresses: (
      ($addresses[0].result // [])
      | map(select(.email | IN($extra_emails[]) | not))
      | map({ key: .id, value: { id: .id, email: .email }})
      | from_entries
    ),
    email_routing_rules: (
      ($rules[0].result // [])
      | map(select(.matchers | map(.type) | contains(["all"]) | not))
      | map(select(.name | IN($extra_rule_names[]) | not))
      | map({
          key: .id,
          value: {
            id: .id,
            name: .name,
            enabled: .enabled,
            priority: .priority,
            actions: .actions,
            matchers: .matchers
          }
        })
      | from_entries
    ),
    email_routing_catch_all: {
      enabled: ($catchall[0].result.enabled // false),
      name: ($catchall[0].result.name // null),
      actions: ($catchall[0].result.actions // []),
      matchers: ($catchall[0].result.matchers // [])
    }
  }' > email_routing.auto.tfvars.json


# Basic sanity checks
echo "${dns_json}" | jq -e '.success == true' >/dev/null
echo "${tunnels_json}" | jq -e '.success == true' >/dev/null

echo "Writing dns.auto.tfvars.json ..."
echo "${dns_json}" | jq \
  --arg zone_id "${ZONE_ID}" \
  --argjson extra_names "${extra_names}" \
  '{
    zone_id: $zone_id,
    dns_records: (
      .result
      | map(select(.name | IN($extra_names[]) | not))
      | map({
          key: .id,
          value: {
            id: .id,
            name: .name,
            type: .type,
            ttl: .ttl,
            proxied: .proxied,
            priority: .priority,
            comment: .comment,
            tags: .tags
          }
          +
          (if (.content? and (.content|type=="string") and (.content|length>0))
            then { content: .content }
            else {}
          end)
          +
          (if (.data? and (.data|type=="object"))
            then { data: .data }
            else {}
          end)
        })
      | from_entries
    )
  }' > dns.auto.tfvars.json

echo "Writing tunnels.auto.tfvars.json ..."
echo "${tunnels_json}" | jq \
  --arg account_id "${ACCOUNT_ID}" \
  --argjson extra_tunnel_names "${extra_tunnel_names}" \
  '{
    account_id: $account_id,
    tunnels: (
      .result
      | map(select(.name | IN($extra_tunnel_names[]) | not))
      | map({
          key: .id,
          value: {
            id: .id,
            name: .name,
            config_src: (.config_src // "cloudflare")
          }
        })
      | from_entries
    )
  }' > tunnels.auto.tfvars.json

echo "Writing imports.tf ..."
{
  echo "// Generated import blocks"
  echo

  # DNS imports: zone_id/record_id (exclude names managed by dns_extra_records)
  echo "${dns_json}" | jq -r --arg zone_id "${ZONE_ID}" --argjson extra_names "${extra_names}" '
    .result[]
    | select(.name | IN($extra_names[]) | not)
    | @text "import {\n  to = cloudflare_dns_record.this[\"\(.id)\"]\n  id = \"\($zone_id)/\(.id)\"\n}\n"
  '

  # Tunnel imports: account_id/tunnel_id (exclude tunnels_extra)
  echo "${tunnels_json}" | jq -r --arg account_id "${ACCOUNT_ID}" --argjson extra_tunnel_names "${extra_tunnel_names}" '
    .result[]
    | select(.name | IN($extra_tunnel_names[]) | not)
    | @text "import {\n  to = cloudflare_zero_trust_tunnel_cloudflared.this[\"\(.id)\"]\n  id = \"\($account_id)/\(.id)\"\n}\n"
  '

  # Email routing destination addresses (account_id/address_id) — exclude email_routing_addresses_extra
  jq -r --arg account_id "${ACCOUNT_ID}" --argjson extra_emails "${extra_emails}" '
    (.result // [])[]
    | select(.email | IN($extra_emails[]) | not)
    | @text "import {\n  to = cloudflare_email_routing_address.this[\"\(.id)\"]\n  id = \"\($account_id)/\(.id)\"\n}\n"
  ' .email_addresses.json

  # Email routing rules (zone_id/rule_id) — exclude catch-all and email_routing_rules_extra
  jq -r --arg zone_id "${ZONE_ID}" --argjson extra_rule_names "${extra_rule_names}" '
    (.result // [])
    | map(select(.matchers | map(.type) | contains(["all"]) | not))
    | map(select(.name | IN($extra_rule_names[]) | not))
    | .[]
    | @text "import {\n  to = cloudflare_email_routing_rule.this[\"\(.id)\"]\n  id = \"\($zone_id)/\(.id)\"\n}\n"
  ' .email_rules.json

  # Email routing catch-all (zone-scoped)
  cat <<EOF
import {
  to = cloudflare_email_routing_catch_all.this
  id = "${ZONE_ID}"
}

import {
  to = cloudflare_email_routing_settings.this
  id = "${ZONE_ID}"
}

EOF
} > imports.tf

# Cleanup
rm -f .email_rules.json .email_catchall.json .email_addresses.json

echo "Done."
echo "Next: terraform plan, then terraform apply"
