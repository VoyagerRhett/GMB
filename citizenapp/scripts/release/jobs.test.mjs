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
  for (const platform of ['android', 'ios']) {
    const workflow = readFileSync(new URL(`../../../.github/workflows/citizenapp-${platform}-release.yml`, import.meta.url), 'utf8');
    assert.match(workflow, new RegExp(`citizenapp/scripts/release/${platform}[.]mjs`, 'u'));
    assert.doesNotMatch(workflow, /citizenapp\/scripts\/release\/(?:android|ios)\//u);
  }
  const sources = ['./android.mjs', './ios.mjs'].map(path => readFileSync(new URL(path, import.meta.url), 'utf8'));
  for (const source of sources) assert.doesNotMatch(source, /github-release|function runExactWorkflowStep/u);
});


test('Android Release的Pub、Gradle与产物回读消费同一轮目录', () => {
  assert.match(androidSteps['6'].source, /create-android/u);
  assert.match(androidSteps['7'].source, /project="\$CITIZENAPP_PROJECT_ROOT"/u);
  assert.match(androidSteps['7'].source, /CITIZENAPP_PROJECT_ROOT/u);
  assert.match(androidSteps['7'].source, /CITIZENAPP_BUILD_DIR/u);
  assert.match(androidSteps['7'].source, /ln -s "\$build" "\$project\/build"/u);
  assert.match(androidSteps['8'].source, /^cd "\$CITIZENAPP_PROJECT_ROOT"/u);
  assert.match(androidSteps['9'].source, /citizenapp\/build\/app\/outputs/u);
  assert.match(iosSteps['5'].source, /citizenapp-view\.mjs/u);
});
