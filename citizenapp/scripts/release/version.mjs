#!/usr/bin/env node

import { execFileSync } from 'node:child_process';
import { readFileSync } from 'node:fs';
import { pathToFileURL } from 'node:url';

const semanticVersionPattern = /^(0|[1-9]\d*)\.(0|[1-9]\d?)\.(0|[1-9]\d?)$/;
const tagPrefixPattern = /^[a-z0-9][a-z0-9-]*-v$/;
const sourceSHAPattern = /^[0-9a-f]{40}$/;

export function parseSemanticVersion(value) {
  const match = semanticVersionPattern.exec(String(value));
  if (!match) throw new Error(`软件版本必须形如 a.b.c 且 b、c 不超过 99：${value}`);
  return match.slice(1).map(Number);
}

export function compareSemanticVersions(left, right) {
  const a = parseSemanticVersion(left);
  const b = parseSemanticVersion(right);
  for (let index = 0; index < 3; index += 1) {
    if (a[index] !== b[index]) return a[index] - b[index];
  }
  return 0;
}

export function nextSemanticVersion(value) {
  let [major, minor, patch] = parseSemanticVersion(value);
  patch += 1;
  if (patch > 99) {
    patch = 0;
    minor += 1;
  }
  if (minor > 99) {
    minor = 0;
    major += 1;
  }
  return `${major}.${minor}.${patch}`;
}

export function expectedSemanticCandidate(seed, successfulVersions) {
  parseSemanticVersion(seed);
  const normalized = [...new Set(successfulVersions.map((value) => {
    parseSemanticVersion(value);
    return value;
  }))].sort(compareSemanticVersions);
  return normalized.length === 0 ? seed : nextSemanticVersion(normalized.at(-1));
}

function parseArguments(argv) {
  const [command, ...rest] = argv;
  if (!command) throw new Error('缺少版本命令');
  const values = {};
  for (let index = 0; index < rest.length; index += 2) {
    const key = rest[index];
    const value = rest[index + 1];
    if (!key?.startsWith('--') || value === undefined) throw new Error(`参数格式无效：${key ?? ''}`);
    const name = key.slice(2);
    if (Object.hasOwn(values, name)) throw new Error(`参数重复：${key}`);
    values[name] = value;
  }
  return { command, values };
}

function requireExactKeys(values, required, optional = []) {
  const allowed = new Set([...required, ...optional]);
  for (const key of Object.keys(values)) {
    if (!allowed.has(key)) throw new Error(`不支持的参数：--${key}`);
  }
  for (const key of required) {
    if (!Object.hasOwn(values, key) || values[key] === '') throw new Error(`缺少参数：--${key}`);
  }
}

function ghJSON(path) {
  const output = execFileSync('gh', ['api', path], {
    encoding: 'utf8', stdio: ['ignore', 'pipe', 'pipe'],
  });
  try {
    return JSON.parse(output);
  } catch {
    throw new Error(`GitHub API 返回了无效 JSON：${path}`);
  }
}

function readSeed(path) {
  const text = readFileSync(path, 'utf8');
  const matches = [...text.matchAll(/^version:\s*([^+\s]+)(?:\+\d+)?\s*$/gm)];
  if (matches.length !== 1) throw new Error(`pubspec 软件版本真源不唯一：${path}`);
  parseSemanticVersion(matches[0][1]);
  return matches[0][1];
}

function publishedSemanticVersions(prefix) {
  if (!tagPrefixPattern.test(prefix)) throw new Error('Tag 前缀无效');
  const escaped = prefix.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
  const pattern = new RegExp(`^${escaped}(${semanticVersionPattern.source.slice(1, -1)})$`);
  const versions = [];
  for (let page = 1; page <= 100; page += 1) {
    const releases = ghJSON(`repos/{owner}/{repo}/releases?per_page=100&page=${page}`);
    if (!Array.isArray(releases)) throw new Error('GitHub Release 列表格式无效');
    for (const release of releases) {
      if (release?.draft === true || release?.prerelease === true) continue;
      const tag = String(release?.tag_name || '');
      if (!tag.startsWith(prefix)) continue;
      const match = pattern.exec(tag);
      if (!match) throw new Error(`同前缀正式 Release Tag 不符合统一版本契约：${tag}`);
      parseSemanticVersion(match[1]);
      versions.push(match[1]);
    }
    if (releases.length < 100) return versions;
  }
  throw new Error('GitHub Release 列表超过安全分页上限');
}

function validateIdentity(values) {
  if (values['product-id'] !== 'citizenapp') throw new Error('product_id 无效');
  if (!['ios', 'android'].includes(values.target)) throw new Error('target 无效');
  if (values.workflow !== `gmb.citizenapp.${values.target}.ci`) throw new Error('workflow 无效');
  if (values.prefix !== `citizenapp-${values.target}-v`) throw new Error('Tag 前缀无效');
  if (!sourceSHAPattern.test(values['source-sha'])) throw new Error('source_sha 无效');
  if (!/^[1-9]\d*$/.test(values['ci-run-id'])) throw new Error('ci_run_id 无效');
}

function verifySuccessfulCIRun(values) {
  validateIdentity(values);
  const expectedTitle = values.target === 'ios' ? '公民 · iOS · CI' : '公民 · Android · CI';
  const run = ghJSON(`repos/{owner}/{repo}/actions/runs/${values['ci-run-id']}`);
  if (run.status !== 'completed' || run.conclusion !== 'success'
    || run.event !== 'workflow_dispatch' || run.head_branch !== 'main'
    || run.head_sha !== values['source-sha']
    || String(run.display_title || '') !== expectedTitle
    || !String(run.path || '').endsWith('/repository.yml')) {
    throw new Error('Release 来源不是同产品、同端、同 workflow 的成功 CI');
  }
  const head = execFileSync('git', ['rev-parse', 'HEAD'], { encoding: 'utf8' }).trim();
  if (head !== values['source-sha']) throw new Error(`checkout 与 source_sha 不一致：${head}`);
}

function printNextSemanticRelease(values) {
  requireExactKeys(values, ['prefix', 'seed']);
  const candidate = expectedSemanticCandidate(
    values.seed,
    publishedSemanticVersions(values.prefix),
  );
  process.stdout.write(`${candidate}\n`);
}

function verifyReleaseSource(values) {
  requireExactKeys(values, [
    'version-tag', 'source-sha', 'ci-run-id', 'prefix', 'product-id', 'target', 'workflow',
  ]);
  if (!tagPrefixPattern.test(values.prefix)
    || !values['version-tag'].startsWith(values.prefix)
    || !/^[a-z0-9][a-z0-9.-]*$/.test(values['version-tag'])) {
    throw new Error('Release 版本 Tag 身份无效');
  }
  verifySuccessfulCIRun(values);
  const suffix = values['version-tag'].slice(values.prefix.length);
  parseSemanticVersion(suffix);
  const expected = expectedSemanticCandidate(
    readSeed('citizenapp/pubspec.yaml'),
    publishedSemanticVersions(values.prefix),
  );
  if (suffix !== expected) {
    throw new Error(`Release 版本不是正式 Release 真源的下一版本：期望 ${expected}，收到 ${suffix}`);
  }
  process.stdout.write(`Release 已锁定成功 CI：${values['ci-run-id']} · ${values['source-sha']}\n`);
}

export function main(argv) {
  const { command, values } = parseArguments(argv);
  if (command === 'next-semantic-release') return printNextSemanticRelease(values);
  if (command === 'verify-release-source') return verifyReleaseSource(values);
  throw new Error(`不支持的版本命令：${command}`);
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  try {
    main(process.argv.slice(2));
  } catch (error) {
    process.stderr.write(`${error instanceof Error ? error.message : String(error)}\n`);
    process.exitCode = 1;
  }
}
