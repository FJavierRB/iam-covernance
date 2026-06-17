# Instrucciones del proyecto

<!-- Archivo generado por scripts/50_generate_results.sh -->
<!-- Uso: entregar a usuarios de este proyecto como guia operativa -->

Proyecto: poc-redes-sociales-dgt
Account ID: 887977137036
Qualifier: dgtdev

## Reglas operativas
- No usar consola para cambios de infraestructura.
- Usar siempre el qualifier del proyecto en el sintetizador CDK.
- Utilizar el modelo de acceso definido para el proyecto y sus roles.
- Cumplir todos los tags obligatorios del proyecto.

## Configuracion local recomendada
1. Configurar credenciales base en ~/.aws/credentials si aplica.
2. Configurar el acceso al role documentado por el sistema: arn:aws:iam::887977137036:role/cdk-dgtdev-cfn-exec.
3. Verificar la sesion con aws sts get-caller-identity.

## Comandos base
export AWS_PROFILE=<perfil_proyecto>
npm install
npx cdk synth
npx cdk diff
npx cdk deploy

## Tags obligatorios del proyecto
- owner
- autor_infra
- proyecto
- cliente
- cost_center
- entorno
