#!/usr/bin/env bash
# 节点本机任务只读中央已验真的 Node/Rust；锁依赖和前端生成状态属于当前任务。
# 必须 source 本脚本，让私有工程路径和工具环境留在调用进程中。
set -euo pipefail

PREPARE_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
GMB_REPOSITORY_ROOT="$(cd "$PREPARE_SCRIPT_DIR/../.." && pwd)"
: "${TATA_ROOT:?缺少塔塔仓库根目录}"
: "${TATA_CONSOLE_TARGET_ROOT:?缺少中央产物目录}"
: "${TATA_CONSOLE_WORK_DIR:?缺少当前任务目录}"
: "${TATA_CONSOLE_RUN_ID:?缺少当前任务身份}"
: "${TATA_CONSOLE_BUILD_WORK_DIR:?缺少当前任务编译目录}"
: "${TATA_CONSOLE_DEPENDENCY_WORK_DIR:?缺少当前任务依赖目录}"
[[ "${GITHUB_ACTIONS:-}" != true && "$(uname -s)" == Darwin \
    && "$TATA_CONSOLE_TARGET_ROOT" == "$TATA_ROOT/tataconsole/target" \
    && "$TATA_CONSOLE_WORK_DIR" == "${TATA_CONSOLE_TARGET_ROOT%/target}/work/gmb/citizenchain-node/macos" \
    && "$TATA_CONSOLE_BUILD_WORK_DIR" == "$TATA_CONSOLE_WORK_DIR/build" \
    && "$TATA_CONSOLE_DEPENDENCY_WORK_DIR" == "$TATA_CONSOLE_WORK_DIR/dependencies" \
    && "${npm_config_cache:-}" == "$TATA_CONSOLE_DEPENDENCY_WORK_DIR/npm" ]] || {
    echo '[error] 节点工具准备必须使用 Worker 已预取的准确本机任务环境' >&2
    return 1 2>/dev/null || exit 1
}

node --input-type=module - "$TATA_ROOT/tataconsole" "$GMB_REPOSITORY_ROOT" <<'NODE_PROJECT'
import fs from 'node:fs';
import { dirname, join } from 'node:path';
import { pathToFileURL } from 'node:url';
const [consoleRoot, source] = process.argv.slice(2);
const work = process.env.TATA_CONSOLE_WORK_DIR;
const { loadTools, verifyTool } = await import(pathToFileURL(join(consoleRoot, 'worker/toolchain.mjs')));
function directory(path) {
    const stat = fs.lstatSync(path);
    if (!stat.isDirectory() || stat.isSymbolicLink() || fs.realpathSync(path) !== path) throw new Error('节点任务目录不是独立真实目录：' + path);
}
directory(source);
directory(work);
const ownerPath = join(work, '.owner');
const ownerStat = fs.lstatSync(ownerPath);
if (!ownerStat.isFile() || ownerStat.isSymbolicLink() || ownerStat.size > 4096) throw new Error('节点任务占有记录无效');
const owner = JSON.parse(fs.readFileSync(ownerPath, 'utf8'));
if (owner.runId !== process.env.TATA_CONSOLE_RUN_ID || owner.canonicalId !== 'gmb.citizenchain-node.macos.build') throw new Error('节点工具准备不属于当前编译任务');
const library = loadTools(join(consoleRoot, 'tools'));
const tools = {};
for (const id of ['node', 'rust']) {
    tools[id] = await verifyTool(library, library.tools.find(tool => tool.id === id));
    if (!tools[id]) throw new Error('中央工具尚未安装并验真：' + id);
}
const executable = name => {
    for (const root of (process.env.PATH || '').split(':').filter(Boolean)) {
        const candidate = join(root, name);
        try { fs.accessSync(candidate, fs.constants.X_OK); return fs.realpathSync(candidate); } catch {}
    }
    throw new Error('中央工具入口不存在：' + name);
};
if (fs.realpathSync(process.execPath) !== tools.node.path || executable('node') !== tools.node.path
    || executable('npm') !== fs.realpathSync(join(dirname(tools.node.path), 'npm'))
    || executable('rustc') !== tools.rust.path || process.env.RUSTC !== tools.rust.path
    || executable('cargo') !== fs.realpathSync(join(dirname(tools.rust.path), 'cargo'))) throw new Error('Node、npm、Rust 或 Cargo 未使用中央验真对象');

// 固定 project 属于已占有的当前任务；已有内容不覆盖、不清空。
const project = join(work, 'project');
fs.mkdirSync(project);
const ignored = new Set(['.git', 'node_modules', 'target', 'build', 'dist', '.cache', 'coverage', '.vite', 'local-docs.generated.ts']);
const config = name => ['package.json', 'package-lock.json', 'npm-shrinkwrap.json', '.npmrc'].includes(name)
    || /^(?:tsconfig(?:\.[^.]+)*\.json|[\w.-]+\.config\.(?:[cm]?[jt]s|json|jsonc))$/u.test(name);
function visit(from, to) {
    directory(from);
    fs.mkdirSync(to, { recursive: true });
    directory(to);
    for (const name of fs.readdirSync(from).sort()) {
        if (ignored.has(name) || name.endsWith('.tsbuildinfo')) continue;
        const input = join(from, name), output = join(to, name), stat = fs.lstatSync(input);
        if (stat.isSymbolicLink()) throw new Error('节点源码符号链接未登记：' + input);
        if (stat.isDirectory()) visit(input, output);
        else if (stat.isFile()) {
            if (config(name)) {
                let content = fs.readFileSync(input, 'utf8');
                // 工具沿任务内源码引用解析包，不能回原仓库寻找 node_modules。
                if (name === 'vite.config.ts') {
                    if (content.split('return {').length !== 2 || /preserveSymlinks/u.test(content)) throw new Error('节点 Vite 配置形状已改变');
                    content = content.replace('return {', 'return {\n  resolve: { preserveSymlinks: true },');
                }
                if (/^tsconfig(?:\.[^.]+)*\.json$/u.test(name) && /"compilerOptions"\s*:/u.test(content)) {
                    if (/"preserveSymlinks"/u.test(content)) throw new Error("节点 TS 源配置已声明符号链接策略");
                    content = content.replace(/("compilerOptions"\s*:\s*\{)/u, '$1\n    "preserveSymlinks": true,');
                }
                fs.writeFileSync(output, content, { flag: 'wx', mode: stat.mode & 0o777 });
            } else fs.symlinkSync(input, output);
        } else throw new Error('节点源码对象类型未登记：' + input);
    }
}
for (const relative of ['citizenchain/crates/scanner-react', 'citizenchain/node/frontend', 'citizenchain/onchina/frontend', 'citizenweb/src']) visit(join(source, relative), join(project, relative));
// 生成器以自身位置寻找输入和输出；复制唯一工具脚本，避免向原始生成文件写入。
const generator = 'citizenchain/scripts/generate-local-docs.mjs';
fs.mkdirSync(dirname(join(project, generator)), { recursive: true });
const generatorStat = fs.lstatSync(join(source, generator));
if (!generatorStat.isFile() || generatorStat.isSymbolicLink()) throw new Error('节点文档生成器必须是原始普通文件');
fs.copyFileSync(join(source, generator), join(project, generator), fs.constants.COPYFILE_EXCL);
NODE_PROJECT

# npm/Vite 的官方可执行入口自身是链接，主入口必须正常解析；只保留业务模块的引用路径。
export NODE_OPTIONS='--preserve-symlinks'
export CARGO_TARGET_DIR="$TATA_CONSOLE_BUILD_WORK_DIR/cargo-target"
: "${TATA_CONSOLE_CARGO_CONFIG:?缺少Worker准备的Cargo依赖配置}"
[[ "${CARGO_NET_OFFLINE:-}" == true && -n "${CARGO_HOME:-}" \
    && "$CARGO_HOME" == "$TATA_CONSOLE_WORK_DIR"/* \
    && "$TATA_CONSOLE_CARGO_CONFIG" == "$CARGO_HOME/config.toml" \
    && -f "$TATA_CONSOLE_CARGO_CONFIG" ]] || {
    echo '[error] Cargo必须消费Worker准备的任务内锁定依赖并保持离线' >&2
    return 1 2>/dev/null || exit 1
}
export npm_config_audit=false
export npm_config_fund=false
NODE_FRONTEND_PROJECT="$TATA_CONSOLE_WORK_DIR/project/citizenchain/node/frontend"
ONCHINA_FRONTEND_PROJECT="$TATA_CONSOLE_WORK_DIR/project/citizenchain/onchina/frontend"
for project in citizenchain/crates/scanner-react citizenchain/node/frontend citizenchain/onchina/frontend; do
    echo "==> 离线准备当前节点任务依赖：$project"
    ( cd "$TATA_CONSOLE_WORK_DIR/project/$project" && npm ci --offline --no-audit --no-fund )
done
[[ -f "$NODE_FRONTEND_PROJECT/node_modules/@tauri-apps/cli/tauri.js" ]] || {
    echo '[error] 当前节点任务缺少锁定 Tauri CLI' >&2
    return 1 2>/dev/null || exit 1
}
echo '==> 当前节点任务的中央工具与锁定依赖已就绪'
