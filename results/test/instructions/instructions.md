# Instrucciones del proyecto test

<!-- Archivo de ejemplo ficticio para validar formato de results -->
<!-- Uso: guia operativa del proyecto para todos los usuarios -->

Proyecto: test
Account ID: 111122223333
Qualifier: tstdev

## Reglas operativas
- No usar consola para cambios de infraestructura (solo CDK/IaC).
- Usar siempre el qualifier del proyecto en DefaultStackSynthesizer.
- Usar perfil de assume-role para desplegar.
- Cumplir todos los tags obligatorios.

## Configuracion local recomendada
1. Configurar credenciales base en ~/.aws/credentials.
2. Configurar profile de despliegue a arn:aws:iam::111122223333:role/cdk-tstdev-cfn-exec.
3. Verificar sesion: aws sts get-caller-identity.

## Comandos base
export AWS_PROFILE=test-project
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
