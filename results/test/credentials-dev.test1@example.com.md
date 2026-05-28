# Credenciales de dev.test1@example.com

<!-- Archivo de ejemplo ficticio para validar formato de results -->
<!-- Uso: hoja de entrega de credenciales de un usuario -->

- Proyecto: test
- Rol: developers
- Qualifier: tstdev
- Role ARN a asumir: arn:aws:iam::111122223333:role/cdk-tstdev-cfn-exec
- Archivo de credenciales JSON: credentials-dev.test1@example.com.json

## Nota de seguridad
- El JSON puede contener secreto. No subir a git ni enviar por canales no seguros.
- Si necesitas rotar credenciales, pedir al admin ejecutar scripts/40_create_access_keys.sh --rotate.
