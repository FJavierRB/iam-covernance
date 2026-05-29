#!/usr/bin/env bash
set -euo pipefail

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || {
    echo "ERROR: falta el comando '$1' en PATH" >&2
    exit 1
  }
}

require_cmd jq

repo_root() {
  git rev-parse --show-toplevel 2>/dev/null
}

ensure_repo_root() {
  local root
  root="$(repo_root)"
  if [[ -z "$root" ]]; then
    echo "ERROR: no parece un repositorio git (git rev-parse falla)" >&2
    exit 1
  fi
}

config_file_path() {
  echo "$(repo_root)/config/config.json"
}

config_value() {
  local key="$1"
  jq -r ".${key}" "$(config_file_path)"
}

default_profile() {
  config_value "profile"
}

default_region() {
  config_value "region"
}

account_id() {
  local profile="${1:-$(default_profile)}"
  aws sts get-caller-identity --query "Account" --output text --profile "$profile"
}

projects_file_path() {
  local root rel
  root="$(repo_root)"
  rel="config/projects.json"
  if [[ -f "$root/cdk.json" ]]; then
    rel="$(node -e "const fs=require('fs'); const j=JSON.parse(fs.readFileSync(process.argv[1],'utf8')); console.log((j.context && j.context.projectsFile) ? j.context.projectsFile : 'config/projects.json');" "$root/cdk.json")"
  fi
  echo "$root/$rel"
}

prefix_file_path() {
  local root
  root="$(repo_root)"
  echo "$root/config/prefix.json"
}

groups_file_path() {
  local root
  root="$(repo_root)"
  echo "$root/config/groups.json"
}

policy_names_file_path() {
  local root
  root="$(repo_root)"
  echo "$root/config/policy-names.json"
}

list_project_bootstrap_rows() {
  local pf pff pnf
  pf="$(projects_file_path)"
  pff="$(prefix_file_path)"
  pnf="$(policy_names_file_path)"

  node - "$pf" "$pff" "$pnf" <<'NODE'
const fs = require('fs');

const projectsFile = process.argv[2];
const prefixFile = process.argv[3];
const policyNamesFile = process.argv[4];

const projectsCfg = JSON.parse(fs.readFileSync(projectsFile, 'utf8'));
const prefixCfg = JSON.parse(fs.readFileSync(prefixFile, 'utf8'));
const policyNamesCfg = JSON.parse(fs.readFileSync(policyNamesFile, 'utf8'));

function deriveEnv(project) {
  if (project.env && String(project.env).trim().length > 0) {
    return String(project.env).trim().toLowerCase();
  }
  const m = String(project.qualifier || '').match(/(dev|qa|test|pre|pro|prod|prd)$/i);
  if (!m) return 'dev';
  return m[1].toLowerCase() === 'prod' ? 'pro' : m[1].toLowerCase();
}

function renderPrefix(pattern, env, projectToken, serviceToken) {
  return pattern
    .replace('[env]', env)
    .replace('[proyecto]', projectToken)
    .replace('[servicio]', serviceToken)
    .replace(/\[([^\]]+)\]/g, '$1');
}

function sanitizeIamName(name, maxLen = 128) {
  return String(name).toLowerCase().replace(/[^a-z0-9+=,.@-]/g, '').slice(0, maxLen);
}

for (const project of (projectsCfg.projects || [])) {
  const env = deriveEnv(project);
  const policyName = sanitizeIamName(
    renderPrefix(
      prefixCfg.pattern,
      env,
      project.id,
      policyNamesCfg.cloudFormationExecution.serviceToken
    )
  );

  console.log([
    project.id || '',
    project.qualifier || '',
    env,
    policyName
  ].join('\t'));
}
NODE
}

list_projects_table() {
  list_project_bootstrap_rows | awk -F '\t' '{print $1"\t"$2}'
}

list_qualifiers() {
  list_project_bootstrap_rows | awk -F '\t' '{print $2}'
}

list_all_user_emails() {
  local pf
  pf="$(projects_file_path)"
  node - "$pf" <<'NODE'
const fs = require('fs');
const projectsFile = process.argv[2];
const cfg = JSON.parse(fs.readFileSync(projectsFile, 'utf8'));
const out = new Set();

for (const project of (cfg.projects || [])) {
  const users = project.users || {};
  for (const email of (users.developers || [])) out.add(String(email));
  for (const email of (users.viewers || [])) out.add(String(email));
  for (const email of (users.architects || [])) out.add(String(email));
}

for (const email of out) {
  console.log(email);
}
NODE
}

list_user_access_mode() {
  local pf
  pf="$(projects_file_path)"
  node - "$pf" <<'NODE'
const fs = require('fs');
const projectsFile = process.argv[2];
const cfg = JSON.parse(fs.readFileSync(projectsFile, 'utf8'));
const userMode = new Map();

for (const project of (cfg.projects || [])) {
  const users = project.users || {};

  for (const emailRaw of (users.developers || [])) {
    const email = String(emailRaw);
    if (!userMode.has(email)) userMode.set(email, { developer: false, viewer: false, architect: false });
    userMode.get(email).developer = true;
  }

  for (const emailRaw of (users.viewers || [])) {
    const email = String(emailRaw);
    if (!userMode.has(email)) userMode.set(email, { developer: false, viewer: false, architect: false });
    userMode.get(email).viewer = true;
  }

  for (const emailRaw of (users.architects || [])) {
    const email = String(emailRaw);
    if (!userMode.has(email)) userMode.set(email, { developer: false, viewer: false, architect: false });
    userMode.get(email).architect = true;
  }
}

for (const [email, mode] of userMode.entries()) {
  console.log(`${email}\t${mode.developer ? 1 : 0}\t${mode.viewer ? 1 : 0}\t${mode.architect ? 1 : 0}`);
}
NODE
}

list_user_group_plan() {
  local pf pff gf
  pf="$(projects_file_path)"
  pff="$(prefix_file_path)"
  gf="$(groups_file_path)"

  node - "$pf" "$pff" "$gf" <<'NODE'
const fs = require('fs');

const projectsFile = process.argv[2];
const prefixFile = process.argv[3];
const groupsFile = process.argv[4];

const projectsCfg = JSON.parse(fs.readFileSync(projectsFile, 'utf8'));
const prefixCfg = JSON.parse(fs.readFileSync(prefixFile, 'utf8'));
const groupsCfg = JSON.parse(fs.readFileSync(groupsFile, 'utf8'));

function deriveEnv(project) {
  if (project.env && String(project.env).trim().length > 0) {
    return String(project.env).trim().toLowerCase();
  }
  const m = String(project.qualifier || '').match(/(dev|qa|test|pre|pro|prod|prd)$/i);
  if (!m) return 'dev';
  return m[1].toLowerCase() === 'prod' ? 'pro' : m[1].toLowerCase();
}

function renderPrefix(pattern, env, projectToken, serviceToken) {
  return pattern
    .replace('[env]', env)
    .replace('[proyecto]', projectToken)
    .replace('[servicio]', serviceToken)
    .replace(/\[([^\]]+)\]/g, '$1');
}

function sanitizeIamName(name, maxLen = 128) {
  return String(name).toLowerCase().replace(/[^a-z0-9+=,.@-]/g, '').slice(0, maxLen);
}

const usersToGroups = new Map();

for (const project of (projectsCfg.projects || [])) {
  const env = deriveEnv(project);
  const devGroup = sanitizeIamName(renderPrefix(prefixCfg.pattern, env, project.id, groupsCfg.developers.serviceToken));
  const viewerGroup = sanitizeIamName(renderPrefix(prefixCfg.pattern, env, project.id, groupsCfg.viewers.serviceToken));
  const architectGroup = sanitizeIamName(renderPrefix(prefixCfg.pattern, env, project.id, (groupsCfg.architects || {}).serviceToken || 'architects'));

  for (const emailRaw of ((project.users || {}).developers || [])) {
    const email = String(emailRaw);
    if (!usersToGroups.has(email)) usersToGroups.set(email, new Set());
    usersToGroups.get(email).add(devGroup);
  }

  for (const emailRaw of ((project.users || {}).viewers || [])) {
    const email = String(emailRaw);
    if (!usersToGroups.has(email)) usersToGroups.set(email, new Set());
    usersToGroups.get(email).add(viewerGroup);
  }

  for (const emailRaw of ((project.users || {}).architects || [])) {
    const email = String(emailRaw);
    if (!usersToGroups.has(email)) usersToGroups.set(email, new Set());
    usersToGroups.get(email).add(architectGroup);
  }
}

for (const [email, groups] of usersToGroups.entries()) {
  console.log(`${email}\t${Array.from(groups).join(',')}`);
}
NODE
}

ssm_bootstrap_param() {
  local qualifier="$1"
  echo "/cdk-bootstrap/${qualifier}/version"
}

is_bootstrapped() {
  local qualifier="$1"
  local profile="${2:-$(default_profile)}"
  local region="${3:-$(default_region)}"
  local param
  param="$(ssm_bootstrap_param "$qualifier")"
  aws ssm get-parameter --name "$param" --region "$region" --profile "$profile" >/dev/null 2>&1
}
