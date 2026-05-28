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
PROJECTS_FILE="$(projects_file_path)"
RESULTS_DIR="$ROOT/results"
OUT_KEYS_DIR="$ROOT/out/access-keys"

mkdir -p "$RESULTS_DIR"

ACCOUNT_ID=""
if ACCOUNT_ID="$(account_id "$PROFILE" 2>/dev/null)"; then
  :
else
  ACCOUNT_ID="UNKNOWN_ACCOUNT_ID"
fi

export IAMGOV_RESULTS_DIR="$RESULTS_DIR"
export IAMGOV_OUT_KEYS_DIR="$OUT_KEYS_DIR"
export IAMGOV_PROJECTS_FILE="$PROJECTS_FILE"
export IAMGOV_ACCOUNT_ID="$ACCOUNT_ID"
export IAMGOV_PROFILE="$PROFILE"

node <<'NODE'
const fs = require('fs');
const path = require('path');

const resultsDir = process.env.IAMGOV_RESULTS_DIR;
const outKeysDir = process.env.IAMGOV_OUT_KEYS_DIR;
const projectsFile = process.env.IAMGOV_PROJECTS_FILE;
const accountId = process.env.IAMGOV_ACCOUNT_ID;
const profile = process.env.IAMGOV_PROFILE;

const cfg = JSON.parse(fs.readFileSync(projectsFile, 'utf8'));

function ensureDir(p) {
  fs.mkdirSync(p, { recursive: true });
}

function safeOutKeyName(email) {
  return String(email).replace(/[/:@]/g, '_');
}

function uniq(arr) {
  return Array.from(new Set(arr.map(String)));
}

function writeFile(filePath, content) {
  fs.writeFileSync(filePath, content, 'utf8');
}

function nowIso() {
  return new Date().toISOString();
}

for (const project of (cfg.projects || [])) {
  const projectId = String(project.id || 'unknown-project');
  const qualifier = String(project.qualifier || 'unknown-qualifier');
  const allowedServices = uniq(project.allowedServices || []);
  const requiredTags = uniq(project.requiredTagKeys || []);
  const developers = uniq((project.users || {}).developers || []);
  const viewers = uniq((project.users || {}).viewers || []);
  const allUsers = uniq([...developers, ...viewers]);

  const projectDir = path.join(resultsDir, projectId);
  const instructionsDir = path.join(projectDir, 'instructions');
  ensureDir(projectDir);
  ensureDir(instructionsDir);

  const projectInfoFile = path.join(projectDir, `${projectId}.md`);
  writeFile(projectInfoFile, [
    '# Informacion de proyecto',
    '',
    '<!-- Archivo generado por scripts/50_generate_results.sh -->',
    '<!-- Uso: referencia operativa para admin y usuarios del proyecto -->',
    '',
    `- Proyecto: ${projectId}`,
    `- Account ID: ${accountId}`,
    `- AWS Profile admin: ${profile}`,
    `- Qualifier: ${qualifier}`,
    `- Role de despliegue esperado: arn:aws:iam::${accountId}:role/cdk-${qualifier}-cfn-exec`,
    '',
    '## Servicios permitidos',
    ...allowedServices.map((s) => `- ${s}`),
    '',
    '## Tags obligatorios',
    ...requiredTags.map((t) => `- ${t}`),
    '',
    '## Usuarios developers',
    ...developers.map((u) => `- ${u}`),
    '',
    '## Usuarios viewers',
    ...viewers.map((u) => `- ${u}`),
    ''
  ].join('\n'));

  const projectInstructionsFile = path.join(instructionsDir, 'instructions.md');
  writeFile(projectInstructionsFile, [
    '# Instrucciones del proyecto',
    '',
    '<!-- Archivo generado por scripts/50_generate_results.sh -->',
    '<!-- Uso: entregar a usuarios de este proyecto como guia operativa -->',
    '',
    `Proyecto: ${projectId}`,
    `Account ID: ${accountId}`,
    `Qualifier: ${qualifier}`,
    '',
    '## Reglas operativas',
    '- No usar consola para cambios de infraestructura (solo CDK/IaC).',
    '- Usar siempre el qualifier del proyecto en DefaultStackSynthesizer.',
    '- Usar perfil de assume-role para desplegar.',
    '- Cumplir todos los tags obligatorios.',
    '',
    '## Configuracion local recomendada',
    '1. Configurar credenciales base en ~/.aws/credentials (entregadas por admin).',
    `2. Configurar profile de despliegue apuntando a arn:aws:iam::${accountId}:role/cdk-${qualifier}-cfn-exec.`,
    '3. Verificar sesion: aws sts get-caller-identity.',
    '',
    '## Comandos base',
    'export AWS_PROFILE=<perfil_proyecto>',
    'npm install',
    'npx cdk synth',
    'npx cdk diff',
    'npx cdk deploy',
    '',
    '## Tags obligatorios del proyecto',
    ...requiredTags.map((t) => `- ${t}`),
    ''
  ].join('\n'));

  for (const user of allUsers) {
    const role = developers.includes(user) ? 'developers' : 'viewers';
    const roleArn = `arn:aws:iam::${accountId}:role/cdk-${qualifier}-cfn-exec`;
    const safe = safeOutKeyName(user);
    const sourceKeyFile = path.join(outKeysDir, `${safe}.json`);
    const jsonTarget = path.join(projectDir, `credentials-${user}.json`);
    const mdTarget = path.join(projectDir, `credentials-${user}.md`);
    const userInstructions = path.join(instructionsDir, `instructions-${user}.md`);

    if (fs.existsSync(sourceKeyFile)) {
      const raw = fs.readFileSync(sourceKeyFile, 'utf8');
      writeFile(jsonTarget, raw);
    } else {
      writeFile(jsonTarget, JSON.stringify({
        _comment: 'Archivo generado como placeholder. No hay credencial creada en out/access-keys para este usuario.',
        user,
        projectId,
        role,
        expectedRoleArn: roleArn,
        createdAt: nowIso()
      }, null, 2) + '\n');
    }

    writeFile(mdTarget, [
      `# Credenciales de ${user}`,
      '',
      '<!-- Archivo generado por scripts/50_generate_results.sh -->',
      '<!-- Uso: entregar al usuario junto con instrucciones de proyecto -->',
      '',
      `- Proyecto: ${projectId}`,
      `- Rol: ${role}`,
      `- Qualifier: ${qualifier}`,
      `- Role ARN a asumir: ${roleArn}`,
      `- Archivo de credenciales JSON: credentials-${user}.json`,
      '',
      '## Nota de seguridad',
      '- El JSON puede contener secreto. No subir a git ni enviar por canales no seguros.',
      '- Si necesitas rotar credenciales, pedir al admin ejecutar scripts/40_create_access_keys.sh --rotate.',
      ''
    ].join('\n'));

    writeFile(userInstructions, [
      `# Instrucciones para ${user}`,
      '',
      '<!-- Archivo generado por scripts/50_generate_results.sh -->',
      '<!-- Uso: guia personalizada por usuario del proyecto -->',
      '',
      `- Proyecto: ${projectId}`,
      `- Rol: ${role}`,
      `- Account ID: ${accountId}`,
      `- Qualifier: ${qualifier}`,
      `- Role ARN: ${roleArn}`,
      '',
      '## Que debes saber',
      '- No puedes operar infraestructura por consola.',
      '- Debes desplegar con CDK asumiendo el role ARN indicado.',
      '- Debes incluir los tags obligatorios del proyecto en tus stacks.',
      '',
      '## Pasos minimos',
      '1. Configura ~/.aws/credentials con tus credenciales base.',
      '2. Configura ~/.aws/config con profile de assume-role para este proyecto.',
      '3. Ejecuta deploy con AWS_PROFILE del proyecto.',
      '',
      '## Tags obligatorios',
      ...requiredTags.map((t) => `- ${t}`),
      ''
    ].join('\n'));
  }
}
NODE

echo "INFO: Results generados en $RESULTS_DIR"