import assert from 'node:assert/strict';
import test from 'node:test';
import {
  compareSemanticVersions, expectedSemanticCandidate, nextSemanticVersion, parseSemanticVersion,
} from './version.mjs';

test('CitizenApp两端Release共用唯一语义版本实现', () => {
  assert.deepEqual(parseSemanticVersion('1.2.3'), [1, 2, 3]);
  assert.equal(compareSemanticVersions('1.2.3', '1.2.4'), -1);
  assert.equal(nextSemanticVersion('1.99.99'), '2.0.0');
  assert.equal(expectedSemanticCandidate('1.0.0', ['1.0.0', '1.0.2']), '1.0.3');
  assert.throws(() => parseSemanticVersion('1.100.0'), /软件版本/u);
});
