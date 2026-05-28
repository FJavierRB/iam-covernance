Scripts del repo iam-governance

Requisitos:
- Node + npm
- AWS CLI
- CDK v2 (se usa via npx)
- Profile AWS configurado (por defecto cap7036)

Variables opcionales:
- AWS_PROFILE (default: cap7036)
- AWS_REGION  (default: eu-west-1)

Orden recomendado de ejecucion (admin):
1) AWS_PROFILE=cap7036 ./scripts/10_deploy_iam_governance.sh
2) AWS_PROFILE=cap7036 ./scripts/20_bootstrap_all_projects.sh
3) AWS_PROFILE=cap7036 ./scripts/30_status.sh
4) AWS_PROFILE=cap7036 ./scripts/40_create_access_keys.sh
5) AWS_PROFILE=cap7036 ./scripts/45_export_keys_csv.sh

Notas:
- scripts/10_deploy_iam_governance.sh ahora ejecuta tambien scripts/15_sync_new_users.sh.
- scripts/15_sync_new_users.sh crea usuarios nuevos y actualiza membresias de usuarios existentes.
- El bootstrap no se repite si ya existe /cdk-bootstrap/<qualifier>/version, salvo que uses --force.
