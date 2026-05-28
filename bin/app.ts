#!/usr/bin/env node
import * as cdk from 'aws-cdk-lib';
import { IamGovernanceStack } from '../lib/iam-governance-stack';

const app = new cdk.App();
new IamGovernanceStack(app, 'IamGovernanceStack', {});