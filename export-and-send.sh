#!/usr/bin/env bash
set -Eeuo pipefail
umask 077

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SELF="$DIR/$(basename "${BASH_SOURCE[0]}")"

[[ $EUID -eq 0 ]] || exec sudo -n "$SELF" "$@"

if [[ "${1:-}" != "--run" ]]; then
  DB_NAME="${1:?usage: export-and-send.sh <database>}"
  nohup setsid bash "$SELF" --run "$DB_NAME" >> "$DIR/export-and-send.log" 2>&1 &
  echo "Started in background (pid $!). Log: $DIR/export-and-send.log"
  exit 0
fi

DB_NAME="${2:?usage: export-and-send.sh <database>}"
source "$DIR/.env"

if ! command -v age >/dev/null; then
  echo "$(date -Is) installing age"
  apt-get update -qq
  apt-get install -y -qq age
fi

if ! command -v aws >/dev/null; then
  echo "$(date -Is) installing awscli"
  apt-get install -y -qq curl unzip
  ARCH="$(uname -m)"
  curl -fsS "https://awscli.amazonaws.com/awscli-exe-linux-${ARCH}.zip" -o /tmp/awscliv2.zip
  unzip -q -o /tmp/awscliv2.zip -d /tmp
  /tmp/aws/install --update
  rm -rf /tmp/aws /tmp/awscliv2.zip
fi

command -v mariadb-dump >/dev/null || { echo "mariadb-dump not found" >&2; exit 1; }

AWS_CONFIG_FILE="$(mktemp)"
CA_FILE="$(mktemp)"
NAME="${DB_NAME}_$(date +%Y%m%d_%H%M%S).sql.age"
TMP="/tmp/$NAME"
trap 'rm -f "$TMP" "$AWS_CONFIG_FILE" "$CA_FILE"' EXIT

printf '[default]\ns3 =\n    addressing_style = path\n' > "$AWS_CONFIG_FILE"
curl -fsS "$CA_URL" -o "$CA_FILE"

export AWS_CONFIG_FILE
export AWS_ACCESS_KEY_ID="$RUSTFS_ACCESS_KEY"
export AWS_SECRET_ACCESS_KEY="$RUSTFS_SECRET_KEY"
export AWS_DEFAULT_REGION="${RUSTFS_REGION:-us-east-1}"
export AWS_CA_BUNDLE="$CA_FILE"

echo "$(date -Is) export $DB_NAME"
mariadb-dump --single-transaction "$DB_NAME" | age -r "$AGE_RECIPIENT" -o "$TMP"

echo "$(date -Is) upload s3://$RUSTFS_BUCKET/$NAME"
aws --endpoint-url "$RUSTFS_ENDPOINT" s3 cp "$TMP" "s3://$RUSTFS_BUCKET/$NAME"

rm -f "$DIR/.env"
echo "$(date -Is) done, .env removed"
