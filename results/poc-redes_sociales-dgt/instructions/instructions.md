# Instrucciones del proyecto

<!-- Archivo generado por scripts/50_generate_results.sh -->
<!-- Uso: entregar a usuarios de este proyecto como guia operativa -->

Proyecto: poc-redes_sociales-dgt
Account ID: 887977137036
Qualifier: dgtdev

## Reglas operativas
- No usar consola para cambios de infraestructura (solo CDK/IaC).
- Usar siempre el qualifier del proyecto en DefaultStackSynthesizer.
- Usar perfil de assume-role para desplegar.
- Cumplir todos los tags obligatorios.

## Configuracion local recomendada
1. Configurar credenciales base en ~/.aws/credentials (entregadas por admin).
2. Configurar profile de despliegue apuntando a arn:aws:iam::887977137036:role/cdk-dgtdev-cfn-exec.
3. Verificar sesion: aws sts get-caller-identity.

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
