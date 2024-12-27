#!/usr/bin/env sh
# shellcheck disable=SC2034
dns_mijnhost_info='mijn.host
Domains: mijn.host
Site: mijn.host
Docs: https://mijn.host/api/doc/
Options:
 MIJNHOST_API_KEY API Key
'

########  Public functions ###################### Constants for your mijn-host API
MIJNHOST_API="https://mijn.host/api/v2"

# Add TXT record for domain verification
dns_mijnhost_add() {
  fulldomain=$1
  txtvalue=$2

  MIJNHOST_API_KEY="${MIJNHOST_API_KEY:-$(_readaccountconf_mutable MIJNHOST_API_KEY)}"
  if [ -z "$MIJNHOST_API_KEY" ]; then
    MIJNHOST_API_KEY=""
    _err "You haven't specified mijn-host API key yet."
    _err "Please set it and try again."
    return 1
  fi

  # Save the API key for future use
  _saveaccountconf_mutable MIJNHOST_API_KEY "$MIJNHOST_API_KEY"

  _debug "First detect the root zone"
  if ! _get_root "$fulldomain"; then
    _err "Invalid domain"
    return 1
  fi

  _debug _sub_domain "$_sub_domain"
  _debug _domain "$_domain"

  _debug "Add TXT record"

  # Build the payload for the API
  data="{\"type\":\"TXT\",\"name\":\"$fulldomain.\",\"value\":\"$txtvalue\",\"ttl\":300}"

  export _H1="API-Key: $MIJNHOST_API_KEY"
  export _H2="Content-Type: application/json"

  # Construct the API URL
  api_url="$MIJNHOST_API/domains/$_domain/dns"

  # Getting previous records
  get_response="$(_get "$api_url" "" "120")"
  records=$(echo "$get_response" | _egrep_o '"records":\[.*\]' | sed 's/"records"://')

  _debug "Current records" "$records"

  # Updating the records
  updated_records=$(echo "$records" | sed -E "s/\]( *$)/,$data\]/")

  _debug "Updated records" "$updated_records"

  # data
  data="{\"records\": $updated_records}"

  _debug "json data add_dns PUT call:" "$data"

  # Use the _post method to make the API request
  response="$(_post "$data" "$api_url" "" "PUT")"

  _debug "Response to PUT dns_add" "$response"

  if ! _contains "$response" "200"; then
    _err "Error adding TXT record: $response"
    return 1
  fi

  _info "TXT record added successfully"
  return 0
}

# Remove TXT record after verification
dns_mijnhost_rm() {
  fulldomain=$1
  txtvalue=$2

  MIJNHOST_API_KEY="${MIJNHOST_API_KEY:-$(_readaccountconf_mutable MIJNHOST_API_KEY)}"
  if [ -z "$MIJNHOST_API_KEY" ]; then
    MIJNHOST_API_KEY=""
    _err "You haven't specified mijn-host API key yet."
    return 1
  fi

  _debug "First detect the root zone"
  if ! _get_root "$fulldomain"; then
    _err "Invalid domain"
    return 1
  fi

  _debug "Removing TXT record" "$txtvalue"

  # Build the payload for the API
  export _H1="API-Key: $MIJNHOST_API_KEY"
  export _H2="Content-Type: application/json"

  # Construct the API URL
  api_url="$MIJNHOST_API/domains/$_domain/dns"

  # Get current records
  get_response="$(_get "$api_url" "" "120")"

  _debug "Get current records response:" "$get_response"

  records=$(echo "$get_response" | _egrep_o '"records":\[.*\]' | sed 's/"records"://')

  _debug "Current records:" "$records"

  updated_records=$(echo "$records" | sed -E "s/\{[^}]*\"value\":\"$txtvalue\"[^}]*\},?//g" | sed 's/,]/]/g')

  _debug "Updated records:" "$updated_records"

  # Build the new payload
  data="{\"records\": $updated_records}"

  # Use the _put method to update the records
  response="$(_post "$data" "$api_url" "" "PUT")"

  _debug "Response to PUT dns_rm:" "$response"

  if ! _contains "$response" "200"; then
    _err "Error updating TXT record: $response"
    return 1
  fi

  _info "TXT record removed successfully"
  return 0
}

# Helper function to detect the root zone
_get_root() {
  domain=$1

  # Get all domains
  export _H1="API-Key: $MIJNHOST_API_KEY"
  export _H2="Content-Type: application/json"

  # Construct the API URL
  api_url="$MIJNHOST_API/domains"

  # Get current records
  response="$(_get "$api_url" "" "120")"

  if ! _contains "$response" "200"; then
    _err "Error listing domains: $response"
    return 1
  fi

  # Extract root domains from response
  rootDomains=$(echo "$response" | _egrep_o '"domain":"[^"]*"' | sed -E 's/"domain":"([^"]*)"/\1/')

  _debug "Root domains:" "$rootDomains"

  for rootDomain in $rootDomains; do
    if _contains "$domain" "$rootDomain"; then
      _domain="$rootDomain"
      _sub_domain=$(echo "$domain" | sed "s/.$rootDomain//g")

      _debug "Found root domain" "$_domain" "and subdomain" "$_sub_domain" "for" "$domain"

      return 0
    fi
  done

  return 1
}
