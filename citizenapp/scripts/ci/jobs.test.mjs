import assert from 'node:assert/strict';
import { spawnSync } from 'node:child_process';
import { readFileSync } from 'node:fs';
import test from 'node:test';
import { jobIdentity as android, workflowSteps as androidSteps } from './android.mjs';
import { jobIdentity as androidCheck, workflowSteps as androidCheckSteps } from './android-check.mjs';
import { jobIdentity as ios, workflowSteps as iosSteps } from './ios.mjs';
import { jobIdentity as iosCheck, workflowSteps as iosCheckSteps } from './ios-check.mjs';
import { runWorkflow } from '../workflow.mjs';

const jobs = [
  [android, androidSteps], [androidCheck, androidCheckSteps],
  [ios, iosSteps], [iosCheck, iosCheckSteps],
];

test('CitizenApp四个CI Job保留准确独立身份且共用唯一执行器', async () => {
  assert.deepEqual(jobs.map(([identity]) => `${identity.pipeline}:${identity.job}`).sort(), [
    'gmb.citizenapp.android.ci:android', 'gmb.citizenapp.android.ci:check',
    'gmb.citizenapp.ios.ci:check', 'gmb.citizenapp.ios.ci:ios',
  ]);
  for (const [, steps] of jobs) {
    for (const step of Object.values(steps)) {
      const result = spawnSync('/bin/bash', ['-n'], { input: step.source, encoding: 'utf8' });
      assert.equal(result.status, 0, result.stderr);
    }
  }
  await assert.rejects(runWorkflow(ios, iosSteps, {}, {
    argumentsList: ['workflow-step', '999'], environment: { GITHUB_REPOSITORY: 'VoyagerRhett/GMB' },
  }), /阶段无效/u);
  await assert.rejects(runWorkflow(ios, iosSteps, {}, {
    argumentsList: ['workflow-step', '0'], environment: { GITHUB_REPOSITORY: 'VoyagerRhett/TATA' },
  }), /仓库身份/u);
});

test('CitizenApp CI Workflow只引用六层内的唯一扁平文件', () => {
  const workflow = readFileSync(new URL('../../../.github/workflows/repository.yml', import.meta.url), 'utf8');
  for (const name of ['android.mjs', 'android-check.mjs', 'ios.mjs', 'ios-check.mjs']) {
    assert.match(workflow, new RegExp(`citizenapp/scripts/ci/${name.replace('.', '[.]')}`, 'u'));
  }
  assert.doesNotMatch(workflow, /citizenapp\/scripts\/ci\/(?:android|ios)\//u);
  for (const source of ['./android.mjs', './android-check.mjs', './ios.mjs', './ios-check.mjs']
    .map(path => readFileSync(new URL(path, import.meta.url), 'utf8'))) {
    assert.doesNotMatch(source, /function cacheIdentity|function runExactWorkflowStep/u);
  }
});
