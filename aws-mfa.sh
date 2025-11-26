#!/bin/bash

PROGRAM_NAME=$(basename "$0")

usage () {
  echo "$PROGRAM_NAME: usage: $PROGRAM_NAME [-p profile | --help]"
  return
}

info() {
  echo "$@"
}

error() {
  echo "$@" >&2
}

die() {
  error "$@"
  exit 1
}

# Extract value from the AWS STS JSON using grep/cut (keeps original behavior, no jq dependency)
extract_json_value() {
  # $1 = json, $2 = key
  echo "$1" | grep -o '"'"$2"'": "[^"]*"' | cut -d '"' -f4
}

profile=default-long-term

parse_args() {
  while [[ -n "$1" ]]; do
    case "$1" in
      -p|--profile)
        shift
        if [[ -n "$1" ]]; then
          profile="$1"
        fi
        ;;
      --help|-h)
        usage >&2
        exit 1
        ;;
      *)
        usage >&2
        exit 1
        ;;
    esac
    shift || true
  done
}

check_profile_configured() {
  local prof="$1"
  if [ -n "$(aws configure get aws_access_key_id --profile="$prof" 2>/dev/null)" ]; then
    info "Using $prof profile."
  else
    die "$prof profile is not configured."
  fi
}

prompt_token() {
  echo -n "Enter your one time token: "
  read token
  echo "$token"
}

get_mfa_serial() {
  local prof="$1"
  aws iam list-mfa-devices --profile="$prof" --query "MFADevices[0].SerialNumber" --output text 2>/dev/null
}

get_session_token() {
  local prof="$1"
  local serial="$2"
  local token="$3"
  aws sts get-session-token --profile="$prof" --serial-number "$serial" --token-code "$token"
}

write_credentials() {
  local credentials_json="$1"
  local file=~/.aws/credentials

  # Clear previous default section (original behavior: delete [default] and 4 lines below)
  sed -i '/^\[default\]/,+4d' "$file" 2>/dev/null || true

  local access_key secret_key session_token expiration
  access_key=$(extract_json_value "$credentials_json" AccessKeyId)
  secret_key=$(extract_json_value "$credentials_json" SecretAccessKey)
  session_token=$(extract_json_value "$credentials_json" SessionToken)
  expiration=$(extract_json_value "$credentials_json" Expiration)

  {
    echo "[default]"
    echo "aws_access_key_id=$access_key"
    echo "aws_secret_access_key=$secret_key"
    echo "aws_session_token=$session_token"
    echo "expiration=$expiration"
  } >> "$file"

  info "Credentials set. Expires at: $expiration."
}

main() {
  parse_args "$@"

  check_profile_configured "$profile"

  local token mfa_serial credentials
  token=$(prompt_token)

  mfa_serial=$(get_mfa_serial "$profile")
  info "Using device: $mfa_serial, with token: $token."

  if [[ -z "$mfa_serial" || "$mfa_serial" == "None" ]]; then
    die "Error: Failed to get MFA device."
  fi

  credentials=$(get_session_token "$profile" "$mfa_serial" "$token")
  if [ $? -ne 0 ] || [[ -z "$credentials" ]]; then
    die "Error: Failed to get session token."
  fi

  write_credentials "$credentials"
}

main "$@"
