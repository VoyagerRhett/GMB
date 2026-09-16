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
