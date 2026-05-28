# iam-governance

Gestion de usuarios IAM, grupos por proyecto, politicas y bootstraps CDK por proyecto (multi-bootstrap con qualifiers) en una sola cuenta AWS.

Objetivo: que cada equipo despliegue solo sus proyectos via CDK, usando roles cdk-<qualifier>-*, con naming y politicas centralizadas por JSON y con procesos idempotentes.

## Tabla de contenidos

- Resumen
- Estructura del repositorio
- Configuracion
- Flujo de administracion
- Que ocurre al dar de alta un proyecto
- Que ocurre al dar de alta un usuario
- Flujo del equipo de desarrollo
- Entrega de artefactos para usuarios
- Operaciones habituales
- Troubleshooting

## Resumen

Este repositorio implementa y opera governance IAM de esta forma:

1. El stack CDK lee configuracion desde la carpeta config:
   - projects.json
   - prefix.json
   - tags.json
   - groups.json
   - roles.json
   - policy-names.json
   - policies.json
2. Crea por proyecto:
   - Managed policy de CloudFormation Execution con nombre derivado del patron de prefix.json y policy-names.json.
   - Grupo developers con nombre derivado de prefix.json y groups.json.
   - Grupo viewers con nombre derivado de prefix.json y groups.json.
   - Reglas IAM de ambos grupos usando policies.json y roles.json.
3. El alta y sincronizacion de usuarios se hace con scripts/15_sync_new_users.sh:
   - Si el usuario no existe: se crea y se asigna a todos sus grupos.
   - Si el usuario ya existe: se actualizan sus membresías de grupo (agregar nuevos, remover los que ya no corresponde).
   - Un mismo usuario puede estar en múltiples proyectos con rol diferentes (developer en uno, viewer en otro).
   - Cada usuario obtiene permisos según su rol y grupo en cada proyecto.
4. El hardening de consola se aplica con scripts/16_enforce_console_mode.sh:
   - Usuarios en developers: sin login profile de consola.
   - Usuarios solo viewers: mantienen uso de consola en modo lectura segun politica.
5. El bootstrap CDK se gestiona por qualifier con scripts/20_bootstrap_all_projects.sh.

## Estructura del repositorio

```text
iam-governance/
├── bin/
│   └── app.ts
├── lib/
│   └── iam-governance-stack.ts
├── config/
│   ├── projects.json
│   ├── prefix.json
│   ├── tags.json
│   ├── groups.json
│   ├── roles.json
│   ├── policy-names.json
│   └── policies.json
├── scripts/
│   ├── common.sh
│   ├── 10_deploy_iam_governance.sh
│   ├── 15_sync_new_users.sh
│   ├── 16_enforce_console_mode.sh
│   ├── 20_bootstrap_all_projects.sh
│   ├── 30_status.sh
│   ├── 40_create_access_keys.sh
│   ├── 45_export_keys_csv.sh
│   └── 50_generate_results.sh
├── results/
│   └── <project-id>/
│       ├── <project-id>.md
│       ├── credentials-<usuario>.md
│       ├── credentials-<usuario>.json
│       └── instructions/
│           ├── instructions.md
│           └── instructions-<usuario>.md
└── cdk.json
```

## Configuracion

### projects.json

Define proyectos, qualifier, servicios permitidos, tags obligatorias por proyecto y usuarios.

Ejemplo:

```json
{
  "projects": [
    {
      "id": "poc-redes_sociales-dgt",
      "qualifier": "dgtdev",
      "allowedServices": ["lambda", "dynamodb", "sqs", "apigateway"],
      "requiredTagKeys": ["owner", "autor_infra", "proyecto", "cliente", "cost_center", "entorno"],
      "users": {
        "developers": ["dev1@capgemini.com"],
        "viewers": ["viewer1@capgemini.com"]
      }
    }
  ]
}
```

### prefix.json

Patron global de nombres. Se usa para generar nombres de grupos y politicas.

### groups.json

Define los tokens de servicio usados para construir nombre de grupos (developers/viewers).

### policy-names.json

Define el token de servicio para el nombre de la managed policy de ejecucion.

### policies.json

Define el contenido funcional de las politicas:
- acciones por servicio permitido
- acciones IAM minimas
- acciones de enforcement de tags
- acciones de developers
- acciones de viewers

### roles.json

Define plantillas de ARN, por ejemplo el patron de roles bootstrap asumibles por developers.

### tags.json

Define claves de tags globales obligatorias. El stack aplica la union entre:
- tags globales de tags.json
- tags por proyecto de projects.json

## Flujo de administracion

Orden recomendado (admin):

```bash
AWS_PROFILE=cap7036 ./scripts/10_deploy_iam_governance.sh
AWS_PROFILE=cap7036 ./scripts/20_bootstrap_all_projects.sh
AWS_PROFILE=cap7036 ./scripts/30_status.sh
AWS_PROFILE=cap7036 ./scripts/40_create_access_keys.sh
AWS_PROFILE=cap7036 ./scripts/45_export_keys_csv.sh
```

Detalles:

1. scripts/10_deploy_iam_governance.sh
   - Ejecuta npm ci o npm install.
   - Ejecuta cdk synth, cdk diff y cdk deploy.
   - Al terminar, ejecuta scripts/15_sync_new_users.sh.
   - Despues ejecuta scripts/16_enforce_console_mode.sh.
2. scripts/15_sync_new_users.sh
   - Lee usuarios y grupos objetivo desde config/projects.json y naming de config.
   - Crea usuarios que no existen en IAM y los asigna a sus grupos.
   - Usuarios existentes: actualiza sus membresias de grupo (agrega nuevos grupos, elimina los que ya no corresponden).
3. scripts/16_enforce_console_mode.sh
   - Elimina login profile de consola a usuarios developers.
   - Mantiene a usuarios viewers en modo lectura de consola.
4. scripts/20_bootstrap_all_projects.sh
   - Hace bootstrap por qualifier.
   - Detecta si ya estaba bootstrap y hace skip (salvo --force).
   - Usa la managed policy generada por configuracion como execution policy.
5. scripts/30_status.sh
   - Muestra por proyecto: qualifier, env, policy esperada y estado bootstrap.
6. scripts/50_generate_results.sh
   - Genera artefactos operativos por proyecto en results/<project-id>/.
   - Crea archivos por usuario (credentials-<usuario>.md/json, instructions-<usuario>.md).
   - Crea archivos de proyecto (instructions/instructions.md y <project-id>.md).

## Que ocurre al dar de alta un proyecto

Cuando anades un proyecto en config/projects.json y ejecutas el flujo:

1. El stack crea (o actualiza) los recursos de governance del proyecto:
   - managed policy de ejecucion
   - grupo developers
   - grupo viewers
2. El script de usuarios crea solo los usuarios nuevos definidos en ese proyecto.
3. El bootstrap crea los roles cdk-<qualifier>-* si ese qualifier no estaba bootstrap.
4. Si el qualifier ya existia, bootstrap hace skip por idempotencia.

## Que ocurre al dar de alta un usuario

Cuando añades un email en projects.json y ejecutas scripts/10_deploy_iam_governance.sh:

1. Se despliega/actualiza governance con CDK.
2. scripts/15_sync_new_users.sh revisa cada email configurado:
   - Usuario no existe en IAM:
     - create-user
     - add-user-to-group segun corresponda (developers/viewers)
   - Usuario ya existe en IAM:
     - Actualiza sus membresias de grupo (agrega nuevos grupos, elimina los que ya no corresponden)

Nota importante: este comportamiento evita tocar identidades existentes por seguridad operativa.

## Flujo del equipo de desarrollo

### Modelo de acceso

Los desarrolladores en el grupo developers:
- NO tienen login profile de consola (hardening).
- SOLO pueden desplegar via CDK asumiendo el rol de bootstrap del qualifier.
- NO tienen permisos directos a servicios AWS (todo a traves del rol asumido).

### Pre-requisitos (admin configura una sola vez)

1. El desarrollador esta en el grupo developers del proyecto (via config/projects.json).
2. El qualifier del proyecto ya esta bootstrappeado (scripts/20_bootstrap_all_projects.sh).
3. El desarrollador tiene credenciales temporales (STS) con acceso a sts:AssumeRole sobre el rol bootstrap.

### Procedimiento para el desarrollador

En el repo de infraestructura de cada proyecto:

1. Usar el mismo qualifier del proyecto en DefaultStackSynthesizer.
2. Aplicar los tags obligatorios requeridos.
3. Asumir el rol de despliegue CDK.

Opcion 1: manual con credenciales temporales:

```bash
ACCOUNT_ID=<tu-account-id>
QUALIFIER=dgtdev
ROLE_ARN="arn:aws:iam::$ACCOUNT_ID:role/cdk-$QUALIFIER-cfn-exec"

CREDENTIALS=$(aws sts assume-role \
  --role-arn "$ROLE_ARN" \
  --role-session-name deploy-session \
  --duration-seconds 3600)

export AWS_ACCESS_KEY_ID=$(echo "$CREDENTIALS" | jq -r '.Credentials.AccessKeyId')
export AWS_SECRET_ACCESS_KEY=$(echo "$CREDENTIALS" | jq -r '.Credentials.SecretAccessKey')
export AWS_SESSION_TOKEN=$(echo "$CREDENTIALS" | jq -r '.Credentials.SessionToken')
```

Opcion 2: perfil AWS automatizado (recomendado). En ~/.aws/config:

```ini
[profile deploy-myproject]
role_arn = arn:aws:iam::ACCOUNT_ID:role/cdk-QUALIFIER-cfn-exec
source_profile = default
duration_seconds = 3600
```

Luego:

```bash
export AWS_PROFILE=deploy-myproject
```

4. Desplegar con CDK:

```bash
npm install
npx cdk synth
npx cdk diff
npx cdk deploy
```

### Consideraciones importantes

- El rol asumido es temporal (default 3600 segundos, 1 hora).
- Las credenciales temporales se borran del entorno al terminar.
- La consola AWS no es accesible para developers (no tienen login profile).
- Todo cambio de infraestructura debe ir a traves de CDK y git.
- Si falta un tag obligatorio, CDK fallará al desplegar (por la politica de Deny).

## Entrega de artefactos para usuarios

La documentacion operativa para usuarios finales ya no se mantiene en este README.

Despues de ejecutar el flujo de administracion, el script scripts/50_generate_results.sh genera:
- results/<project-id>/<project-id>.md con datos del proyecto (Account ID, qualifier, servicios, tags).
- results/<project-id>/instructions/instructions.md con guia de operacion del proyecto.
- results/<project-id>/instructions/instructions-<usuario>.md con guia personalizada por usuario.
- results/<project-id>/credentials-<usuario>.md con contexto de acceso por usuario.
- results/<project-id>/credentials-<usuario>.json con credenciales o placeholder confidencial.

## Operaciones habituales

### Anadir usuarios a un proyecto

1. Editar config/projects.json.
2. Ejecutar:

```bash
AWS_PROFILE=cap7036 ./scripts/10_deploy_iam_governance.sh
```

Opcional, para credenciales de largo plazo (para assume-role sin MFA):

```bash
AWS_PROFILE=cap7036 ./scripts/40_create_access_keys.sh
```

### Usuarios en múltiples proyectos con roles diferentes

Un mismo usuario (identificado por su correo) puede estar en varios proyectos con roles diferentes:

**Ejemplo en config/projects.json:**

```json
{
  "projects": [
    {
      "id": "proyecto-infra",
      "qualifier": "infradev",
      "users": {
        "developers": ["alice@company.com"],
        "viewers": []
      }
    },
    {
      "id": "proyecto-apps",
      "qualifier": "appsdev",
      "users": {
        "developers": [],
        "viewers": ["alice@company.com"]
      }
    }
  ]
}
```

En este caso, `alice@company.com`:
- **En proyecto-infra**: pertenece al grupo `dev-*-infra-developers` → puede desplegar con qualifier `infradev`.
- **En proyecto-apps**: pertenece al grupo `dev-*-apps-viewers` → acceso solo lectura con qualifier `appsdev`.

**Comportamiento de sincronizacion:**

1. Primera vez que se ejecuta `scripts/15_sync_new_users.sh`: se crea el usuario y se añade a ambos grupos.
2. Si añades el usuario a un nuevo proyecto: se ejecuta `scripts/15_sync_new_users.sh` nuevamente y automáticamente:
   - Añade el usuario a los nuevos grupos del proyecto.
   - Mantiene su pertenencia a grupos anteriores.
3. Si quitas el usuario de un proyecto: se ejecuta `scripts/15_sync_new_users.sh` y automáticamente:
   - Remueve el usuario de los grupos de ese proyecto.
   - Mantiene su pertenencia a grupos de otros proyectos.

**Proceso para añadir usuario a un nuevo proyecto:**

1. Editar config/projects.json e incluir el usuario en `users.developers` o `users.viewers` del nuevo proyecto.
2. Ejecutar:

```bash
AWS_PROFILE=cap7036 ./scripts/10_deploy_iam_governance.sh
AWS_PROFILE=cap7036 ./scripts/15_sync_new_users.sh
```

El usuario recibirá automáticamente los permisos del nuevo proyecto según su rol (developer o viewer).

### Anadir un proyecto nuevo

1. Editar config/projects.json con id, qualifier, allowedServices, requiredTagKeys y users.
2. Ejecutar:

```bash
AWS_PROFILE=cap7036 ./scripts/10_deploy_iam_governance.sh
AWS_PROFILE=cap7036 ./scripts/20_bootstrap_all_projects.sh
```

### Cambiar servicios permitidos o politicas

1. Editar config/policies.json (y/o projects.json).
2. Ejecutar:

```bash
AWS_PROFILE=cap7036 ./scripts/10_deploy_iam_governance.sh
AWS_PROFILE=cap7036 ./scripts/20_bootstrap_all_projects.sh --force
```

### Rotar access keys

```bash
AWS_PROFILE=cap7036 ./scripts/40_create_access_keys.sh --rotate
```

### Regenerar artefactos de entrega (manual)

```bash
AWS_PROFILE=cap7036 bash ./scripts/50_generate_results.sh
```

## Troubleshooting

### Error: no existe la policy al hacer bootstrap

Ejecuta antes:

```bash
AWS_PROFILE=cap7036 ./scripts/10_deploy_iam_governance.sh
```

### Error: environment not bootstrapped

Ejecuta:

```bash
AWS_PROFILE=cap7036 ./scripts/20_bootstrap_all_projects.sh
```

### AccessDenied al desplegar con developer

Revisa:
1. Que el developer esta en el grupo developers del proyecto.
2. Que el qualifier es correcto y coincide en el repo del proyecto.
3. Que el qualifier fue bootstrappeado.
4. Que el rol asumido es el correcto: arn:aws:iam::ACCOUNT_ID:role/cdk-QUALIFIER-cfn-exec

### Error: falta un tag obligatorio en deploy

Todos los recursos crear (Lambda, DynamoDB, SQS, API Gateway) deben tener los tags definidos en requiredTagKeys.

Edita tu CDK stack para aplicar:

```ts
cdk.Tags.of(app).add('owner', '...');
cdk.Tags.of(app).add('autor_infra', '...');
cdk.Tags.of(app).add('proyecto', '...');
cdk.Tags.of(app).add('cliente', '...');
cdk.Tags.of(app).add('cost_center', '...');
cdk.Tags.of(app).add('entorno', '...');
```
