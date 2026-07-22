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
REGION="$(default_region)"
ACCOUNT_ID="$(account_id "$PROFILE")"

echo "profile=$PROFILE region=$REGION account=$ACCOUNT_ID"
echo
echo -e "project_id\tqualifier\tenv\texec_policy\tpolicy\tbootstrap_ssm"

while IFS=$'\t' read -r PROJECT_ID QUALIFIER PROJECT_ENV POLICY_NAME; do
  [[ -z "$QUALIFIER" ]] && continue

  POLICY_ARN="arn:aws:iam::${ACCOUNT_ID}:policy/${POLICY_NAME}"
  SSM_PARAM="/cdk-bootstrap/${QUALIFIER}/version"

  POLICY_OK="NO"
  if aws iam get-policy --policy-arn "$POLICY_ARN" --profile "$PROFILE" >/dev/null 2>&1; then
    POLICY_OK="OK"
  fi

  SSM_OK="NO"
  if aws ssm get-parameter --name "$SSM_PARAM" --region "$REGION" --profile "$PROFILE" >/dev/null 2>&1; then
    SSM_OK="OK"
  fi

  printf "%s\t%s\t%s\t%s\t%s\t%s\n" "$PROJECT_ID" "$QUALIFIER" "$PROJECT_ENV" "$POLICY_NAME" "$POLICY_OK" "$SSM_OK"
done < <(list_project_bootstrap_rows)
