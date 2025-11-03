#!/bin/bash

PROGRAM_NAME=$(basename "$0")

usage () {
  echo "$PROGRAM_NAME: usage: $PROGRAM_NAME [-p profile]"
  return
}

profile=default

while [[ -n "$1" ]]; do
  case "$1" in
    -p | --profile)
      shift

      if [[ -n "$1" ]]; then
        profile="$1"
      fi

      ;;
    *)
      usage >&2
      exit 1

      ;;
  esac
  shift
done

if [ -n "$(aws configure get aws_access_key_id --profile="$profile" 2>/dev/null)" ]; then
    echo "Using $profile profile."
else
    echo "$profile profile is not configured."
fi

echo -n "Enter your one time token: "
read token

mfa_serial=$(aws iam list-mfa-devices --query "MFADevices[0].SerialNumber" --output text)
echo "Using device: $mfa_serial, with token: $token."

credentials=$(aws sts get-session-token --serial-number "$mfa_serial" --token-code "$token")

if [ $? -ne 0 ]; then
    echo "Error: Failed to get session token."
    exit 1
fi

export AWS_ACCESS_KEY_ID=$(echo "$credentials" | jq -r ".Credentials.AccessKeyId")
export AWS_SECRET_ACCESS_KEY=$(echo "$credentials" | jq -r ".Credentials.SecretAccessKey")
export AWS_SESSION_TOKEN=$(echo "$credentials" | jq -r ".Credentials.SessionToken")

expiration=$(echo "$credentials" | jq -r ".Credentials.Expiration")
echo "Temporary credentials set. Expires at: $expiration."