#!/usr/bin/env bash
set -euo pipefail

# Script para endurecer el acceso a consola de usuarios IAM.
#
# Comportamiento:
# - Developers: NO pueden tener login profile de consola.
# - Architects: NO pueden tener login profile de consola.
# - Viewers: mantienen acceso de solo lectura (según sus políticas).
#
# Este script es idempotente:
# - Si ya está en el estado deseado, no hace cambios.
# - Se puede ejecutar tantas veces como sea necesario.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=common.sh
source "$SCRIPT_DIR/common.sh"

require_cmd aws
require_cmd git
require_cmd node

ensure_repo_root

PROFILE="$(default_profile)"

echo "INFO: Aplicando hardening de acceso a consola."
echo "INFO: Developers y architects: sin acceso a consola."
echo "INFO: Viewers: acceso en modo lectura (si tienen login profile)."
echo

# ---------------------------------------------------------
# FUNCIONES AUXILIARES
# ---------------------------------------------------------

# Verifica si un usuario tiene login profile (acceso a consola)
has_login_profile() {
  local user="$1"

  if aws iam get-login-profile \
    --user-name "$user" \
    --profile "$PROFILE" >/dev/null 2>&1; then
    return 0
  fi

  return 1
}

# Elimina el login profile de un usuario
remove_login_profile() {
  local user="$1"

  aws iam delete-login-profile \
    --user-name "$user" \
    --profile "$PROFILE"

  echo "UPDATED user=$user login_profile=removed"
}

# ---------------------------------------------------------
# PROCESAMIENTO PRINCIPAL
# ---------------------------------------------------------

while IFS=$'\t' read -r USER_EMAIL IS_DEVELOPER IS_VIEWER IS_ARCHITECT; do
  [[ -z "$USER_EMAIL" ]] && continue

  # Verifica que el usuario existe en IAM
  if ! aws iam get-user \
    --user-name "$USER_EMAIL" \
    --profile "$PROFILE" >/dev/null 2>&1; then

    echo "SKIP user=$USER_EMAIL (no existe en IAM)"
    continue
  fi

  # -----------------------------------------------------
  # CASO: DEVELOPERS O ARCHITECTS
  # -----------------------------------------------------
  # Estos usuarios no deben tener acceso a consola.

  if [[ "$IS_DEVELOPER" == "1" || "$IS_ARCHITECT" == "1" ]]; then

    if has_login_profile "$USER_EMAIL"; then
      remove_login_profile "$USER_EMAIL"
    else
      echo "OK user=$USER_EMAIL (sin acceso a consola)"
    fi

    continue
  fi

  # -----------------------------------------------------
  # CASO: VIEWERS
  # -----------------------------------------------------
  # Se permite login profile pero no se modifica.
  # Su capacidad real depende de las políticas IAM.

  if [[ "$IS_VIEWER" == "1" ]]; then
    if has_login_profile "$USER_EMAIL"; then
      echo "OK user=$USER_EMAIL modo=viewer (login_profile presente)"
    else
      echo "OK user=$USER_EMAIL modo=viewer (sin login_profile)"
    fi

    continue
  fi

  # -----------------------------------------------------
  # CASO: SIN ROL DEFINIDO (defensivo)
  # -----------------------------------------------------
  # Si aparece un usuario sin rol, no se toca.

  echo "WARN user=$USER_EMAIL sin rol definido (no se modifica)"

done < <(list_user_access_mode)

echo
echo "INFO: Hardening de consola finalizado."