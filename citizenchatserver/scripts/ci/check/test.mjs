import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import test from 'node:test';

test('gmb.citizenchatserver.cloudflare.ci的扁平check远端Job物理独立', () => {
  const source = readFileSync(new URL('./execute.mjs', import.meta.url), 'utf8');
  assert.ok(source.includes('{"pipeline":"gmb.citizenchatserver.cloudflare.ci","job":"check"}'));
  assert.match(source, /function runExactWorkflowStep\(index\)/u);
  assert.match(source, /function requireExactRemoteJobEnvironment\(\)/u);
  assert.match(source, /action --instance citizenchatserver --output/u);
  assert.doesNotMatch(source, /action \\\\n/u);
});

// 中文注释：实际 Workflow 只保留本仓检查与配置候选生成，不给 CI 注入上游 Secret。
test('CI 单阶段只检查本仓并生成配置候选，未配置任何上游凭据', () => {
  const source = readFileSync(new URL('./execute.mjs', import.meta.url), 'utf8');
  const steps = JSON.parse(source.match(/const workflowSteps = Object.freeze\((\{[^\n]+\})\);/u)[1]);
  assert.deepEqual(Object.keys(steps), ['0']);
  assert.match(steps['0'].source, /git rev-parse HEAD/u);
  assert.match(steps['0'].source, /node --test/u);
  assert.match(steps['0'].source, / action --instance citizenchatserver/u);
  assert.ok(steps['0'].source.indexOf('node --test') < steps['0'].source.indexOf(' action '));
  assert.doesNotMatch(steps['0'].source, /gh |release|curl|wget|TOKEN/u);
  const workflow = readFileSync(new URL('../../../../.github/workflows/citizenchatserver-cloudflare-ci.yml', import.meta.url), 'utf8');
  const check = workflow.split('  flow:')[1];
  assert.doesNotMatch(check, /secrets[.]|GH_TOKEN|GITHUB_TOKEN|workflow-step 1|VoyagerRhett\/TATA/u);
  assert.match(check, /workflow-step 0/u);
  assert.match(check, /CitizenChatServer-Cloudflare-CI/u);
});
