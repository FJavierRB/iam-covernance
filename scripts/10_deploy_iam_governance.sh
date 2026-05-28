#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=common.sh
source "$SCRIPT_DIR/common.sh"

require_cmd node
require_cmd npm
require_cmd npx
require_cmd aws
require_cmd git

ensure_repo_root

PROFILE="$(default_profile)"

ROOT="$(repo_root)"
cd "$ROOT"

npm ci || npm install

npx cdk synth --profile "$PROFILE"
npx cdk diff  --profile "$PROFILE"
npx cdk deploy --profile "$PROFILE"

"$SCRIPT_DIR/15_sync_new_users.sh"
"$SCRIPT_DIR/16_enforce_console_mode.sh"
bash "$SCRIPT_DIR/50_generate_results.sh"