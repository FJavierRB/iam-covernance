#!/usr/bin/env node
import * as cdk from 'aws-cdk-lib';
import { IamGovernanceStack } from '../lib/iam-governance-stack';

const app = new cdk.App();

// This stack only manages IAM resources and does not publish assets.
// Use CLI credentials synthesizer to deploy directly with the active AWS profile,
// avoiding dependency on broken bootstrap execution roles.
new IamGovernanceStack(app, 'IamGovernanceStack', {
	synthesizer: new cdk.CliCredentialsStackSynthesizer()
});