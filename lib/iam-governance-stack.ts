import { Stack, StackProps, CfnOutput } from 'aws-cdk-lib';
import * as iam from 'aws-cdk-lib/aws-iam';
import { Construct } from 'constructs';
import * as fs from 'fs';
import * as path from 'path';

type ProjectUsers = {
  developers?: string[];
  viewers?: string[];
  architects?: string[];
};

type ProjectSpec = {
  id: string;
  qualifier: string;
  env?: string;
  allowedServices: string[];
  requiredTagKeys: string[];
  users: ProjectUsers;
};

type ProjectsConfig = {
  projects: ProjectSpec[];
};

type PrefixConfig = {
  pattern: string;
  accountId: string;
  separator: string;
  description: string;
};

type TagsConfig = {
  requiredTagKeys?: string[];
};

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

type RolesConfig = {
  bootstrapAssumableRoleArnTemplate: {
    value: string;
  };
};

type PolicyNamesConfig = {
  cloudFormationExecution: {
    serviceToken: string;
  };
};

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
  };
};

function readJsonFile<T>(absolutePath: string): T {
  const raw = fs.readFileSync(absolutePath, 'utf-8');
  return JSON.parse(raw) as T;
}

function safeId(s: string): string {
  return s.replace(/[^a-zA-Z0-9]/g, '-');
}

function toSid(input: string): string {
  const sanitized = input.replace(/[^a-zA-Z0-9]/g, '');
  return sanitized.length > 0 ? sanitized.slice(0, 120) : 'SidDefault';
}

function deriveEnv(project: ProjectSpec): string {
  if (project.env && project.env.trim().length > 0) {
    return project.env.trim().toLowerCase();
  }

  const m = project.qualifier.match(/(dev|qa|test|pre|pro|prod|prd)$/i);
  if (!m) {
    return 'dev';
  }

  const suffix = m[1].toLowerCase();
  return suffix === 'prod' ? 'pro' : suffix;
}

function sanitizeIamName(name: string, maxLen: number): string {
  return name.toLowerCase().replace(/[^a-z0-9+=,.@-]/g, '').slice(0, maxLen);
}

function renderPrefixName(pattern: string, env: string, projectToken: string, serviceToken: string): string {
  const namePattern = pattern
    .replace('[env]', env)
    .replace('[proyecto]', projectToken)
    .replace('[servicio]', serviceToken);

  return namePattern.replace(/\[([^\]]+)\]/g, '$1');
}

function actionsFromServices(services: string[], byService: Record<string, string[]>): string[] {
  const set = new Set<string>();
  for (const service of services) {
    const actions = byService[service] ?? [];
    for (const action of actions) {
      set.add(action);
    }
  }

  return Array.from(set.values());
}

export class IamGovernanceStack extends Stack {
  constructor(scope: Construct, id: string, props: StackProps = {}) {
    super(scope, id, props);

    const projectsFileRel: string = this.node.tryGetContext('projectsFile') ?? 'config/projects.json';
    const projectsFile = path.resolve(__dirname, '..', projectsFileRel);
    const cfg = readJsonFile<ProjectsConfig>(projectsFile);

    const prefixFileRel: string = this.node.tryGetContext('prefixFile') ?? 'config/prefix.json';
    const prefixFile = path.resolve(__dirname, '..', prefixFileRel);
    const prefixCfg = readJsonFile<PrefixConfig>(prefixFile);

    const tagsFileRel: string = this.node.tryGetContext('tagsFile') ?? 'config/tags.json';
    const tagsFile = path.resolve(__dirname, '..', tagsFileRel);
    const tagsCfg = readJsonFile<TagsConfig>(tagsFile);

    const groupsFileRel: string = this.node.tryGetContext('groupsFile') ?? 'config/groups.json';
    const groupsFile = path.resolve(__dirname, '..', groupsFileRel);
    const groupsCfg = readJsonFile<GroupsConfig>(groupsFile);

    const rolesFileRel: string = this.node.tryGetContext('rolesFile') ?? 'config/roles.json';
    const rolesFile = path.resolve(__dirname, '..', rolesFileRel);
    const rolesCfg = readJsonFile<RolesConfig>(rolesFile);

    const policyNamesFileRel: string = this.node.tryGetContext('policyNamesFile') ?? 'config/policy-names.json';
    const policyNamesFile = path.resolve(__dirname, '..', policyNamesFileRel);
    const policyNamesCfg = readJsonFile<PolicyNamesConfig>(policyNamesFile);

    const policiesFileRel: string = this.node.tryGetContext('policiesFile') ?? 'config/policies.json';
    const policiesFile = path.resolve(__dirname, '..', policiesFileRel);
    const policiesCfg = readJsonFile<PoliciesConfig>(policiesFile);

    /*
      =====================================================
      1) Para cada proyecto:
         - Creamos ManagedPolicy para CloudFormation Execution Role (usada en bootstrap con --qualifier).
         - Creamos grupos IAM por proyecto usando el patrón de naming de prefix.json
         - Creamos usuarios (email como userName) y los metemos en su grupo.
         - Muy importante:
             los devs SOLO pueden asumir roles cdk-<qualifier>-*
             si no ponen qualifier (default hnb659fds) o ponen otro, NO pueden asumir roles y no despliegan.
      =====================================================
    */

    for (const project of cfg.projects) {
      const q = project.qualifier;
      const pid = project.id;
      const env = deriveEnv(project);

      const devGroupName = sanitizeIamName(
        renderPrefixName(prefixCfg.pattern, env, pid, groupsCfg.developers.serviceToken),
        128
      );
      const viewerGroupName = sanitizeIamName(
        renderPrefixName(prefixCfg.pattern, env, pid, groupsCfg.viewers.serviceToken),
        128
      );
      const architectGroupName = sanitizeIamName(
        renderPrefixName(prefixCfg.pattern, env, pid, groupsCfg.architects.serviceToken),
        128
      );
      const execPolicyName = sanitizeIamName(
        renderPrefixName(prefixCfg.pattern, env, pid, policyNamesCfg.cloudFormationExecution.serviceToken),
        128
      );

      const allowedServiceActions = actionsFromServices(
        project.allowedServices,
        policiesCfg.executionPolicy.serviceActionsByService
      );
      for (const action of policiesCfg.executionPolicy.additionalActions ?? []) {
        allowedServiceActions.push(action);
      }

      const createActions = actionsFromServices(
        project.allowedServices,
        policiesCfg.executionPolicy.tagEnforcementCreateActionsByService
      );

      const requiredGlobalTags = tagsCfg.requiredTagKeys ?? [];
      const requiredProjectTags = project.requiredTagKeys ?? [];
      const requiredTagKeys = Array.from(new Set([...requiredGlobalTags, ...requiredProjectTags]));

      // ---------- A) Managed Policy por proyecto para el CloudFormation execution role ----------
      const execPolicy = new iam.ManagedPolicy(this, `ExecPolicy-${safeId(q)}`, {
        managedPolicyName: execPolicyName,
        statements: [
          new iam.PolicyStatement({
            sid: toSid(`AllowServices${q}`),
            effect: iam.Effect.ALLOW,
            actions: Array.from(new Set(allowedServiceActions)),
            resources: ['*']
          }),

          new iam.PolicyStatement({
            sid: toSid(`AllowIamMinimal${q}`),
            effect: iam.Effect.ALLOW,
            actions: policiesCfg.executionPolicy.iamMinimalActions,
            resources: ['*']
          })
        ]
      });

      if (createActions.length > 0) {
        for (let i = 0; i < requiredTagKeys.length; i += 1) {
          const tagKey = requiredTagKeys[i];
          execPolicy.addStatements(
            new iam.PolicyStatement({
              sid: toSid(`DenyCreateWithout${q}${tagKey}${i}`),
              effect: iam.Effect.DENY,
              actions: createActions,
              resources: ['*'],
              conditions: {
                Null: {
                  [`aws:RequestTag/${tagKey}`]: 'true'
                }
              }
            })
          );
        }
      }

      new CfnOutput(this, `ExecPolicyArn-${safeId(q)}`, {
        value: execPolicy.managedPolicyArn,
        description: `ARN policy ejecución CloudFormation para qualifier=${q} (proyecto ${pid})`
      });

      // ---------- B) Grupos por proyecto ----------
      const devGroup = new iam.Group(this, `DevGroup-${safeId(q)}`, {
        groupName: devGroupName
      });

      const viewerGroup = new iam.Group(this, `ViewerGroup-${safeId(q)}`, {
        groupName: viewerGroupName
      });

      const architectGroup = new iam.Group(this, `ArchitectGroup-${safeId(q)}`, {
        groupName: architectGroupName
      });

      // Dev: SOLO AssumeRole a roles del bootstrap de SU qualifier
      const assumeRoleArn = rolesCfg.bootstrapAssumableRoleArnTemplate.value
        .replace('[accountId]', this.account)
        .replace('[qualifier]', q);

      devGroup.addToPolicy(
        new iam.PolicyStatement({
          sid: toSid(`AllowAssumeOnlyProjectBootstrapRoles${q}`),
          effect: iam.Effect.ALLOW,
          actions: policiesCfg.developersGroupPolicy.allowAssumeRoleActions,
          resources: [assumeRoleArn]
        })
      );

      devGroup.addToPolicy(
        new iam.PolicyStatement({
          sid: toSid(`DenyDirectCloudFormationAndCoreServices${q}`),
          effect: iam.Effect.DENY,
          notActions: policiesCfg.developersGroupPolicy.denyEverythingExceptActions,
          resources: ['*']
        })
      );

      viewerGroup.addToPolicy(
        new iam.PolicyStatement({
          sid: toSid(`AllowViewerCloudFormationDescribe${q}`),
          effect: iam.Effect.ALLOW,
          actions: policiesCfg.viewersGroupPolicy.readOnlyActions,
          resources: ['*']
        })
      );

      // Architect: AssumeRole sobre roles bootstrap del qualifier + lectura transversal
      architectGroup.addToPolicy(
        new iam.PolicyStatement({
          sid: toSid(`AllowArchitectAssumeBootstrapRoles${q}`),
          effect: iam.Effect.ALLOW,
          actions: policiesCfg.architectsGroupPolicy.allowAssumeRoleActions,
          resources: [assumeRoleArn]
        })
      );

      architectGroup.addToPolicy(
        new iam.PolicyStatement({
          sid: toSid(`AllowArchitectReadTransversal${q}`),
          effect: iam.Effect.ALLOW,
          actions: policiesCfg.architectsGroupPolicy.denyDirectServicesExceptActions,
          resources: ['*']
        })
      );

      new CfnOutput(this, `ArchitectGroupName-${safeId(q)}`, {
        value: architectGroup.groupName,
        description: `Nombre del grupo architects para proyecto ${pid}`
      });

      new CfnOutput(this, `DevGroupName-${safeId(q)}`, {
        value: devGroup.groupName,
        description: `Nombre del grupo developers para proyecto ${pid}`
      });

      new CfnOutput(this, `ViewerGroupName-${safeId(q)}`, {
        value: viewerGroup.groupName,
        description: `Nombre del grupo viewers para proyecto ${pid}`
      });
    }
  }
}
