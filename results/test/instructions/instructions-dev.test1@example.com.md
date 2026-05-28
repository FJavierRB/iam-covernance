# Instrucciones para dev.test1@example.com

<!-- Archivo de ejemplo ficticio para validar formato de results -->
<!-- Uso: guia personalizada por usuario -->

- Proyecto: test
- Rol: developers
- Account ID: 111122223333
- Qualifier: tstdev
- Role ARN: arn:aws:iam::111122223333:role/cdk-tstdev-cfn-exec

## Que debes saber
- No puedes operar infraestructura por consola.
- Debes desplegar con CDK asumiendo el role ARN indicado.
- Debes incluir los tags obligatorios del proyecto en tus stacks.

## Pasos minimos
1. Configura ~/.aws/credentials con tus credenciales base.
2. Configura ~/.aws/config con profile de assume-role para este proyecto.
3. Ejecuta deploy con AWS_PROFILE del proyecto.

## Tags obligatorios
- owner
- autor_infra
- proyecto
- cliente
- cost_center
- entorno
