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
  const generalDir = path.join(projectDir, `${projectId}-general`);

  ensureDir(projectDir);
  ensureDir(generalDir);

  // Elimina artefactos obsoletos de versiones anteriores del generador.
  const obsoleteProjectFile = path.join(projectDir, `${projectId}.md`);
  if (fs.existsSync(obsoleteProjectFile)) fs.unlinkSync(obsoleteProjectFile);
  const obsoleteInstructionsDir = path.join(projectDir, 'instructions');
  if (fs.existsSync(obsoleteInstructionsDir)) {
    fs.rmSync(obsoleteInstructionsDir, { recursive: true, force: true });
  }
  // Limpia artefactos de nivel de proyecto que ahora van en carpeta general.
  const obsoleteGeneralFolder = path.join(projectDir, 'general');
  if (fs.existsSync(obsoleteGeneralFolder)) fs.rmSync(obsoleteGeneralFolder, { recursive: true, force: true });
  const obsoleteInstructionsFile = path.join(projectDir, 'instructions.md');
  if (fs.existsSync(obsoleteInstructionsFile)) fs.unlinkSync(obsoleteInstructionsFile);
  const obsoleteDeployFile = path.join(projectDir, 'deploy.sh');
  if (fs.existsSync(obsoleteDeployFile)) fs.unlinkSync(obsoleteDeployFile);

  const projectRoleArn = getExpectedRoleArn(accountId, qualifier);

  /**
   * Genera un único fichero de instrucciones para todos los usuarios del proyecto.
   */
  const projectInstructionsFile = path.join(generalDir, 'instructions.md');
  writeFile(projectInstructionsFile, [
    `# Instrucciones de acceso — ${projectId}`,
    '',
    `- Account ID: ${accountId}`,
    `- Qualifier: ${qualifier}`,
    `- Role de despliegue: ${projectRoleArn}`,
    '',
    '## ⚠️ IMPORTANTE',
    '**NO ejecutar bootstrap** — el administrador ya ha bootstrapped este proyecto.',
    '',
    '**Solo ejecutar `deploy.sh`** — es el único script que necesitas. Cualquier otro comando puede causar problemas.',
    '',
    '**Solo disponible en entorno DEV** — este proyecto está limitado a desarrollo. No hay stacks para producción.',
    '',
    '## Tags obligatorios',
    ...renderMarkdownList(requiredTags),
    '',
    '## Servicios disponibles en este proyecto',
    ...renderMarkdownList(allowedServices),
    '',
    '## Cómo desplegar',
    '1. Configura tu perfil AWS con las credenciales del archivo credentials-<tu-email>.json.',
    '2. Verifica acceso: `aws sts get-caller-identity --profile <PERFIL>`',
    '3. Copia deploy.sh a tu repo de infraestructura y sigue las instrucciones que contiene.',
    '',
    '## Reglas',
    '- No realizar cambios de infraestructura desde la consola AWS.',
    '- Incluir todos los tags obligatorios en cada recurso creado.',
    '- Todo despliegue debe hacerse mediante CDK usando el qualifier del proyecto.',
    ''
  ].join('\n'));

  /**
   * Genera artefactos por usuario del proyecto.
   */
  for (const user of allUsers) {
    const userDir = path.join(projectDir, `${projectId}-${user}`);
    ensureDir(userDir);

    const userRoles = getUserRolesForProject(user, developers, viewers, architects);
    const primaryRole = getPrimaryRole(userRoles);
    const roleLabel = getRoleLabel(userRoles);

    const roleArn = getExpectedRoleArn(accountId, qualifier);
    const safe = safeOutKeyName(user);

    const sourceKeyFile = path.join(outKeysDir, `${safe}.json`);
    const jsonTarget = path.join(userDir, `credentials-${user}.json`);
    const mdTarget = path.join(userDir, `credentials-${user}.md`);

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
      `# Credenciales — ${user}`,
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
      '- Si necesitas rotar credenciales, contacta con el administrador del proyecto.',    
      ''
    ].join('\n'));


  }

  /**
   * Genera un deploy.sh de referencia por proyecto.
   *
   * Este fichero es un punto de partida para que el desarrollador entienda
   * cómo desplegar su proyecto respetando el modelo de governance IAM:
   *   - Sus credenciales base solo permiten sts:AssumeRole (no tienen acceso
   *     directo a servicios AWS).
   *   - CDK asume automáticamente los roles bootstrap del qualifier usando
   *     esas credenciales base: no hay que asumir el role manualmente para
   *     el cdk deploy.
   *   - El stack CDK debe gestionar internamente operaciones adicionales como
   *     sync a S3 (via BucketDeployment) o invalidación de CloudFront.
   *
   * El desarrollador debe:
   *   1. Copiar este fichero a scripts/deploy.sh de su repo de infraestructura.
   *   2. Rellenar BASE_PROFILE con su perfil AWS.
   *   3. Ajustar REGION si no es eu-west-1.
   *   4. Sustituir el bloque TODO de build por los pasos reales de su proyecto.
   *   5. Asegurarse de que bin/app.ts usa DefaultStackSynthesizer con
   *      qualifier igual a QUALIFIER.
   */
  const deployScriptFile = path.join(generalDir, 'deploy.sh');
  writeFile(deployScriptFile, [
    '#!/usr/bin/env bash',
    `# deploy.sh — ${projectId}`,
    '#',
    '# iam-governance — deploy reference script',    
    '#',
    '# ─── Para el desarrollador ───────────────────────────────────────────────────',
    '#',
    '# ANTES DE USAR ESTE SCRIPT:',
    '#   1. Copia este fichero a scripts/deploy.sh de tu repo de infraestructura.',
    '#   2. Rellena BASE_PROFILE con el nombre de tu perfil AWS configurado en ~/.aws/config.',    
    '#   3. Ajusta REGION si tu proyecto no despliega en eu-west-1.',
    '#   4. Sustituye el bloque "TODO: build" por los comandos de build de tu proyecto.',
    '#      Ejemplos:',
    '#        Angular  → cd frontend/app && npm install && npx ng build --configuration=production && cd ../..',
    '#        Node/tsc → npm install && npm run build',
    '#        Python   → pip install -r requirements.txt',
    '#   5. Verifica que bin/app.ts (o equivalente) instancia DefaultStackSynthesizer',
    `#      con qualifier: '${qualifier}'.`,
    '#',
    '# CÓMO FUNCIONA EL ACCESO AWS:',
    '#   Tus credenciales base (BASE_PROFILE) solo tienen permiso sts:AssumeRole.',
    '#   No puedes llamar directamente a Lambda, S3, etc. con ellas.',
    '#   CDK detecta el qualifier del synthesizer y asume automáticamente los roles',
    `#   bootstrap del proyecto (cdk-${qualifier}-deploy-role, cdk-${qualifier}-file-publishing-role).`,
    '#   Todo el acceso a servicios AWS ocurre a través de esos roles asumidos.',
    '#',
    '# REQUISITOS EN TU MÁQUINA:',
    '#   - node, npm, npx  →  node --version',
    '#   - aws CLI         →  aws --version',
    '#   - jq              →  jq --version',
    '#   - Perfil AWS configurado en ~/.aws/credentials o ~/.aws/config',
    '#',
    '# USO:',
    `#   ./scripts/deploy.sh          → despliega en dev (por defecto)`,
    `#   ./scripts/deploy.sh dev      → despliega en dev`,
    `#   ./scripts/deploy.sh pre      → despliega en pre`,
    `#   ./scripts/deploy.sh pro      → despliega en pro`,
    '#',
    '# ─────────────────────────────────────────────────────────────────────────────',
    '',
    'set -euo pipefail',
    '',
    '# export es obligatorio: la variable ENV debe llegar al proceso hijo (node/CDK).',
    '# Sin export, process.env.ENV es undefined y CDK siempre despliega el entorno por defecto.',
    'export ENV="${1:-dev}"',
    '',
    `readonly PROJECT_ID="${projectId}"`,
    `readonly QUALIFIER="${qualifier}"`,
    `readonly TOOLKIT_STACK_NAME="${projectId}-cdk-toolkit"`,
    '',
    '# Nombre del perfil AWS configurado en ~/.aws/config o ~/.aws/credentials.',    
    'readonly BASE_PROFILE="<PERFIL_AWS>"',
    '',
    '# Ajustar si el proyecto despliega en otra región.',
    'readonly REGION="eu-west-1"',
    '',
    'echo "========================================"',
    `echo " Deploy : ${projectId}"`,
    'echo " Env    : $ENV"',
    'echo " Profile: $BASE_PROFILE"',
    'echo " Region : $REGION"',
    'echo "========================================"',
    '',
    '# Validación rápida del perfil antes de continuar.',
    'if ! aws sts get-caller-identity --profile "$BASE_PROFILE" > /dev/null 2>&1; then',
    '  echo "[ERROR] No se puede autenticar con el perfil $BASE_PROFILE"',
    '  echo "        Comprueba ~/.aws/credentials o ~/.aws/config"',
    '  exit 1',
    'fi',
    'echo "[OK] Credenciales base válidas"',
    '',
    '# ── TODO: build del proyecto ─────────────────────────────────────────────────',
    '# Sustituye este bloque por los pasos de build reales de tu proyecto.',
    '# Ejemplo Angular:',
    '#   cd frontend/app',
    '#   npm install',
    '#   npx ng build --configuration=production',
    '#   cd ../..',
    'echo "[INFO] Build... (añadir pasos reales aquí)"',
    '',
    '# ── CDK Deploy ───────────────────────────────────────────────────────────────',
    '# npm run build compila TypeScript a JavaScript antes del deploy.',
    'echo "[INFO] Build CDK TypeScript..."',
    'npm run build',
    '',
    '# cdk deploy usa las credenciales base del perfil y asume automáticamente',
    `# cdk-${qualifier}-deploy-role para orquestar el despliegue en CloudFormation.`,
    '# El stack debe tener el nombre "$PROJECT_ID-$ENV" (ej. meta-tech-provider-back-dev).',
    `echo "[INFO] CDK deploy (\${PROJECT_ID}-\${ENV})..."`,
    'npx cdk deploy "${PROJECT_ID}-${ENV}" \\',
    '  --profile "$BASE_PROFILE" \\',
    '  --region  "$REGION" \\',
    '  --toolkit-stack-name "$TOOLKIT_STACK_NAME" \\',
    '  --require-approval never',
    '',
    'echo "========================================"',
    'echo " Deploy completado: ${PROJECT_ID} (${ENV})"',
    'echo "========================================"',
    ''
  ].join('\n'));
}
NODE

echo "INFO: Results generados en $RESULTS_DIR"