#!/usr/bin/env bash



# Por cada email (IAM userName):

# si no existe el usuario → error (normalmente primero ejecutas 10_deploy_iam_governance.sh)
# si tiene 0 keys → crea 1 key y guarda el JSON solo en local: out/access-keys/<user>.json
# si tiene ≥1 keys → skip
# si pasas --rotate:

# si tiene 2 keys → desactiva + borra la más antigua y crea una nueva.

# Para crear renovación - AWS_PROFILE=cap7036 ./scripts/40_create_access_keys.sh --rotate

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

echo "INFO: Guardaré las credenciales nuevas en $OUT_DIR (NO las subas a git)."
echo "INFO: El SecretAccessKey solo se ve al crear la key. [4](https://docs.aws.amazon.com/IAM/latest/UserGuide/id_credentials_access-keys.html)[5](https://awscli.amazonaws.com/v2/documentation/api/2.1.30/reference/iam/create-access-key.html)"
echo

create_key() {
  local user="$1"
  local out_file="$2"

  local resp
  resp="$(aws iam create-access-key --user-name "$user" --profile "$PROFILE")" # incluye SecretAccessKey solo ahora [5](https://awscli.amazonaws.com/v2/documentation/api/2.1.30/reference/iam/create-access-key.html)

  printf '%s\n' "$resp" > "$out_file"
  chmod 600 "$out_file"

  local key_id
  key_id="$(node -e "const j=require('$out_file'); console.log(j.AccessKey.AccessKeyId)")"
  echo "CREATED user=$user accessKeyId=$key_id saved=$out_file"
}

list_keys() {
  local user="$1"
  aws iam list-access-keys --user-name "$user" --profile "$PROFILE" \
    --query 'AccessKeyMetadata[*].[AccessKeyId,CreateDate,Status]' --output json
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

  # elegir la más antigua por CreateDate
  local oldest
  oldest="$(node - <<NODE
const keys = $keys_json;
keys.sort((a,b)=> new Date(a[1]) - new Date(b[1]));
console.log(keys[0][0]);
NODE
)"
  echo "ROTATE user=$user deleting oldest accessKeyId=$oldest"

  # desactivar y borrar (orden recomendado)
  aws iam update-access-key --user-name "$user" --access-key-id "$oldest" --status Inactive --profile "$PROFILE" >/dev/null
  aws iam delete-access-key --user-name "$user" --access-key-id "$oldest" --profile "$PROFILE" >/dev/null
}

while IFS= read -r USER_EMAIL; do
  [[ -z "$USER_EMAIL" ]] && continue

  # existe el usuario?
  if ! aws iam get-user --user-name "$USER_EMAIL" --profile "$PROFILE" >/dev/null 2>&1; then
    echo "ERROR: no existe el usuario IAM '$USER_EMAIL'. Ejecuta antes scripts/10_deploy_iam_governance.sh" >&2
    exit 1
  fi

  keys_json="$(list_keys "$USER_EMAIL")"
  key_count="$(node -e "const k=$keys_json; console.log(k.length)")"

  safe="$(echo "$USER_EMAIL" | tr '/:@' '___')"
  out_file="$OUT_DIR/${safe}.json"

  if [[ "$key_count" -eq 0 ]]; then
    create_key "$USER_EMAIL" "$out_file"
    continue
  fi

  if [[ "$ROTATE" -eq 1 ]]; then
    delete_oldest_key_if_needed "$USER_EMAIL"
    # recalcular
    keys_json="$(list_keys "$USER_EMAIL")"
    key_count="$(node -e "const k=$keys_json; console.log(k.length)")"
    if [[ "$key_count" -lt 2 ]]; then
      create_key "$USER_EMAIL" "$out_file"
    else
      echo "SKIP user=$USER_EMAIL (ya tiene 2 keys y no se pudo rotar correctamente)"
    fi
  else
    echo "SKIP user=$USER_EMAIL (ya tiene $key_count access key(s); usa --rotate si quieres rotar)"
  fi

done < <(list_all_user_emails)