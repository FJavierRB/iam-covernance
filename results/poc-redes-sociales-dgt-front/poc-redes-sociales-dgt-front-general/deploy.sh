#!/usr/bin/env bash
# deploy.sh — poc-redes-sociales-dgt-front
#
# iam-governance — deploy reference script
#
# ─── Para el desarrollador ───────────────────────────────────────────────────
#
# ANTES DE USAR ESTE SCRIPT:
#   1. Copia este fichero a scripts/deploy.sh de tu repo de infraestructura.
#   2. Rellena BASE_PROFILE con el nombre de tu perfil AWS configurado en ~/.aws/config.
#   3. Ajusta REGION si tu proyecto no despliega en eu-west-1.
#   4. Sustituye el bloque "TODO: build" por los comandos de build de tu proyecto.
#      Ejemplos:
#        Angular  → cd frontend/app && npm install && npx ng build --configuration=production && cd ../..
#        Node/tsc → npm install && npm run build
#        Python   → pip install -r requirements.txt
#   5. Verifica que bin/app.ts (o equivalente) instancia DefaultStackSynthesizer
#      con qualifier: 'dgtdevspa'.
#
# CÓMO FUNCIONA EL ACCESO AWS:
#   Tus credenciales base (BASE_PROFILE) solo tienen permiso sts:AssumeRole.
#   No puedes llamar directamente a Lambda, S3, etc. con ellas.
#   CDK detecta el qualifier del synthesizer y asume automáticamente los roles
#   bootstrap del proyecto (cdk-dgtdevspa-deploy-role, cdk-dgtdevspa-file-publishing-role).
#   Todo el acceso a servicios AWS ocurre a través de esos roles asumidos.
#
# REQUISITOS EN TU MÁQUINA:
#   - node, npm, npx  →  node --version
#   - aws CLI         →  aws --version
#   - jq              →  jq --version
#   - Perfil AWS configurado en ~/.aws/credentials o ~/.aws/config
#
# USO:
#   ./scripts/deploy.sh          → despliega en dev (por defecto)
#   ./scripts/deploy.sh dev      → despliega en dev
#   ./scripts/deploy.sh pre      → despliega en pre
#   ./scripts/deploy.sh pro      → despliega en pro
#
# ─────────────────────────────────────────────────────────────────────────────

set -euo pipefail

# export es obligatorio: la variable ENV debe llegar al proceso hijo (node/CDK).
# Sin export, process.env.ENV es undefined y CDK siempre despliega el entorno por defecto.
export ENV="${1:-dev}"

readonly PROJECT_ID="poc-redes-sociales-dgt-front"
readonly QUALIFIER="dgtdevspa"
readonly TOOLKIT_STACK_NAME="poc-redes-sociales-dgt-front-cdk-toolkit"

# Nombre del perfil AWS configurado en ~/.aws/config o ~/.aws/credentials.
readonly BASE_PROFILE="<PERFIL_AWS>"

# Ajustar si el proyecto despliega en otra región.
readonly REGION="eu-west-1"

echo "========================================"
echo " Deploy : poc-redes-sociales-dgt-front"
echo " Env    : $ENV"
echo " Profile: $BASE_PROFILE"
echo " Region : $REGION"
echo "========================================"

# Validación rápida del perfil antes de continuar.
if ! aws sts get-caller-identity --profile "$BASE_PROFILE" > /dev/null 2>&1; then
  echo "[ERROR] No se puede autenticar con el perfil $BASE_PROFILE"
  echo "        Comprueba ~/.aws/credentials o ~/.aws/config"
  exit 1
fi
echo "[OK] Credenciales base válidas"

# ── TODO: build del proyecto ─────────────────────────────────────────────────
# Sustituye este bloque por los pasos de build reales de tu proyecto.
# Ejemplo Angular:
#   cd frontend/app
#   npm install
#   npx ng build --configuration=production
#   cd ../..
echo "[INFO] Build... (añadir pasos reales aquí)"

# ── CDK Deploy ───────────────────────────────────────────────────────────────
# npm run build compila TypeScript a JavaScript antes del deploy.
echo "[INFO] Build CDK TypeScript..."
npm run build

# cdk deploy usa las credenciales base del perfil y asume automáticamente
# cdk-dgtdevspa-deploy-role para orquestar el despliegue en CloudFormation.
# El stack debe tener el nombre "$PROJECT_ID-$ENV" (ej. meta-tech-provider-back-dev).
echo "[INFO] CDK deploy (${PROJECT_ID}-${ENV})..."
npx cdk deploy "${PROJECT_ID}-${ENV}" \
  --profile "$BASE_PROFILE" \
  --region  "$REGION" \
  --toolkit-stack-name "$TOOLKIT_STACK_NAME" \
  --require-approval never

echo "========================================"
echo " Deploy completado: ${PROJECT_ID} (${ENV})"
echo "========================================"
