#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=common.sh
source "$SCRIPT_DIR/common.sh"

require_cmd aws
require_cmd git
require_cmd node

ensure_repo_root

PROFILE="$(default_profile)"

echo "INFO: Aplicando hardening de acceso a consola."
echo "INFO: Usuarios developers no tendran login profile de consola."
echo "INFO: Usuarios solo viewers mantienen modo lectura en consola segun sus politicas."
echo

while IFS=$'\t' read -r USER_EMAIL IS_DEVELOPER IS_VIEWER IS_ARCHITECT; do
  [[ -z "$USER_EMAIL" ]] && continue

  if ! aws iam get-user --user-name "$USER_EMAIL" --profile "$PROFILE" >/dev/null 2>&1; then
    echo "SKIP user=$USER_EMAIL (no existe en IAM)"
    continue
  fi

  if [[ "$IS_DEVELOPER" == "1" || "$IS_ARCHITECT" == "1" ]]; then
    if aws iam get-login-profile --user-name "$USER_EMAIL" --profile "$PROFILE" >/dev/null 2>&1; then
      aws iam delete-login-profile --user-name "$USER_EMAIL" --profile "$PROFILE"
      echo "UPDATED user=$USER_EMAIL login_profile=removed"
    else
      echo "OK user=$USER_EMAIL login_profile=absent"
    fi
  else
    if [[ "$IS_VIEWER" == "1" ]]; then
      echo "OK user=$USER_EMAIL modo=viewer"
    fi
  fi
done < <(list_user_access_mode)

echo

echo "INFO: Hardening de consola finalizado."
