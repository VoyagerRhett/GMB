import assert from 'node:assert/strict';
import { spawnSync } from 'node:child_process';
import { readFileSync } from 'node:fs';
import test from 'node:test';
import { jobIdentity as android, workflowSteps as androidSteps } from './android.mjs';
import { jobIdentity as ios, workflowSteps as iosSteps } from './ios.mjs';

test('CitizenApp两个Release Job保留准确身份且共用唯一版本实现', () => {
  assert.deepEqual([android, ios].map(value => `${value.pipeline}:${value.job}`).sort(), [
    'gmb.citizenapp.android.release:android', 'gmb.citizenapp.ios.release:ios',
  ]);
  for (const steps of [androidSteps, iosSteps]) {
    assert.ok(Object.values(steps).some(step => step.source.includes('scripts/release/version.mjs')));
    for (const step of Object.values(steps)) {
      const result = spawnSync('/bin/bash', ['-n'], { input: step.source, encoding: 'utf8' });
      assert.equal(result.status, 0, result.stderr);
    }
  }
});

test('CitizenApp Release Workflow只引用两个扁平平台Job', () => {
  const workflow = readFileSync(new URL('../../../.github/workflows/repository.yml', import.meta.url), 'utf8');
  assert.match(workflow, /citizenapp\/scripts\/release\/android[.]mjs/u);
  assert.match(workflow, /citizenapp\/scripts\/release\/ios[.]mjs/u);
  assert.doesNotMatch(workflow, /citizenapp\/scripts\/release\/(?:android|ios)\//u);
  const sources = ['./android.mjs', './ios.mjs'].map(path => readFileSync(new URL(path, import.meta.url), 'utf8'));
  for (const source of sources) assert.doesNotMatch(source, /github-release|function runExactWorkflowStep/u);
});
