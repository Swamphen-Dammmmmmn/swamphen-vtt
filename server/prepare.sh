#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")"
if [[ $# != 1 || ! "$1" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]]; then
  echo 'Usage: ./prepare.sh PUBLIC_IP'
  exit 1
fi
IFS='.' read -r a b c d <<< "$1"
for octet in "$a" "$b" "$c" "$d"; do
  if (( 10#$octet > 255 )); then echo 'Invalid public IPv4 address'; exit 1; fi
done
if [[ -e .env || -e certs/private.key || -e certs/public.crt ]]; then
  echo 'Existing configuration retained; initialization refused.'
  exit 1
fi
umask 077
mkdir -p certs
secret=$(openssl rand -hex 32)
local_address=$(ip -4 route get 1.1.1.1 | awk '{for(i=1;i<=NF;i++)if($i=="src"){print $(i+1);exit}}')
if [[ -z "$local_address" ]]; then echo 'Cannot determine local relay interface'; exit 1; fi
printf 'PUBLIC_ADDRESS=%s\nLOCAL_ADDRESS=%s\nTURN_SECRET=%s\n' "$1" "$local_address" "$secret" > .env
openssl req -x509 -newkey rsa:3072 -sha256 -nodes -days 3650 \
  -keyout certs/private.key -out certs/public.crt \
  -subj '/CN=Purple Swamp Hen Relay' -addext "subjectAltName=IP:$1" \
  -addext 'basicConstraints=critical,CA:TRUE' >/dev/null 2>&1
# Only the public certificate is given to clients.
chmod 644 certs/public.crt
chown 65534:65534 certs certs/private.key
openssl x509 -in certs/public.crt -noout -fingerprint -sha256
