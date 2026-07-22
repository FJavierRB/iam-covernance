# Instrucciones de acceso — meta-tech-provider-front

- Account ID: 887977137036
- Qualifier: mtpdevfrt
- Role de despliegue: arn:aws:iam::887977137036:role/cdk-mtpdevfrt-cfn-exec

## ⚠️ IMPORTANTE
**NO ejecutar bootstrap** — el administrador ya ha bootstrapped este proyecto.

**Solo ejecutar `deploy.sh`** — es el único script que necesitas. Cualquier otro comando puede causar problemas.

**Solo disponible en entorno DEV** — este proyecto está limitado a desarrollo. No hay stacks para producción.

## Tags obligatorios
- owner
- autor_infra
- proyecto
- cliente
- cost_center
- entorno
- ecr

## Servicios disponibles en este proyecto
- cloudfront
- s3
- lambda
- apigateway
- logs

## Cómo desplegar
1. Configura tu perfil AWS con las credenciales del archivo credentials-<tu-email>.json.
2. Verifica acceso: `aws sts get-caller-identity --profile <PERFIL>`
3. Copia deploy.sh a tu repo de infraestructura y sigue las instrucciones que contiene.

## Reglas
- No realizar cambios de infraestructura desde la consola AWS.
- Incluir todos los tags obligatorios en cada recurso creado.
- Todo despliegue debe hacerse mediante CDK usando el qualifier del proyecto.
