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

while IFS=$'\t' read -r USER_EMAIL GROUPS_CSV; do
  [[ -z "$USER_EMAIL" ]] && continue

  # Parse expected groups
  IFS=',' read -r -a EXPECTED_GROUPS <<< "$GROUPS_CSV"
  declare -A expected_set
  for group in "${EXPECTED_GROUPS[@]}"; do
    [[ -z "$group" ]] && continue
    expected_set["$group"]=1
  done

  # Check if user exists
  if aws iam get-user --user-name "$USER_EMAIL" --profile "$PROFILE" >/dev/null 2>&1; then
    echo "UPDATE user=$USER_EMAIL (usuario existente, actualizando membresías)"
    
    # Get current groups
    readarray -t current_groups < <(get_user_current_groups "$USER_EMAIL")
    declare -A current_set
    for group in "${current_groups[@]}"; do
      [[ -z "$group" ]] && continue
      current_set["$group"]=1
    done

    # Add user to new groups
    for group in "${EXPECTED_GROUPS[@]}"; do
      [[ -z "$group" ]] && continue
      if [[ -z "${current_set[$group]:-}" ]]; then
        add_user_to_group "$USER_EMAIL" "$group"
      fi
    done

    # Remove user from groups no longer needed
    for group in "${current_groups[@]}"; do
      [[ -z "$group" ]] && continue
      if [[ -z "${expected_set[$group]:-}" ]]; then
        remove_user_from_group "$USER_EMAIL" "$group"
      fi
    done

    unset expected_set current_set
  else
    # Create new user
    aws iam create-user --user-name "$USER_EMAIL" --profile "$PROFILE" >/dev/null
    echo "CREATED user=$USER_EMAIL"

    # Add to all expected groups
    for GROUP_NAME in "${EXPECTED_GROUPS[@]}"; do
      [[ -z "$GROUP_NAME" ]] && continue
      add_user_to_group "$USER_EMAIL" "$GROUP_NAME"
    done

    unset expected_set
  fi
done < <(list_user_group_plan)

echo
echo "INFO: Sincronizacion de usuarios finalizada."
