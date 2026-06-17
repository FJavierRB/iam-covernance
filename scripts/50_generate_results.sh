#!/usr/bin/env bash
set -euo pipefail

# Script para generar artefactos operativos por proyecto y por usuario.
# Genera:
# - Un fichero resumen del proyecto.
# - Un fichero de instrucciones generales del proyecto.
# - Un fichero JSON de credenciales o placeholder por usuario.
# - Un fichero Markdown de contexto de credenciales por usuario.
# - Un fichero de instrucciones personalizadas por usuario.
#
# Este script lee la configuración de proyectos y genera salida en results/.
# También intenta reutilizar los ficheros de credenciales creados previamente
# en out/access-keys/ cuando existan.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# Importa utilidades comunes del repositorio.
# shellcheck source=common.sh
source "$SCRIPT_DIR/common.sh"

# Verifica disponibilidad de dependencias necesarias.
require_cmd node
require_cmd aws
require_cmd git

# Verifica que el script se ejecuta dentro del repositorio correcto.
ensure_repo_root

# Obtiene el profile AWS por defecto desde config/config.json.
PROFILE="$(default_profile)"

# Obtiene la raíz del repositorio y rutas relevantes.
ROOT="$(repo_root)"
PROJECTS_FILE="$(projects_file_path)"
RESULTS_DIR="$ROOT/results"
OUT_KEYS_DIR="$ROOT/out/access-keys"

# Garantiza que exista el directorio de resultados.
mkdir -p "$RESULTS_DIR"

# Intenta resolver el Account ID usando el profile configurado.
# Si falla, se deja un literal de fallback para que el resultado siga generándose.
ACCOUNT_ID=""
if ACCOUNT_ID="$(account_id "$PROFILE" 2>/dev/null)"; then
  :
else
  ACCOUNT_ID="UNKNOWN_ACCOUNT_ID"
fi

# Exporta variables de entorno para que el bloque Node.js pueda consumirlas.
export IAMGOV_RESULTS_DIR="$RESULTS_DIR"
export IAMGOV_OUT_KEYS_DIR="$OUT_KEYS_DIR"
export IAMGOV_PROJECTS_FILE="$PROJECTS_FILE"
export IAMGOV_ACCOUNT_ID="$ACCOUNT_ID"
export IAMGOV_PROFILE="$PROFILE"

node <<'NODE'
const fs = require('fs');
const path = require('path');

/**
 * Lee variables de entorno exportadas por el shell.
 */
const resultsDir = process.env.IAMGOV_RESULTS_DIR;
const outKeysDir = process.env.IAMGOV_OUT_KEYS_DIR;
const projectsFile = process.env.IAMGOV_PROJECTS_FILE;
const accountId = process.env.IAMGOV_ACCOUNT_ID;
const profile = process.env.IAMGOV_PROFILE;

/**
 * Carga la configuración de proyectos desde el JSON indicado.
 */
const cfg = JSON.parse(fs.readFileSync(projectsFile, 'utf8'));

/**
 * Crea un directorio si no existe.
 */
function ensureDir(dirPath) {
  fs.mkdirSync(dirPath, { recursive: true });
}

/**
 * Convierte un email en un nombre seguro para fichero de salida.
 */
function safeOutKeyName(email) {
  return String(email).replace(/[/:@]/g, '_');
}

/**
 * Elimina duplicados preservando cadenas.
 */
function uniq(arr) {
  return Array.from(new Set((arr || []).map((value) => String(value))));
}

/**
 * Escribe un fichero de texto en UTF-8.
 */
function writeFile(filePath, content) {
  fs.writeFileSync(filePath, content, 'utf8');
}

/**
 * Devuelve la fecha actual en formato ISO.
 */
function nowIso() {
  return new Date().toISOString();
}

/**
 * Devuelve los roles efectivos de un usuario dentro de un proyecto.
 * Un usuario puede aparecer en uno o varios roles del mismo proyecto.
 */
function getUserRolesForProject(user, developers, viewers, architects) {
  const roles = [];

  if (developers.includes(user)) {
    roles.push('developers');
  }

  if (viewers.includes(user)) {
    roles.push('viewers');
  }

  if (architects.includes(user)) {
    roles.push('architects');
  }

  return roles;
}

/**
 * Devuelve una etiqueta legible con los roles del usuario.
 */
function getRoleLabel(roles) {
  if (!roles || roles.length === 0) {
    return 'sin-rol';
  }

  return roles.join(', ');
}

/**
 * Devuelve el rol principal a efectos de compatibilidad con los artefactos previos.
 * Prioridad:
 * - architects
 * - developers
 * - viewers
 *
 * Esta prioridad solo se usa para el campo "role" del JSON generado.
 * La información completa de roles se documenta también en "roles".
 */
function getPrimaryRole(roles) {
  if (roles.includes('architects')) {
    return 'architects';
  }

  if (roles.includes('developers')) {
    return 'developers';
  }

  if (roles.includes('viewers')) {
    return 'viewers';
  }

  return 'sin-rol';
}

/**
 * Construye el ARN del role esperado documentado por el sistema.
 * Se mantiene la semántica actual del proyecto para no mezclar este cambio
 * con otros ajustes funcionales de IAM/CDK que se revisarán aparte.
 */
function getExpectedRoleArn(accountIdValue, qualifier) {
  return `arn:aws:iam::${accountIdValue}:role/cdk-${qualifier}-cfn-exec`;
}

/**
 * Genera un bloque Markdown de lista.
 */
function renderMarkdownList(items) {
  if (!items || items.length === 0) {
    return ['- Ninguno'];
  }

  return items.map((item) => `- ${item}`);
}

/**
 * Procesa cada proyecto definido en la configuración.
 */
for (const project of (cfg.projects || [])) {
  const projectId = String(project.id || 'unknown-project');
  const qualifier = String(project.qualifier || 'unknown-qualifier');

  const allowedServices = uniq(project.allowedServices || []);
  const requiredTags = uniq(project.requiredTagKeys || []);

  const developers = uniq(((project.users || {}).developers) || []);
  const viewers = uniq(((project.users || {}).viewers) || []);
  const architects = uniq(((project.users || {}).architects) || []);

  const allUsers = uniq([
    ...developers,
    ...viewers,
    ...architects
  ]);

  const projectDir = path.join(resultsDir, projectId);
  const instructionsDir = path.join(projectDir, 'instructions');

  ensureDir(projectDir);
  ensureDir(instructionsDir);

  const projectRoleArn = getExpectedRoleArn(accountId, qualifier);

  /**
   * Genera el fichero resumen del proyecto.
   */
  const projectInfoFile = path.join(projectDir, `${projectId}.md`);
  writeFile(projectInfoFile, [
    '# Informacion de proyecto',
    '',
    '<!-- Archivo generado por scripts/50_generate_results.sh -->',
    '<!-- Uso: referencia operativa para administracion y usuarios del proyecto -->',
    '',
    `- Proyecto: ${projectId}`,
    `- Account ID: ${accountId}`,
    `- AWS Profile admin: ${profile}`,
    `- Qualifier: ${qualifier}`,
    `- Role documentado por el sistema: ${projectRoleArn}`,
    '',
    '## Servicios permitidos',
    ...renderMarkdownList(allowedServices),
    '',
    '## Tags obligatorios',
    ...renderMarkdownList(requiredTags),
    '',
    '## Usuarios developers',
    ...renderMarkdownList(developers),
    '',
    '## Usuarios viewers',
    ...renderMarkdownList(viewers),
    '',
    '## Usuarios architects',
    ...renderMarkdownList(architects),
    '',
    '## Todos los usuarios del proyecto',
    ...renderMarkdownList(allUsers),
    ''
  ].join('\n'));

  /**
   * Genera el fichero de instrucciones generales del proyecto.
   */
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
    '- No usar consola para cambios de infraestructura.',
    '- Usar siempre el qualifier del proyecto en el sintetizador CDK.',
    '- Utilizar el modelo de acceso definido para el proyecto y sus roles.',
    '- Cumplir todos los tags obligatorios del proyecto.',
    '',
    '## Configuracion local recomendada',
    '1. Configurar credenciales base en ~/.aws/credentials si aplica.',
    `2. Configurar el acceso al role documentado por el sistema: ${projectRoleArn}.`,
    '3. Verificar la sesion con aws sts get-caller-identity.',
    '',
    '## Comandos base',
    'export AWS_PROFILE=<perfil_proyecto>',
    'npm install',
    'npx cdk synth',
    'npx cdk diff',
    'npx cdk deploy',
    '',
    '## Tags obligatorios del proyecto',
    ...renderMarkdownList(requiredTags),
    ''
  ].join('\n'));

  /**
   * Genera artefactos por usuario del proyecto.
   */
  for (const user of allUsers) {
    const userRoles = getUserRolesForProject(user, developers, viewers, architects);
    const primaryRole = getPrimaryRole(userRoles);
    const roleLabel = getRoleLabel(userRoles);

    const roleArn = getExpectedRoleArn(accountId, qualifier);
    const safe = safeOutKeyName(user);

    const sourceKeyFile = path.join(outKeysDir, `${safe}.json`);
    const jsonTarget = path.join(projectDir, `credentials-${user}.json`);
    const mdTarget = path.join(projectDir, `credentials-${user}.md`);
    const userInstructions = path.join(instructionsDir, `instructions-${user}.md`);

    /**
     * Genera el JSON de credenciales.
     * Si existe un fichero real en out/access-keys, lo copia tal cual.
     * Si no existe, genera un placeholder con contexto suficiente.
     */
    if (fs.existsSync(sourceKeyFile)) {
      const raw = fs.readFileSync(sourceKeyFile, 'utf8');
      writeFile(jsonTarget, raw);
    } else {
      writeFile(jsonTarget, JSON.stringify({
        _comment: 'Archivo generado como placeholder. No hay credencial creada en out/access-keys para este usuario.',
        user,
        projectId,
        role: primaryRole,
        roles: userRoles,
        expectedRoleArn: roleArn,
        createdAt: nowIso()
      }, null, 2) + '\n');
    }

    /**
     * Genera el Markdown de contexto de credenciales por usuario.
     */
    writeFile(mdTarget, [
      `# Credenciales de ${user}`,
      '',
      '<!-- Archivo generado por scripts/50_generate_results.sh -->',
      '<!-- Uso: entregar al usuario junto con instrucciones de proyecto -->',
      '',
      `- Proyecto: ${projectId}`,
      `- Rol principal: ${primaryRole}`,
      `- Roles en el proyecto: ${roleLabel}`,
      `- Qualifier: ${qualifier}`,
      `- Role documentado por el sistema: ${roleArn}`,
      `- Archivo de credenciales JSON: credentials-${user}.json`,
      '',
      '## Nota de seguridad',
      '- El JSON puede contener secreto. No subir a git ni enviar por canales no seguros.',
      '- Si necesitas rotar credenciales, pedir al administrador ejecutar scripts/40_create_access_keys.sh --rotate.',
      ''
    ].join('\n'));

    /**
     * Genera las instrucciones personalizadas por usuario.
     */
    writeFile(userInstructions, [
      `# Instrucciones para ${user}`,
      '',
      '<!-- Archivo generado por scripts/50_generate_results.sh -->',
      '<!-- Uso: guia personalizada por usuario del proyecto -->',
      '',
      `- Proyecto: ${projectId}`,
      `- Rol principal: ${primaryRole}`,
      `- Roles en el proyecto: ${roleLabel}`,
      `- Account ID: ${accountId}`,
      `- Qualifier: ${qualifier}`,
      `- Role documentado por el sistema: ${roleArn}`,
      '',
      '## Que debes saber',
      '- Debes operar conforme a los permisos asignados a tus roles dentro de este proyecto.',
      '- No debes realizar cambios de infraestructura fuera del modelo definido por el proyecto.',
      '- Debes incluir los tags obligatorios del proyecto en tus despliegues o recursos aplicables.',
      '',
      '## Pasos minimos',
      '1. Configura tus credenciales base si aplica.',
      '2. Configura tu perfil AWS o método de acceso correspondiente para este proyecto.',
      '3. Verifica identidad con aws sts get-caller-identity.',
      '4. Ejecuta los comandos del proyecto con el perfil adecuado.',
      '',
      '## Tags obligatorios',
      ...renderMarkdownList(requiredTags),
      ''
    ].join('\n'));
  }
}
NODE

echo "INFO: Results generados en $RESULTS_DIR"