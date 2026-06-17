import { Stack, StackProps, CfnOutput } from 'aws-cdk-lib';
import * as iam from 'aws-cdk-lib/aws-iam';
import { Construct } from 'constructs';
import * as fs from 'fs';
import * as path from 'path';

/**
 * Relación de usuarios por rol dentro de un proyecto.
 * Un mismo usuario puede aparecer en más de un rol si así se define en configuración.
 */
type ProjectUsers = {
  developers?: string[];
  viewers?: string[];
  architects?: string[];
};

/**
 * Definición funcional de un proyecto gobernado por este stack.
 */
type ProjectSpec = {
  id: string;
  qualifier: string;
  logicalIdSeed?: string;
  env?: string;
  allowedServices: string[];
  requiredTagKeys: string[];
  users: ProjectUsers;
};

/**
 * Estructura del fichero config/projects.json.
 */
type ProjectsConfig = {
  projects: ProjectSpec[];
};

/**
 * Estructura del fichero config/prefix.json.
 */
type PrefixConfig = {
  pattern: string;
  accountId: string;
  separator: string;
  description: string;
};

/**
 * Estructura del fichero config/tags.json.
 */
type TagsConfig = {
  requiredTagKeys?: string[];
};

/**
 * Estructura del fichero config/groups.json.
 */
type GroupsConfig = {
  developers: {
    serviceToken: string;
  };
  viewers: {
    serviceToken: string;
  };
  architects: {
    serviceToken: string;
  };
};

/**
 * Estructura del fichero config/roles.json.
 */
type RolesConfig = {
  bootstrapAssumableRoleArnTemplate: {
    value: string;
  };
};

/**
 * Estructura del fichero config/policy-names.json.
 */
type PolicyNamesConfig = {
  cloudFormationExecution: {
    serviceToken: string;
  };
  architectsInline?: {
    serviceToken: string;
  };
};

/**
 * Estructura del fichero config/policies.json.
 */
type PoliciesConfig = {
  executionPolicy: {
    serviceActionsByService: Record<string, string[]>;
    additionalActions: string[];
    iamMinimalActions: string[];
    tagEnforcementCreateActionsByService: Record<string, string[]>;
  };
  developersGroupPolicy: {
    allowAssumeRoleActions: string[];
    denyEverythingExceptActions: string[];
  };
  viewersGroupPolicy: {
    readOnlyActions: string[];
  };
  architectsGroupPolicy: {
    allowAssumeRoleActions: string[];
    denyDirectServicesExceptActions: string[];
    bedrock?: string[];
  };
};

/**
 * Lee un fichero JSON y lo deserializa con el tipo esperado.
 */
function readJsonFile<T>(absolutePath: string): T {
  const raw = fs.readFileSync(absolutePath, 'utf-8');
  return JSON.parse(raw) as T;
}

/**
 * Convierte una cadena en un identificador seguro para Logical IDs auxiliares.
 */
function safeId(value: string): string {
  return value.replace(/[^a-zA-Z0-9]/g, '-');
}

/**
 * Genera un SID válido y acotado para statements IAM.
 */
function toSid(input: string): string {
  const sanitized = input.replace(/[^a-zA-Z0-9]/g, '');
  return sanitized.length > 0 ? sanitized.slice(0, 120) : 'SidDefault';
}

/**
 * Deriva el entorno lógico del proyecto.
 * Si el proyecto no lo define explícitamente, se intenta deducir desde el qualifier.
 */
function deriveEnv(project: ProjectSpec): string {
  if (project.env && project.env.trim().length > 0) {
    return project.env.trim().toLowerCase();
  }

  const match = project.qualifier.match(/(dev|qa|test|pre|pro|prod|prd)$/i);

  if (!match) {
    return 'dev';
  }

  const suffix = match[1].toLowerCase();
  return suffix === 'prod' ? 'pro' : suffix;
}

/**
 * Sanitiza un nombre IAM respetando caracteres válidos y longitud máxima.
 */
function sanitizeIamName(name: string, maxLen: number): string {
  return name
    .toLowerCase()
    .replace(/[^a-z0-9+=,.@-]/g, '')
    .slice(0, maxLen);
}

/**
 * Renderiza un nombre a partir del patrón de prefijo configurable.
 */
function renderPrefixName(
  pattern: string,
  env: string,
  projectToken: string,
  serviceToken: string
): string {
  const namePattern = pattern
    .replace('[env]', env)
    .replace('[proyecto]', projectToken)
    .replace('[servicio]', serviceToken);

  return namePattern.replace(/\[([^\]]+)\]/g, '$1');
}

/**
 * Extrae acciones IAM a partir de la lista de servicios permitidos del proyecto.
 */
function actionsFromServices(
  services: string[],
  byService: Record<string, string[]>
): string[] {
  const actions = new Set<string>();

  for (const service of services) {
    for (const action of byService[service] ?? []) {
      actions.add(action);
    }
  }

  return Array.from(actions.values());
}

/**
 * Devuelve una lista sin duplicados preservando el contenido como cadena.
 */
function uniq(values: string[]): string[] {
  return Array.from(
    new Set(values.filter((value) => value && value.trim().length > 0))
  );
}

/**
 * Obtiene el prefijo de servicio IAM a partir de una acción, por ejemplo:
 * - "lambda:CreateFunction" -> "lambda"
 * - "cloudformation:*" -> "cloudformation"
 */
function actionServicePrefix(action: string): string {
  const separatorIndex = action.indexOf(':');

  if (separatorIndex === -1) {
    return action.trim().toLowerCase();
  }

  return action.slice(0, separatorIndex).trim().toLowerCase();
}

/**
 * Determina qué servicios pueden usarse como acceso directo transversal para architects
 * sin depender de allowedServices de proyecto.
 *
 * Estos servicios son de soporte, observabilidad, coste o metadatos de despliegue.
 */
function isArchitectTransversalService(servicePrefix: string): boolean {
  return new Set([
    'sts',
    'cloudformation',
    'iam',
    'ce',
    'cloudwatch',
    'logs',
    'ssm'
  ]).has(servicePrefix);
}

/**
 * Filtra las acciones directas de architects para que:
 * - mantengan siempre las acciones transversales de soporte
 * - solo permitan acciones de servicios que estén en allowedServices del proyecto
 *
 * Esto evita que un architect de un proyecto obtenga permisos directos sobre
 * servicios ajenos a ese proyecto aunque la política global tenga más acciones declaradas.
 */
function filterArchitectDirectActions(
  configuredActions: string[],
  allowedServices: Set<string>
): string[] {
  const result = new Set<string>();

  for (const action of configuredActions) {
    const servicePrefix = actionServicePrefix(action);

    if (
      isArchitectTransversalService(servicePrefix) ||
      allowedServices.has(servicePrefix)
    ) {
      result.add(action);
    }
  }

  return Array.from(result.values());
}

/**
 * Obtiene las acciones directas que se quieren permitir realmente a developers,
 * excluyendo las acciones de asunción de roles que se gestionan en un statement separado.
 */
function extractDeveloperDirectActions(
  allowAssumeRoleActions: string[],
  denyEverythingExceptActions: string[]
): string[] {
  const allowAssumeSet = new Set(
    uniq((allowAssumeRoleActions ?? []).map((action) => action.trim()))
  );

  return uniq(
    (denyEverythingExceptActions ?? []).filter(
      (action) => !allowAssumeSet.has(action.trim())
    )
  );
}

export class IamGovernanceStack extends Stack {
  constructor(scope: Construct, id: string, props: StackProps = {}) {
    super(scope, id, props);

    /**
     * Carga todos los ficheros de configuración necesarios para construir el gobierno IAM.
     */
    const projectsFileRel: string =
      this.node.tryGetContext('projectsFile') ?? 'config/projects.json';
    const projectsFile = path.resolve(__dirname, '..', projectsFileRel);
    const projectsCfg = readJsonFile<ProjectsConfig>(projectsFile);

    const prefixFileRel: string =
      this.node.tryGetContext('prefixFile') ?? 'config/prefix.json';
    const prefixFile = path.resolve(__dirname, '..', prefixFileRel);
    const prefixCfg = readJsonFile<PrefixConfig>(prefixFile);

    const tagsFileRel: string =
      this.node.tryGetContext('tagsFile') ?? 'config/tags.json';
    const tagsFile = path.resolve(__dirname, '..', tagsFileRel);
    const tagsCfg = readJsonFile<TagsConfig>(tagsFile);

    const groupsFileRel: string =
      this.node.tryGetContext('groupsFile') ?? 'config/groups.json';
    const groupsFile = path.resolve(__dirname, '..', groupsFileRel);
    const groupsCfg = readJsonFile<GroupsConfig>(groupsFile);

    const rolesFileRel: string =
      this.node.tryGetContext('rolesFile') ?? 'config/roles.json';
    const rolesFile = path.resolve(__dirname, '..', rolesFileRel);
    const rolesCfg = readJsonFile<RolesConfig>(rolesFile);

    const policyNamesFileRel: string =
      this.node.tryGetContext('policyNamesFile') ?? 'config/policy-names.json';
    const policyNamesFile = path.resolve(__dirname, '..', policyNamesFileRel);
    const policyNamesCfg = readJsonFile<PolicyNamesConfig>(policyNamesFile);

    const policiesFileRel: string =
      this.node.tryGetContext('policiesFile') ?? 'config/policies.json';
    const policiesFile = path.resolve(__dirname, '..', policiesFileRel);
    const policiesCfg = readJsonFile<PoliciesConfig>(policiesFile);

    /**
     * Recorre todos los proyectos y crea por cada uno:
     * - policy de ejecución CloudFormation para el bootstrap CDK
     * - grupos IAM por rol
     * - permisos de asunción de roles bootstrap por qualifier
     * - permisos de acceso directo controlado para viewers y architects
     */
    for (const project of projectsCfg.projects) {
      const qualifier = project.qualifier;
      const logicalIdSeed = project.logicalIdSeed ?? qualifier;
      const projectId = project.id;
      const env = deriveEnv(project);

      /**
       * Nombres de grupos IAM por rol construidos desde el patrón de prefijo.
       */
      const developerGroupName = sanitizeIamName(
        renderPrefixName(
          prefixCfg.pattern,
          env,
          projectId,
          groupsCfg.developers.serviceToken
        ),
        128
      );

      const viewerGroupName = sanitizeIamName(
        renderPrefixName(
          prefixCfg.pattern,
          env,
          projectId,
          groupsCfg.viewers.serviceToken
        ),
        128
      );

      const architectGroupName = sanitizeIamName(
        renderPrefixName(
          prefixCfg.pattern,
          env,
          projectId,
          groupsCfg.architects.serviceToken
        ),
        128
      );

      /**
       * Nombre de la managed policy que se usará como execution policy del bootstrap CDK.
       */
      const executionPolicyName = sanitizeIamName(
        renderPrefixName(
          prefixCfg.pattern,
          env,
          projectId,
          policyNamesCfg.cloudFormationExecution.serviceToken
        ),
        128
      );

      /**
       * Normaliza y deduplica la lista de servicios permitidos para el proyecto.
       */
      const allowedServices = new Set<string>(
        uniq((project.allowedServices ?? []).map((service) => service.toLowerCase()))
      );

      /**
       * Construye el conjunto de acciones de servicios permitidas al execution role.
       * Estas acciones son las que podrá ejercer CloudFormation al desplegar recursos
       * del proyecto a través del bootstrap del qualifier correspondiente.
       */
      const allowedServiceActions = uniq([
        ...actionsFromServices(
          Array.from(allowedServices.values()),
          policiesCfg.executionPolicy.serviceActionsByService
        ),
        ...(policiesCfg.executionPolicy.additionalActions ?? [])
      ]);

      /**
       * Identifica las acciones CREATE sobre las que se aplicará enforcement de tags.
       */
      const createActions = actionsFromServices(
        Array.from(allowedServices.values()),
        policiesCfg.executionPolicy.tagEnforcementCreateActionsByService
      );

      /**
       * Une las tag keys globales y las específicas del proyecto, eliminando duplicados.
       */
      const requiredGlobalTagKeys = tagsCfg.requiredTagKeys ?? [];
      const requiredProjectTagKeys = project.requiredTagKeys ?? [];
      const requiredTagKeys = uniq([...requiredGlobalTagKeys, ...requiredProjectTagKeys]);

      /**
       * Crea la execution policy usada por el bootstrap CDK del qualifier del proyecto.
       * Esta policy controla qué puede ejecutar CloudFormation al desplegar recursos.
       */
      const executionPolicy = new iam.ManagedPolicy(
        this,
        `ExecPolicy-${safeId(logicalIdSeed)}`,
        {
          managedPolicyName: executionPolicyName,
          statements: [
            new iam.PolicyStatement({
              sid: toSid(`AllowServices${qualifier}`),
              effect: iam.Effect.ALLOW,
              actions: allowedServiceActions,
              resources: ['*']
            }),
            new iam.PolicyStatement({
              sid: toSid(`AllowIamMinimal${qualifier}`),
              effect: iam.Effect.ALLOW,
              actions: uniq(policiesCfg.executionPolicy.iamMinimalActions ?? []),
              resources: ['*']
            })
          ]
        }
      );

      /**
       * Añade permisos de control plane de API Gateway cuando el proyecto lo permite.
       * Se define en statement separado porque API Gateway usa ARNs particulares.
       */
      if (allowedServices.has('apigateway')) {
        executionPolicy.addStatements(
          new iam.PolicyStatement({
            sid: toSid(`AllowApiGatewayControlPlane${qualifier}`),
            effect: iam.Effect.ALLOW,
            actions: uniq([
              'apigateway:POST',
              'apigateway:PUT',
              'apigateway:PATCH',
              'apigateway:GET',
              'apigateway:DELETE',
              'apigateway:TagResource',
              'apigateway:UntagResource'
            ]),
            resources: [
              `arn:aws:apigateway:${this.region}::/restapis`,
              `arn:aws:apigateway:${this.region}::/restapis/*`,
              `arn:aws:apigateway:${this.region}::/tags/*`
            ]
          })
        );
      }

      /**
       * Fuerza la presencia de tags obligatorias en acciones de creación soportadas.
       * Se añade un DENY por cada tag requerida cuando no venga informada en RequestTag.
       * Se excluyen los roles bootstrap de CDK (cdk-*) porque son recursos técnicos
       * internos y CDK no envía RequestTag al crearlos.
       */
      if (createActions.length > 0 && requiredTagKeys.length > 0) {
        for (let index = 0; index < requiredTagKeys.length; index += 1) {
          const tagKey = requiredTagKeys[index];

          executionPolicy.addStatements(
            new iam.PolicyStatement({
              sid: toSid(`DenyCreateWithout${qualifier}${tagKey}${index}`),
              effect: iam.Effect.DENY,
              actions: uniq(createActions),
              resources: ['*'],
              conditions: {
                Null: {
                  [`aws:RequestTag/${tagKey}`]: 'true'
                },
                StringNotLike: {
                  'aws:PrincipalArn': 'arn:aws:iam::*:role/cdk-*'
                }
              }
            })
          );
        }
      }

      /**
       * Expone por salida el ARN de la policy de ejecución generada para el proyecto.
       */
      new CfnOutput(this, `ExecPolicyArn-${safeId(logicalIdSeed)}`, {
        value: executionPolicy.managedPolicyArn,
        description: `ARN policy ejecución CloudFormation para qualifier=${qualifier} proyecto ${projectId}`
      });

      /**
       * Crea los grupos IAM por rol del proyecto.
       */
      const developerGroup = new iam.Group(
        this,
        `DevGroup-${safeId(logicalIdSeed)}`,
        {
          groupName: developerGroupName
        }
      );

      const viewerGroup = new iam.Group(
        this,
        `ViewerGroup-${safeId(logicalIdSeed)}`,
        {
          groupName: viewerGroupName
        }
      );

      const architectGroup = new iam.Group(
        this,
        `ArchitectGroup-${safeId(logicalIdSeed)}`,
        {
          groupName: architectGroupName
        }
      );

      /**
       * Construye el patrón ARN de roles bootstrap que cada proyecto puede asumir.
       * Cada grupo del proyecto queda limitado al qualifier correspondiente.
       */
      const assumeRoleArn = rolesCfg.bootstrapAssumableRoleArnTemplate.value
        .replace('[accountId]', this.account)
        .replace('[qualifier]', qualifier);

      /**
       * Developers:
       * - pueden asumir roles bootstrap del qualifier del proyecto
       * - pueden leer metadatos mínimos del bootstrap en SSM para que CDK valide la versión
       * - se mantiene el DENY para cualquier otra acción directa no permitida
       */
      developerGroup.addToPolicy(
        new iam.PolicyStatement({
          sid: toSid(`AllowAssumeOnlyProjectBootstrapRoles${qualifier}`),
          effect: iam.Effect.ALLOW,
          actions: uniq(policiesCfg.developersGroupPolicy.allowAssumeRoleActions ?? []),
          resources: [assumeRoleArn]
        })
      );

      /**
       * Se extraen las acciones directas permitidas realmente a developers.
       * En tu caso actual esto habilita las lecturas SSM del bootstrap que CDK necesita
       * antes de asumir el role de despliegue.
       */
      const developerDirectActions = extractDeveloperDirectActions(
        policiesCfg.developersGroupPolicy.allowAssumeRoleActions ?? [],
        policiesCfg.developersGroupPolicy.denyEverythingExceptActions ?? []
      );

      /**
       * Acciones SSM que pueden acotarse al path del bootstrap del qualifier.
       */
      const developerSsmParameterReadActions = developerDirectActions.filter(
        (action) =>
          actionServicePrefix(action) === 'ssm' &&
          action !== 'ssm:DescribeParameters'
      );

      /**
       * Acciones SSM que requieren Resource="*".
       */
      const developerSsmDescribeActions = developerDirectActions.filter(
        (action) => action === 'ssm:DescribeParameters'
      );

      /**
       * Permite a developers leer únicamente el path SSM del bootstrap del qualifier del proyecto.
       */
      if (developerSsmParameterReadActions.length > 0) {
        developerGroup.addToPolicy(
          new iam.PolicyStatement({
            sid: toSid(`AllowDeveloperBootstrapSsmRead${qualifier}`),
            effect: iam.Effect.ALLOW,
            actions: uniq(developerSsmParameterReadActions),
            resources: [
              `arn:aws:ssm:${this.region}:${this.account}:parameter/cdk-bootstrap/${qualifier}`,
              `arn:aws:ssm:${this.region}:${this.account}:parameter/cdk-bootstrap/${qualifier}/*`
            ]
          })
        );
      }

      /**
       * Permite describir parámetros SSM a nivel global cuando así se haya configurado.
       */
      if (developerSsmDescribeActions.length > 0) {
        developerGroup.addToPolicy(
          new iam.PolicyStatement({
            sid: toSid(`AllowDeveloperBootstrapSsmDescribe${qualifier}`),
            effect: iam.Effect.ALLOW,
            actions: uniq(developerSsmDescribeActions),
            resources: ['*']
          })
        );
      }

      /**
       * Deniega todo lo que no esté expresamente exceptuado en notActions.
       * Esto mantiene el modelo estricto de developers.
       */
      developerGroup.addToPolicy(
        new iam.PolicyStatement({
          sid: toSid(`DenyDirectCloudFormationAndCoreServices${qualifier}`),
          effect: iam.Effect.DENY,
          notActions: uniq(
            policiesCfg.developersGroupPolicy.denyEverythingExceptActions ?? []
          ),
          resources: ['*']
        })
      );

      /**
       * Viewers:
       * - permisos de solo lectura definidos en configuración
       */
      viewerGroup.addToPolicy(
        new iam.PolicyStatement({
          sid: toSid(`AllowViewerConfiguredReadOnly${qualifier}`),
          effect: iam.Effect.ALLOW,
          actions: uniq(policiesCfg.viewersGroupPolicy.readOnlyActions ?? []),
          resources: ['*']
        })
      );

      /**
       * Architects:
       * - pueden asumir roles bootstrap del qualifier del proyecto
       * - mantienen acciones transversales de soporte
       * - sus acciones directas sobre servicios del proyecto se filtran por allowedServices
       *
       * Esto evita que un architect de un proyecto reciba permisos directos sobre
       * servicios no autorizados para ese proyecto.
       *
       * También se incorpora la propiedad opcional "bedrock" del JSON de políticas,
       * que antes estaba definida pero no se utilizaba en el stack.
       */
      const architectConfiguredActions = uniq([
        ...(policiesCfg.architectsGroupPolicy.denyDirectServicesExceptActions ?? []),
        ...(policiesCfg.architectsGroupPolicy.bedrock ?? [])
      ]);

      const architectDirectActions = filterArchitectDirectActions(
        architectConfiguredActions,
        allowedServices
      );

      architectGroup.addToPolicy(
        new iam.PolicyStatement({
          sid: toSid(`AllowArchitectAssumeBootstrapRoles${qualifier}`),
          effect: iam.Effect.ALLOW,
          actions: uniq(policiesCfg.architectsGroupPolicy.allowAssumeRoleActions ?? []),
          resources: [assumeRoleArn]
        })
      );

      if (architectDirectActions.length > 0) {
        architectGroup.addToPolicy(
          new iam.PolicyStatement({
            sid: toSid(`AllowArchitectConfiguredDirectActions${qualifier}`),
            effect: iam.Effect.ALLOW,
            actions: architectDirectActions,
            resources: ['*']
          })
        );
      }

      /**
       * Expone nombres de grupos por salida para uso operativo y scripts.
       */
      new CfnOutput(this, `ArchitectGroupName-${safeId(logicalIdSeed)}`, {
        value: architectGroup.groupName,
        description: `Nombre del grupo architects para proyecto ${projectId}`
      });

      new CfnOutput(this, `DevGroupName-${safeId(logicalIdSeed)}`, {
        value: developerGroup.groupName,
        description: `Nombre del grupo developers para proyecto ${projectId}`
      });

      new CfnOutput(this, `ViewerGroupName-${safeId(logicalIdSeed)}`, {
        value: viewerGroup.groupName,
        description: `Nombre del grupo viewers para proyecto ${projectId}`
      });
    }
  }
}