# Instrucciones para viewer.test1@example.com

<!-- Archivo de ejemplo ficticio para validar formato de results -->
<!-- Uso: guia personalizada por usuario -->

- Proyecto: test
- Rol: viewers
- Account ID: 111122223333
- Qualifier: tstdev
- Role ARN: arn:aws:iam::111122223333:role/cdk-tstdev-cfn-exec

## Que debes saber
- Tu acceso es de lectura en consola y consulta.
- No puedes desplegar infraestructura.
- Si necesitas cambios, coordinarlos con un usuario developer.

## Pasos minimos
1. Configura tus credenciales de consulta.
2. Verifica sesion con aws sts get-caller-identity.
3. Usa la consola en modo lectura o CLI de consulta.
