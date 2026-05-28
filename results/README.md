# results

<!-- Carpeta de artefactos de entrega para usuarios por proyecto -->
<!-- Generada por scripts/50_generate_results.sh -->

Estructura esperada por proyecto:
- <project-id>/<project-id>.md
- <project-id>/credentials-<usuario>.md
- <project-id>/credentials-<usuario>.json (confidencial)
- <project-id>/instructions/instructions.md
- <project-id>/instructions/instructions-<usuario>.md

Uso:
1. Ejecutar deploy admin (scripts/10_deploy_iam_governance.sh) o manual scripts/50_generate_results.sh.
2. Entregar al usuario su paquete del proyecto correspondiente.
3. No subir secretos (credentials-*.json) a git.
