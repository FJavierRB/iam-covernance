# comandos.md

## 1) Para el administrador (-<qualifier>, viewer-<qualifier>)## 1) Para el administrador (cuenta única)
- crea usuarios y los asigna a su proyecto
- crea policies de ejecución CloudFormation por proyecto: CdkCfnExec_<qualifier>
- crea los bootstraps por qualifier (roles/bucket/ssm por qualifier)

## 2) Para cada proyecto (repo de infraestructura del proyecto)

### 2.1 Obligatorio: fijar el qualifier del proyecto en el código
En el repo del proyecto, en el StackProps (o en bin/app.ts), usar DefaultStackSynthesizer con el qualifier que le corresponde.
Ejemplo (en bin/app.ts):

new MiStack(app, 'MiStack', {
  synthesizer: new DefaultStackSynthesizer({ qualifier: '<QUALIFIER_DEL_PROYECTO>' })
});

El qualifier debe coincidir con el definido en config/projects.json.

### 2.2 Obligatorio: aplicar las keys de tags requeridas (con valores del proyecto)
Cada proyecto debe aplicar las keys de tagging requeridas (owner, autor_infra, proyecto, cliente, cost_center, entorno) con sus valores reales.
Recomendación: a nivel App o Stack:
Tags.of(app).add('owner', '...');
Tags.of(app).add('autor_infra', '...');
Tags.of(app).add('proyecto', '...');
Tags.of(app).add('cliente', '...');
Tags.of(app).add('cost_center', '...');
Tags.of(app).add('entorno', '...');

### 2.3 Comandos de despliegue (developer)
El developer debe usar su propio profile AWS (sus access keys), por ejemplo:
AWS_PROFILE=<perfil_del_developer>

Comandos típicos:
- npm install
- npx cdk synth --profile $AWS_PROFILE
- npx cdk diff  --profile $AWS_PROFILE
- npx cdk deploy --profile $AWS_PROFILE

Si el developer intenta desplegar usando otro qualifier distinto:
- no podrá asumir roles cdk-<qualifier>-* porque IAM sólo permite los de su proyecto.

## 3) Añadir usuarios/proyectos nuevos

### 3.1 Añadir usuarios a un proyecto existente
Editar config/projects.json -> users.developers o users.viewers
Luego:
- AWS_PROFILE=cap7036 ./scripts/10_deploy_iam_governance.sh

### 3.2 Añadir un nuevo proyecto (nuevo qualifier)
Añadir un nuevo bloque en config/projects.json con:
- id
- qualifier
- allowedServices
- requiredTagKeys
- users

Luego:
- AWS_PROFILE=cap7036 ./scripts/10_deploy_iam_governance.sh
- AWS_PROFILE=cap7036 ./scripts/20_bootstrap_all_projects.sh

### 1.1 Desplegar IAM governance (usuarios/grupos/policies)
Desde el repo iam-governance:

- AWS_PROFILE=cap7036 ./scripts/10_deploy_iam_governance.sh
- AWS_PROFILE=cap7036 ./scripts/20_bootstrap_all_projects.sh
- AWS_PROFILE=cap7036 ./scripts/30_status.sh

Esto:
