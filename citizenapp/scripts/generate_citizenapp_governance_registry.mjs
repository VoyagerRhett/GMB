import { execFileSync } from 'node:child_process';
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const repoRoot = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '../..');
const cbPath = path.join(repoRoot, 'citizenchain/runtime/primitives/cid/china/china_cb.rs');
const chPath = path.join(repoRoot, 'citizenchain/runtime/primitives/cid/china/china_ch.rs');
const zfPath = path.join(repoRoot, 'citizenchain/runtime/primitives/cid/china/china_zf.rs');
const sfPath = path.join(repoRoot, 'citizenchain/runtime/primitives/cid/china/china_sf.rs');
const outPath = path.join(
  repoRoot,
  'citizenapp/lib/citizen/institution/governance_registry.generated.dart',
);

function extractField(block, name) {
  const quoted = new RegExp(`${name}:\\s*"([^"]+)"`).exec(block);
  if (quoted) return quoted[1];
  const hex = new RegExp(`${name}:\\s*hex!\\("([0-9a-fA-F]+)"\\)`).exec(block);
  if (hex) return hex[1].toLowerCase();
  throw new Error(`missing ${name} in block:\n${block.slice(0, 240)}`);
}

function extractStructs(source, structName) {
  const blocks = [];
  const pattern = new RegExp(`${structName}\\s*\\{([\\s\\S]*?)\\n\\s*\\},`, 'g');
  let match;
  while ((match = pattern.exec(source)) !== null) {
    blocks.push(match[1]);
  }
  // 数据块必含带引号的 cid_number；懒惰正则会把 struct 定义体与后续
  // 非数据常量(如 FscGenesisAssignment)误捕成块,在此过滤。
  return blocks.filter((block) => /cid_number:\s*"/.test(block));
}

function dartString(value) {
  return `'${value.replaceAll('\\', '\\\\').replaceAll("'", "\\'")}'`;
}

/// AccountId 规范形式（ADR-040）：小写 `0x` + 64 位十六进制。
/// china_*.rs 里是 `hex!("…")` 裸 hex，落到 Dart 必须补 `0x`，
/// 否则 `isAccountIdText()` 判定失败。
function dartAccountId(hex) {
  if (!/^[0-9a-f]{64}$/.test(hex)) {
    throw new Error(`invalid account id hex: ${hex}`);
  }
  return dartString(`0x${hex}`);
}

function dartInstitution(item) {
  const lines = [
    '  InstitutionInfo(',
    `    cidFullName: ${dartString(item.cidFullName)},`,
    `    cidShortName: ${dartString(item.cidShortName)},`,
    `    cidFullNameEn: ${dartString(item.cidFullNameEn)},`,
    `    cidShortNameEn: ${dartString(item.cidShortNameEn)},`,
    `    cidNumber: ${dartString(item.cidNumber)},`,
    `    orgType: OrgType.${item.orgType},`,
  ];
  if (item.adminAccountCode) {
    lines.push(`    adminAccountCode: ${dartString(item.adminAccountCode)},`);
  }
  lines.push(
    '    accounts: InstitutionAccounts(',
    `      mainAccountId: ${dartAccountId(item.mainAccount)},`,
    `      feeAccountId: ${dartAccountId(item.feeAccount)},`,
  );
  if (item.safetyFundAccount) {
    lines.push(`      safetyFundAccountId: ${dartAccountId(item.safetyFundAccount)},`);
  }
  if (item.heAccount) {
    lines.push(`      heAccountId: ${dartAccountId(item.heAccount)},`);
  }
  if (item.stakeAccount) {
    lines.push(`      stakeAccountId: ${dartAccountId(item.stakeAccount)},`);
  }
  lines.push('    ),', '  ),');
  return lines.join('\n');
}

const cbSource = fs.readFileSync(cbPath, 'utf8');
const chSource = fs.readFileSync(chPath, 'utf8');
const zfSource = fs.readFileSync(zfPath, 'utf8');
const sfSource = fs.readFileSync(sfPath, 'utf8');
const safetyFundMatch = /SAFETY_FUND_ACCOUNT:\s*\[u8;\s*32\]\s*=\s*hex!\("([0-9a-fA-F]+)"\)/.exec(
  cbSource,
);
if (!safetyFundMatch) throw new Error('missing SAFETY_FUND_ACCOUNT');
const safetyFundAccount = safetyFundMatch[1].toLowerCase();
const heFundMatch = /NRC_HE_ACCOUNT:\s*\[u8;\s*32\]\s*=\s*hex!\("([0-9a-fA-F]+)"\)/.exec(
  cbSource,
);
if (!heFundMatch) throw new Error('missing NRC_HE_ACCOUNT');
const heAccount = heFundMatch[1].toLowerCase();

const cbItems = extractStructs(cbSource, 'ChinaCb').map((block, index) => ({
  cidFullName: extractField(block, 'cid_full_name'),
  cidShortName: extractField(block, 'cid_short_name'),
  cidFullNameEn: extractField(block, 'cid_full_name_en'),
  cidShortNameEn: extractField(block, 'cid_short_name_en'),
  cidNumber: extractField(block, 'cid_number'),
  orgType: index === 0 ? 'nrc' : 'prc',
  mainAccount: extractField(block, 'main_account'),
  feeAccount: extractField(block, 'fee_account'),
  safetyFundAccount: index === 0 ? safetyFundAccount : null,
  heAccount: index === 0 ? heAccount : null,
  stakeAccount: null,
}));

const chItems = extractStructs(chSource, 'ChinaCh').map((block) => ({
  cidFullName: extractField(block, 'cid_full_name'),
  cidShortName: extractField(block, 'cid_short_name'),
  cidFullNameEn: extractField(block, 'cid_full_name_en'),
  cidShortNameEn: extractField(block, 'cid_short_name_en'),
  cidNumber: extractField(block, 'cid_number'),
  orgType: 'prb',
  mainAccount: extractField(block, 'main_account'),
  feeAccount: extractField(block, 'fee_account'),
  safetyFundAccount: null,
  heAccount: null,
  stakeAccount: extractField(block, 'stake_account'),
}));

function codeFromCidNumber(cidNumber) {
  const parts = cidNumber.split('-');
  if (parts.length < 2) throw new Error(`invalid cid_number: ${cidNumber}`);
  return parts[1].slice(0, 3);
}

function fixedGovernanceItemFrom(source, structName, code) {
  const block = extractStructs(source, structName).find(
    (item) => codeFromCidNumber(extractField(item, 'cid_number')) === code,
  );
  if (!block) throw new Error(`missing ${code} in ${structName}`);
  return {
    cidFullName: extractField(block, 'cid_full_name'),
    cidShortName: extractField(block, 'cid_short_name'),
    cidFullNameEn: extractField(block, 'cid_full_name_en'),
    cidShortNameEn: extractField(block, 'cid_short_name_en'),
    cidNumber: extractField(block, 'cid_number'),
    orgType: 'institution',
    adminAccountCode: code,
    mainAccount: extractField(block, 'main_account'),
    feeAccount: extractField(block, 'fee_account'),
    safetyFundAccount: null,
    heAccount: null,
    stakeAccount: null,
  };
}

const fixedGovernanceItems = [
  fixedGovernanceItemFrom(zfSource, 'ChinaZf', 'FRG'),
  fixedGovernanceItemFrom(sfSource, 'ChinaSf', 'NJD'),
];

if (cbItems.length !== 44) {
  throw new Error(`CHINA_CB count mismatch: ${cbItems.length}`);
}
if (chItems.length !== 43) {
  throw new Error(`CHINA_CH count mismatch: ${chItems.length}`);
}

const content = [
  "part of 'governance_registry.dart';",
  '',
  '// 本文件由 citizenapp/scripts/generate_citizenapp_governance_registry.mjs 自动生成。',
  '// 中文注释：创世治理机构中英全称/简称、cid_number 和制度账户来自 runtime primitives；管理员必须动态读取链上 AdminAccounts。',
  '',
  '/// 国储会（1 个）。',
  'const List<InstitutionInfo> kNrc = [',
  dartInstitution(cbItems[0]),
  '];',
  '',
  '/// 省储会（43 个）。',
  'const List<InstitutionInfo> kPrcs = [',
  cbItems.slice(1).map(dartInstitution).join('\n'),
  '];',
  '',
  '/// 省储行（43 个）。',
  'const List<InstitutionInfo> kProvincialBanks = [',
  chItems.map(dartInstitution).join('\n'),
  '];',
  '',
  '/// 其它固定治理机构（不进入治理 tab 联合投票列表）。',
  'const List<InstitutionInfo> kFixedGovernanceInstitutions = [',
  fixedGovernanceItems.map(dartInstitution).join('\n'),
  '];',
  '',
].join('\n');

fs.writeFileSync(outPath, content, 'utf8');
// 生成物必须是 dart format 稳定态，否则每次重生都在格式上打架。
execFileSync('dart', ['format', outPath], { stdio: 'inherit' });
console.log(`generated ${path.relative(repoRoot, outPath)} (${cbItems.length + chItems.length + fixedGovernanceItems.length} institutions)`);
