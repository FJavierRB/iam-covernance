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
cd "$ROOT"

echo "INFO: Sincronizando usuarios desde config/projects.json"
echo "INFO: Usuarios nuevos serán creados y asignados a sus grupos."
echo "INFO: Usuarios existentes tendrán sus membresías actualizadas."
echo

# Función auxiliar para obtener los grupos actuales de un usuario
get_user_current_groups() {
  local user_email="$1"
  aws iam list-groups-for-user --user-name "$user_email" --profile "$PROFILE" \
    --query 'Groups[].GroupName' --output text 2>/dev/null | tr '\t' '\n' | sort
}

# Función auxiliar para agregar usuario a un grupo
add_user_to_group() {
  local user_email="$1"
  local group_name="$2"
  if aws iam add-user-to-group --group-name "$group_name" --user-name "$user_email" --profile "$PROFILE" 2>/dev/null; then
    echo "  + group=$group_name"
    return 0
  else
    echo "  ! error adding to group=$group_name" >&2
    return 1
  fi
}

# Función auxiliar para remover usuario de un grupo
remove_user_from_group() {
  local user_email="$1"
  local group_name="$2"
  if aws iam remove-user-from-group --group-name "$group_name" --user-name "$user_email" --profile "$PROFILE" 2>/dev/null; then
    echo "  - group=$group_name"
    return 0
  else
    echo "  ! error removing from group=$group_name" >&2
    return 1
  fi
}

array_contains() {
  local needle="$1"; shift
  local item
  for item in "$@"; do
    [[ "$item" == "$needle" ]] && return 0
  done
  return 1
}

while IFS=$'\t' read -r USER_EMAIL GROUPS_CSV; do
  [[ -z "$USER_EMAIL" ]] && continue

  # Parse expected groups into indexed array (compatible con bash 3.2)
  IFS=',' read -r -a EXPECTED_GROUPS <<< "$GROUPS_CSV"

  # Check if user exists
  if aws iam get-user --user-name "$USER_EMAIL" --profile "$PROFILE" >/dev/null 2>&1; then
    echo "UPDATE user=$USER_EMAIL (usuario existente, actualizando membresías)"

    # Get current groups into indexed array
    current_groups=()
    while IFS= read -r g; do
      [[ -n "$g" ]] && current_groups+=("$g")
    done < <(get_user_current_groups "$USER_EMAIL")

    # Add user to new groups not yet assigned
    for group in "${EXPECTED_GROUPS[@]}"; do
      [[ -z "$group" ]] && continue
      if ! array_contains "$group" "${current_groups[@]:-}"; then
        add_user_to_group "$USER_EMAIL" "$group"
      fi
    done

    # Remove user from groups no longer needed
    for group in "${current_groups[@]:-}"; do
      [[ -z "$group" ]] && continue
      if ! array_contains "$group" "${EXPECTED_GROUPS[@]:-}"; then
        remove_user_from_group "$USER_EMAIL" "$group"
      fi
    done

  else
    # Create new user
    aws iam create-user --user-name "$USER_EMAIL" --profile "$PROFILE" >/dev/null
    echo "CREATED user=$USER_EMAIL"

    # Add to all expected groups
    for GROUP_NAME in "${EXPECTED_GROUPS[@]}"; do
      [[ -z "$GROUP_NAME" ]] && continue
      add_user_to_group "$USER_EMAIL" "$GROUP_NAME"
    done
  fi
done < <(list_user_group_plan)

echo
echo "INFO: Sincronizacion de usuarios finalizada."
