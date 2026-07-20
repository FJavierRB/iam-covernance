#!/usr/bin/env bash

# Script de gestión de access keys IAM.
#
# Comportamiento:
# - Solo genera claves para usuarios con rol developers o architects.
# - Nunca genera claves para viewers (no deben operar programáticamente).
# - Si un usuario tiene 0 keys → crea una.
# - Si tiene >=1 → no hace nada (salvo --rotate).
# - Con --rotate:
#     - si tiene 2 keys → elimina la más antigua y crea nueva.
#
# Las credenciales se guardan SOLO en local:
# out/access-keys/<user>.json

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=common.sh
source "$SCRIPT_DIR/common.sh"

require_cmd node
require_cmd aws
require_cmd git

ensure_repo_root

PROFILE="$(default_profile)"

ROTATE=0
if [[ "${1:-}" == "--rotate" ]]; then
  ROTATE=1
fi

ROOT="$(repo_root)"
cd "$ROOT"

OUT_DIR="$ROOT/out/access-keys"
mkdir -p "$OUT_DIR"
chmod 700 "$ROOT/out" "$OUT_DIR"

echo "INFO: Generacion de access keys controlada por rol."
echo "INFO: Solo se generan claves para developers y architects."
echo "INFO: Los viewers no reciben access keys."
echo "INFO: El SecretAccessKey solo se ve en el momento de creación."
echo

# ---------------------------------------------------------
# FUNCIONES AUXILIARES
# ---------------------------------------------------------

create_key() {
  local user="$1"
  local out_file="$2"

  local resp
  resp="$(aws iam create-access-key --user-name "$user" --profile "$PROFILE")"

  printf '%s\n' "$resp" > "$out_file"
  chmod 600 "$out_file"

  local key_id
  key_id="$(node -e "const j=require('$out_file'); console.log(j.AccessKey.AccessKeyId)")"

  echo "CREATED user=$user accessKeyId=$key_id saved=$out_file"
}

list_keys() {
  local user="$1"
  aws iam list-access-keys \
    --user-name "$user" \
    --profile "$PROFILE" \
    --query 'AccessKeyMetadata[*].[AccessKeyId,CreateDate,Status]' \
    --output json
}

delete_oldest_key_if_needed() {
  local user="$1"

  local keys_json
  keys_json="$(list_keys "$user")"

  local count
  count="$(node -e "const k=$keys_json; console.log(k.length)")"

  if [[ "$count" -lt 2 ]]; then
    return 0
  fi

  local oldest
  oldest="$(node - <<NODE
const keys = $keys_json;
keys.sort((a,b)=> new Date(a[1]) - new Date(b[1]));
console.log(keys[0][0]);
NODE
)"

  echo "ROTATE user=$user deleting oldest accessKeyId=$oldest"

  aws iam update-access-key \
    --user-name "$user" \
    --access-key-id "$oldest" \
    --status Inactive \
    --profile "$PROFILE" > /dev/null

  aws iam delete-access-key \
    --user-name "$user" \
    --access-key-id "$oldest" \
    --profile "$PROFILE" > /dev/null
}

# ---------------------------------------------------------
# PROCESAMIENTO PRINCIPAL
# ---------------------------------------------------------

while IFS=$'\t' read -r USER_EMAIL IS_DEVELOPER IS_VIEWER IS_ARCHITECT; do
  [[ -z "$USER_EMAIL" ]] && continue

  # Solo developers y architects pueden tener keys
  if [[ "$IS_DEVELOPER" != "1" && "$IS_ARCHITECT" != "1" ]]; then
    echo "SKIP user=$USER_EMAIL (rol viewer, no se generan claves)"
    continue
  fi

  # Verificar que el usuario existe
  if ! aws iam get-user --user-name "$USER_EMAIL" --profile "$PROFILE" > /dev/null 2>&1; then
    echo "ERROR: no existe el usuario IAM '$USER_EMAIL'. Ejecuta primero el deploy de governance." >&2
    exit 1
  fi

  keys_json="$(list_keys "$USER_EMAIL")"
  key_count="$(node -e "const k=$keys_json; console.log(k.length)")"

  safe="$(echo "$USER_EMAIL" | tr '/:@' '___')"
  out_file="$OUT_DIR/${safe}.json"

  # ----------------------------------------
  # CASO: SIN KEYS
  # ----------------------------------------
  if [[ "$key_count" -eq 0 ]]; then
    create_key "$USER_EMAIL" "$out_file"
    continue
  fi

  # ----------------------------------------
  # CASO: ROTACION
  # ----------------------------------------
  if [[ "$ROTATE" -eq 1 ]]; then
    delete_oldest_key_if_needed "$USER_EMAIL"

    keys_json="$(list_keys "$USER_EMAIL")"
    key_count="$(node -e "const k=$keys_json; console.log(k.length)")"

    if [[ "$key_count" -lt 2 ]]; then
      create_key "$USER_EMAIL" "$out_file"
    else
      echo "SKIP user=$USER_EMAIL (no se pudo rotar correctamente)"
    fi

  else
    echo "SKIP user=$USER_EMAIL (ya tiene $key_count access key(s); usa --rotate si quieres rotar)"
  fi

done < <(list_user_access_mode)

echo
echo "INFO: Gestion de access keys finalizada."