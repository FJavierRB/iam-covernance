#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=common.sh
source "$SCRIPT_DIR/common.sh"

require_cmd node
require_cmd aws
require_cmd git

ensure_repo_root

PROFILE="$(default_profile)"

ROOT="$(repo_root)"
OUT_DIR="$ROOT/out"
OUT_FILE="$OUT_DIR/access-keys.csv"

mkdir -p "$OUT_DIR"
chmod 700 "$OUT_DIR"

echo "UserName,AccessKeyId,Status,CreateDate" > "$OUT_FILE"

while IFS= read -r USER_EMAIL; do
  [[ -z "$USER_EMAIL" ]] && continue

  # Comprobar si existe el usuario
  if ! aws iam get-user --user-name "$USER_EMAIL" --profile "$PROFILE" >/dev/null 2>&1; then
    echo "WARN: usuario no existe -> $USER_EMAIL (se omite)"
    continue
  fi

  KEYS_JSON="$(aws iam list-access-keys \
    --user-name "$USER_EMAIL" \
    --profile "$PROFILE" \
    --output json)"

  COUNT="$(node -e "const k=$KEYS_JSON; console.log(k.AccessKeyMetadata.length)")"

  if [[ "$COUNT" -eq 0 ]]; then
    # Usuario sin keys
    echo "$USER_EMAIL,,," >> "$OUT_FILE"
    continue
  fi

  # Iterar keys
  node - <<NODE >> "$OUT_FILE"
const data = $KEYS_JSON;
const user = "${USER_EMAIL}";
for (const k of data.AccessKeyMetadata) {
  console.log([
    user,
    k.AccessKeyId,
    k.Status,
    k.CreateDate
  ].join(","));
}
NODE

done < <(list_all_user_emails)

chmod 600 "$OUT_FILE"

echo "CSV generado en: $OUT_FILE"