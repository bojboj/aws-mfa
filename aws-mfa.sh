#!/bin/bash

PROGRAM_NAME=$(basename "$0")

usage () {
  echo "$PROGRAM_NAME: usage: $PROGRAM_NAME [-p profile | --help]"
  return
}

profile=default-long-term

while [[ -n "$1" ]]; do
  case "$1" in
    -p | --profile)
      shift

      if [[ -n "$1" ]]; then
        profile="$1"
      fi

      ;;
    --help | *)
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
    exit 1
fi

echo -n "Enter your one time token: "
read token

mfa_serial=$(aws iam list-mfa-devices --profile="$profile" --query "MFADevices[0].SerialNumber" --output text)
echo "Using device: $mfa_serial, with token: $token."

if [[ -z "$mfa_serial" ]]; then
    echo "Error: Failed to get MFA device."
    exit 1
fi

credentials=$(aws sts get-session-token --profile="$profile" --serial-number "$mfa_serial" --token-code "$token")

if [ $? -ne 0 ]; then
    echo "Error: Failed to get session token."
    exit 1
fi

file=~/.aws/credentials
sed -i '/^\[default\]/,+4d' "$file" # Delete [default] and 4 lines below.
echo "[default]" >> "$file"
echo "aws_access_key_id=$(echo "$credentials" | grep -o '"AccessKeyId": "[^"]*"' | cut -d'"' -f4)" >> "$file"
echo "aws_secret_access_key=$(echo "$credentials" | grep -o '"SecretAccessKey": "[^"]*"' | cut -d'"' -f4)" >> "$file"
echo "aws_session_token=$(echo "$credentials" | grep -o '"SessionToken": "[^"]*"' | cut -d'"' -f4)" >> "$file"

expiration=$(echo "$credentials" | grep -o '"Expiration": "[^"]*"' | cut -d'"' -f4)
echo "expiration=$expiration" >> "$file"

echo "Credentials set. Expires at: $expiration."
