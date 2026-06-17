#!/usr/bin/env bash

# Hace bootstrap por qualifier para cada proyecto definido en config/projects.json (o lo que tengas configurado en cdk.json -> context.projectsFile).

# Requiere que ya exista la policy CdkCfnExec_<qualifier> creada por el stack IAM governance.
# Usa --cloudformation-execution-policies para adjuntar esa policy al execution role de ese bootstrap.


set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=common.sh
source "$SCRIPT_DIR/common.sh"

require_cmd node
require_cmd aws
require_cmd npx
require_cmd git

ensure_repo_root

PROFILE="$(default_profile)"
REGION="$(default_region)"
ACCOUNT_ID="$(account_id "$PROFILE")"

FORCE=0
if [[ "${1:-}" == "--force" ]]; then
  FORCE=1
fi

ROOT="$(repo_root)"
cd "$ROOT"

while IFS=$'\t' read -r PROJECT_ID QUALIFIER PROJECT_ENV POLICY_NAME; do
  [[ -z "$QUALIFIER" ]] && continue

  POLICY_ARN="arn:aws:iam::${ACCOUNT_ID}:policy/${POLICY_NAME}"

  if ! aws iam get-policy --policy-arn "$POLICY_ARN" --profile "$PROFILE" >/dev/null 2>&1; then
    echo "ERROR: no existe la policy $POLICY_ARN. Ejecuta antes scripts/10_deploy_iam_governance.sh" >&2
    exit 1
  fi

  if [[ "$FORCE" -eq 0 ]] && is_bootstrapped "$QUALIFIER" "$PROFILE" "$REGION"; then
    echo "SKIP bootstrap qualifier=${QUALIFIER} (ya existe $(ssm_bootstrap_param "$QUALIFIER"))"
    continue
  fi

  TOOLKIT_STACK_NAME="${PROJECT_ID}-cdk-toolkit"

  echo "BOOTSTRAP project=${PROJECT_ID} qualifier=${QUALIFIER} env=${PROJECT_ENV} region=${REGION} policy=${POLICY_NAME} toolkit=${TOOLKIT_STACK_NAME}"
  npx cdk bootstrap "aws://${ACCOUNT_ID}/${REGION}" \
    --toolkit-stack-name "$TOOLKIT_STACK_NAME" \
    --qualifier "$QUALIFIER" \
    --cloudformation-execution-policies "$POLICY_ARN" \
    --profile "$PROFILE"

done < <(list_project_bootstrap_rows)
