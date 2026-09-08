// 仓库结构守卫读取失败必须立即中止测试，断言式解包仅限本测试目标。
#![allow(clippy::expect_used, clippy::unwrap_used)]

use std::collections::BTreeSet;
use std::path::{Path, PathBuf};
use std::{env, fs};

use serde_json::Value;

/// GMB 只保留 GitHub 可发现的固定入口，产品流水线统一由冻结的 TATA 提交提供。
///
/// 这里仅验证公开委派边界，不复制 TATA 内部产品矩阵或 CI/Release 实现合同；后者由
/// TATA 仓库自己的测试负责，避免两个仓库维护两份会漂移的流程真源。
#[test]
fn github_workflow_entrypoints_delegate_to_single_tata_flow() {
    let repo_root = repo_root();
    let workflow_root = repo_root.join(".github/workflows");
    let mut violations = Vec::new();
    let mut entry_names = Vec::new();

    let entries = fs::read_dir(&workflow_root)
        .unwrap_or_else(|e| panic!("读取 {} 失败: {e}", workflow_root.display()));
    for entry in entries {
        let entry = entry.unwrap_or_else(|e| panic!("读取 GitHub Workflow 目录项失败: {e}"));
        let file_type = entry
            .file_type()
            .unwrap_or_else(|e| panic!("读取 {} 类型失败: {e}", entry.path().display()));
        let name = entry
            .file_name()
            .into_string()
            .unwrap_or_else(|_| panic!("{} 的文件名不是 UTF-8", entry.path().display()));
        if !file_type.is_file() {
            violations.push(format!(
                ".github/workflows/{name}: 统一入口目录只允许普通 Workflow 文件"
            ));
        }
        entry_names.push(name);
    }
    entry_names.sort();
    let expected_entries = vec!["flow.yml".to_string(), "repository.yml".to_string()];
    if entry_names != expected_entries {
        violations.push(format!(
            ".github/workflows 必须精确包含 flow.yml、repository.yml，实际为 {entry_names:?}"
        ));
    }

    let repository_entry =
        fs::read_to_string(workflow_root.join("repository.yml")).expect("读取 repository.yml 失败");
    let event_count = |source: &str, event: &str| {
        let expected = format!("{event}:");
        source
            .lines()
            .filter(|line| line.trim() == expected)
            .count()
    };
    if event_count(&repository_entry, "workflow_dispatch") != 1
        || event_count(&repository_entry, "workflow_call") != 0
    {
        violations
            .push("repository.yml: 必须且只能由一个 workflow_dispatch 接受显式调度".to_string());
    }
    for required in [
        "uses: ./.github/workflows/flow.yml",
        "pipeline: ${{ inputs.pipeline }}",
        "source_sha: ${{ inputs.source_sha }}",
        "secrets: inherit",
    ] {
        if !repository_entry.contains(required) {
            violations.push(format!("repository.yml: 缺少统一委派合同 {required}"));
        }
    }

    let reusable_flow =
        fs::read_to_string(workflow_root.join("flow.yml")).expect("读取 flow.yml 失败");
    if event_count(&reusable_flow, "workflow_call") != 1
        || event_count(&reusable_flow, "workflow_dispatch") != 0
    {
        violations.push(
            "flow.yml: 只能作为 workflow_call 可复用入口，禁止第二个显式调度入口".to_string(),
        );
    }
    for required in [
        "repository: VoyagerRhett/TATA",
        "path: .tata-flow",
        "FLOW_COMMIT_SHA",
        "git -C .tata-flow rev-parse HEAD",
        "uses: ./.tata-flow/tataconsole/flows/gmb/shared",
        "job: dispatch-product",
    ] {
        if !reusable_flow.contains(required) {
            violations.push(format!("flow.yml: 缺少冻结 TATA 中央流程合同 {required}"));
        }
    }

    // 每个消费中央流程的作业都必须在同一作业内完成冻结提交检出与回读；只检查全文件中
    // “曾经出现过”这些字符串会放过新增的未冻结调用。
    const CENTRAL_FLOW_USE: &str = "uses: ./.tata-flow/tataconsole/flows/gmb/shared";
    const LOCKED_REF: &str =
        "ref: \"${{ secrets[format('TATA_FLOW_COMMIT_SHA_{0}', inputs.lease_id)] }}\"";
    const LOCKED_TOKEN: &str =
        "token: \"${{ secrets[format('TATA_FLOW_READ_TOKEN_{0}', inputs.lease_id)] }}\"";
    const COMMIT_ENV: &str = "env: { FLOW_COMMIT_SHA: \"${{ secrets[format('TATA_FLOW_COMMIT_SHA_{0}', inputs.lease_id)] }}\" }";
    const COMMIT_READBACK: &str =
        "run: test \"$(git -C .tata-flow rev-parse HEAD)\" = \"$FLOW_COMMIT_SHA\"";
    let jobs_text = reusable_flow
        .split_once("\njobs:\n")
        .map(|(_, jobs)| jobs)
        .unwrap_or_else(|| {
            violations.push("flow.yml: 缺少 jobs 根节点".to_string());
            ""
        });
    let mut job_blocks: Vec<(String, String)> = Vec::new();
    let mut current_job: Option<(String, String)> = None;
    for line in jobs_text.lines() {
        let is_job_heading = line.starts_with("  ")
            && !line.starts_with("   ")
            && line.ends_with(':')
            && line.len() > 3;
        if is_job_heading {
            if let Some(job) = current_job.take() {
                job_blocks.push(job);
            }
            current_job = Some((line.trim_end_matches(':').trim().to_string(), String::new()));
        }
        if let Some((_, block)) = current_job.as_mut() {
            block.push_str(line);
            block.push('\n');
        }
    }
    if let Some(job) = current_job {
        job_blocks.push(job);
    }

    let mut central_job_count = 0;
    for (job_name, block) in &job_blocks {
        let central_call_count = block.matches(CENTRAL_FLOW_USE).count();
        if central_call_count == 0 {
            continue;
        }
        central_job_count += 1;
        for (contract, expected_count) in [
            (CENTRAL_FLOW_USE, 1),
            ("repository: VoyagerRhett/TATA", 1),
            (LOCKED_REF, 1),
            (LOCKED_TOKEN, 1),
            ("path: .tata-flow", 1),
            ("persist-credentials: false", 1),
            (COMMIT_ENV, 1),
            (COMMIT_READBACK, 1),
        ] {
            let actual_count = block.matches(contract).count();
            if actual_count != expected_count {
                violations.push(format!(
                    "flow.yml 作业 {job_name}: 冻结 TATA 委派合同 {contract} 应出现 {expected_count} 次，实际 {actual_count} 次"
                ));
            }
        }
    }
    let all_central_calls = reusable_flow.matches(CENTRAL_FLOW_USE).count();
    if central_job_count == 0 || central_job_count != all_central_calls {
        violations.push(format!(
            "flow.yml: 每个中央流程调用必须独占一个完成冻结检出与回读的作业，中央作业 {central_job_count} 个，调用 {all_central_calls} 次"
        ));
    }

    // 这里只限制 GitHub 会识别为本仓产品入口的一级产品根目录；内嵌上游依赖可能保留其
    // 来源仓库的 .github 元数据，但不会成为 GMB 仓库的可执行 Workflow。
    for product in [
        "citizenapp",
        "citizenchain",
        "citizenchatserver",
        "citizensdk",
        "citizenserve",
        "citizenwallet",
        "citizenweb",
    ] {
        let duplicate = repo_root.join(product).join(".github/workflows");
        if duplicate.exists() {
            violations.push(format!(
                "{}: 一级产品根目录禁止建立第二套 GMB GitHub Workflow",
                duplicate.display()
            ));
        }
    }

    assert!(
        violations.is_empty(),
        "GMB GitHub Workflow 统一委派守卫失败:\n{}",
        violations.join("\n")
    );
}

/// CitizenChatServer 没有宿主 OS 平台；产品声明与正式 Release manifest 必须把
/// Cloudflare 表达为部署供应商。这里只检查两个新合同，不能误伤 QR_V1/action 中尚未
/// 原子迁移的签名兼容字段 `platform=cloudflare`。
#[test]
fn citizenchatserver_product_and_release_manifest_use_deployment_provider() {
    let product_path = repo_root().join("citizenchatserver/scripts/product.json");
    let product_text = fs::read_to_string(&product_path)
        .unwrap_or_else(|e| panic!("读取 {} 失败: {e}", product_path.display()));
    let product: Value = serde_json::from_str(&product_text)
        .unwrap_or_else(|e| panic!("解析 {} 失败: {e}", product_path.display()));
    let product = product
        .as_object()
        .expect("CitizenChatServer product.json 根节点必须是对象");
    let actual_keys = product.keys().map(String::as_str).collect::<BTreeSet<_>>();
    let expected_keys = [
        "deployment_provider",
        "product_id",
        "public_url",
        "realtime_url",
        "source_product_id",
        "source_repository",
        "version",
    ]
    .into_iter()
    .collect::<BTreeSet<_>>();
    assert_eq!(
        actual_keys, expected_keys,
        "CitizenChatServer product.json 字段闭集漂移"
    );
    assert_eq!(product["product_id"], "citizenchatserver");
    assert_eq!(product["deployment_provider"], "cloudflare");
    assert!(
        !product.contains_key("platform"),
        "CitizenChatServer 产品声明禁止把部署供应商写成 platform"
    );

    let flow_root = tata_flow_root();
    let ci_path = flow_root.join("gmb/citizenchatserver/ci-cloudflare.mjs");
    let ci = fs::read_to_string(&ci_path)
        .unwrap_or_else(|e| panic!("读取 {} 失败: {e}", ci_path.display()));
    assert!(
        ci.contains("JSON.stringify(Object.keys(product).sort())")
            && ci.contains("'deployment_provider', 'product_id', 'public_url', 'realtime_url'")
            && ci.contains("Object.hasOwn(product, 'platform')"),
        "CitizenChatServer CI 必须锁定产品声明精确闭集并拒绝旧 platform"
    );

    let release_path = flow_root.join("gmb/citizenchatserver/release-cloudflare.mjs");
    let release = fs::read_to_string(&release_path)
        .unwrap_or_else(|e| panic!("读取 {} 失败: {e}", release_path.display()));
    // 限定到 manifest 对象本身，不能全局扫描 release/action 或 QR 签名协议旧边界。
    let manifest_start = release
        .find("const manifest = {")
        .expect("CitizenChatServer Release 缺少 manifest 构造");
    let manifest_end = release[manifest_start..]
        .find("const manifestPath =")
        .map(|offset| manifest_start + offset)
        .expect("CitizenChatServer Release 缺少 manifest 输出边界");
    let manifest = &release[manifest_start..manifest_end];
    assert!(
        manifest.contains("deployment_provider: 'cloudflare'"),
        "CitizenChatServer Release manifest 缺少 deployment_provider: cloudflare"
    );
    assert!(
        !manifest.contains("platform:"),
        "CitizenChatServer Release manifest 禁止把 Cloudflare 写入 platform"
    );
    assert!(
        release.contains("export function verifyPackagedRelease")
            && release.contains("manifest.archive_sha256 !== archiveSHA256")
            && release.contains("verifyPackagedRelease({ archive, manifestPath, sumsPath })")
            && release.contains("'--no-recursion', '--null', '-T', archiveList")
            && release.contains("detailRows.some((line) => line[0] !== '-')"),
        "CitizenChatServer Release 必须生成并回验仅含普通文件且绑定实际归档哈希的三件套"
    );

    let console_root = flow_root
        .parent()
        .expect("TataConsole flows 必须位于控制台根目录下");
    let publisher_path = console_root.join("app/Sources/CloudflarePublisher.swift");
    let publisher = fs::read_to_string(&publisher_path)
        .unwrap_or_else(|e| panic!("读取 {} 失败: {e}", publisher_path.display()));
    assert!(
        publisher.contains("manifest[\"archive_sha256\"] as? String == archiveSHA256")
            && publisher.contains("citizenChatServerExternalChecksums(")
            && publisher.contains("expectedFiles = Set(files.keys)"),
        "CitizenChatServer 原生发布器必须验证外部三件套、实际归档哈希与内部候选闭集"
    );
}

/// CitizenServe 正式制品必须把 Cloudflare 表达为部署供应商；QR_V1/action/recovery 中的
/// `platform=cloudflare` 是另一项签名与持久化 wire，不能在 Release 中局部兼容双写。
#[test]
fn citizenserve_release_identity_uses_deployment_provider() {
    let flow_root = tata_flow_root();
    let tata_console_root = flow_root
        .parent()
        .expect("TATA_CONSOLE_FLOW_ROOT 必须位于 tataconsole/flows")
        .to_path_buf();
    let implementation = |path: &Path| {
        let text = fs::read_to_string(path)
            .unwrap_or_else(|e| panic!("读取 {} 失败: {e}", path.display()));
        let line = text
            .lines()
            .find(|line| line.starts_with("const implementations = Object.freeze("))
            .unwrap_or_else(|| panic!("{} 缺少内嵌实现登记", path.display()));
        let json = line
            .strip_prefix("const implementations = Object.freeze(")
            .and_then(|value| value.strip_suffix(");"))
            .unwrap_or_else(|| panic!("{} 的内嵌实现登记格式无效", path.display()));
        let implementations: Value = serde_json::from_str(json)
            .unwrap_or_else(|e| panic!("解析 {} 内嵌实现失败: {e}", path.display()));
        implementations["action"]
            .as_str()
            .unwrap_or_else(|| panic!("{} 缺少 CitizenServe action 实现", path.display()))
            .to_string()
    };
    let ci_path = flow_root.join("gmb/citizenserve/ci-cloudflare.mjs");
    let release_path = flow_root.join("gmb/citizenserve/release-cloudflare.mjs");
    let ci_implementation = implementation(&ci_path);
    let release_implementation = implementation(&release_path);
    assert_eq!(
        ci_implementation, release_implementation,
        "CitizenServe CI 与 Release 必须内嵌同一份正式制品实现"
    );
    for required in [
        "const DEPLOYMENT_PROVIDER = 'cloudflare';",
        "['product_id', 'deployment_provider', 'software_version', 'git_commit_sha', 'tools', 'files', 'resources']",
        "manifest.deployment_provider !== DEPLOYMENT_PROVIDER",
        "deployment_provider: DEPLOYMENT_PROVIDER",
        "sha256File(join(candidate, 'wrangler.toml')) !== manifest.resources.wrangler_sha256",
        "候选 SHA256SUMS 不一致",
        "if (!deterministicTar(output).equals(tar))",
        "assertNoSecrets(candidate);",
    ] {
        assert!(
            release_implementation.contains(required),
            "CitizenServe Release 缺少部署供应商或完整性合同 {required}"
        );
    }
    assert_eq!(
        release_implementation
            .matches("deployment_provider: DEPLOYMENT_PROVIDER")
            .count(),
        1,
        "CitizenServe manifest 必须且只能写入一次部署供应商"
    );
    for forbidden in [
        "manifest.platform",
        "platform: DEPLOYMENT_PROVIDER",
        "platform: 'cloudflare'",
    ] {
        assert!(
            !release_implementation.contains(forbidden),
            "CitizenServe 正式制品禁止旧 platform 或双写 {forbidden}"
        );
    }

    let release_test_path = repo_root().join("citizenserve/test/release_manifest.test.ts");
    let release_test = fs::read_to_string(&release_test_path)
        .unwrap_or_else(|e| panic!("读取 {} 失败: {e}", release_test_path.display()));
    for required in [
        "gmb/citizenserve/ci-cloudflare.mjs",
        "gmb/citizenserve/release-cloudflare.mjs",
        "deployment_provider).toBe('cloudflare')",
        "manifest.platform = 'cloudflare'",
        "候选部署供应商不正确",
    ] {
        assert!(
            release_test.contains(required),
            "CitizenServe Release 测试缺少当前入口或失败关闭合同 {required}"
        );
    }
    for obsolete in [
        "gmb/scripts/citizenserve-ci-global.mjs",
        "gmb/scripts/citizenserve-release-global.mjs",
    ] {
        assert!(
            !release_test.contains(obsolete),
            "CitizenServe Release 测试禁止恢复失效入口 {obsolete}"
        );
    }

    let publisher_path = tata_console_root.join("app/Sources/CloudflarePublisher.swift");
    let publisher = fs::read_to_string(&publisher_path)
        .unwrap_or_else(|e| panic!("读取 {} 失败: {e}", publisher_path.display()));
    let prepare_start = publisher
        .find("private func prepareCandidate(")
        .expect("CloudflarePublisher 缺少 prepareCandidate");
    let validator_start = publisher
        .find("static func validateCitizenServeReleaseManifest(")
        .expect("CloudflarePublisher 缺少 CitizenServe Release 验证器");
    let citizen_web_validator_start = publisher[validator_start..]
        .find("static func validateCitizenWebReleaseContract(")
        .map(|offset| validator_start + offset)
        .expect("CitizenServe 验证器缺少后续 CitizenWeb 边界");
    let prepare = &publisher[prepare_start..validator_start];
    let validator = &publisher[validator_start..citizen_web_validator_start];
    assert!(
        prepare.contains("if input.productID == \"citizenserve\"")
            && prepare.contains("try Self.validateCitizenServeReleaseManifest(manifest)"),
        "CitizenServe 原生发布器必须只在本产品候选准备阶段调用专用验证器"
    );
    for required in [
        "\"product_id\", \"deployment_provider\", \"software_version\", \"git_commit_sha\"",
        "manifest[\"product_id\"] as? String == \"citizenserve\"",
        "manifest[\"deployment_provider\"] as? String == \"cloudflare\"",
        "^[0-9]+\\\\.[0-9]{1,2}\\\\.[0-9]{1,2}$",
        "^[0-9a-f]{40}$",
    ] {
        assert!(
            validator.contains(required),
            "CitizenServe 原生发布器缺少部署供应商身份复核 {required}"
        );
    }
    assert!(
        publisher
            .contains("input.productID == \"citizenserve\" && input.platform == \"cloudflare\""),
        "CitizenServe QR/action/recovery 的既有签名 wire 不得在本步局部改写"
    );

    let shared_path = tata_console_root.join("dictionary/gmb/shared.json");
    let shared_text = fs::read_to_string(&shared_path)
        .unwrap_or_else(|e| panic!("读取 {} 失败: {e}", shared_path.display()));
    let shared: Value = serde_json::from_str(&shared_text)
        .unwrap_or_else(|e| panic!("解析 {} 失败: {e}", shared_path.display()));
    let provider_fields = shared["fields"]
        .as_array()
        .expect("GMB 共享字典 fields 必须是数组")
        .iter()
        .filter(|field| field["concept_id"] == "deployment_provider")
        .collect::<Vec<_>>();
    assert_eq!(
        provider_fields.len(),
        1,
        "deployment_provider 字段必须只有一个共享真源"
    );
    assert_eq!(provider_fields[0]["data_type"], "enum");
    assert_eq!(provider_fields[0]["value_set_id"], "deployment_provider");
    let provider_value_sets = shared["value_sets"]
        .as_array()
        .expect("GMB 共享字典 value_sets 必须是数组")
        .iter()
        .filter(|value_set| value_set["value_set_id"] == "deployment_provider")
        .collect::<Vec<_>>();
    assert_eq!(
        provider_value_sets.len(),
        1,
        "deployment_provider 值集必须只有一个共享真源"
    );
    assert_eq!(
        provider_value_sets[0]["values"].as_array().map(Vec::len),
        Some(1)
    );
    assert_eq!(provider_value_sets[0]["values"][0]["value"], "cloudflare");

    let citizenserve_path = tata_console_root.join("dictionary/gmb/citizenserve.json");
    let citizenserve_text = fs::read_to_string(&citizenserve_path)
        .unwrap_or_else(|e| panic!("读取 {} 失败: {e}", citizenserve_path.display()));
    let citizenserve: Value = serde_json::from_str(&citizenserve_text)
        .unwrap_or_else(|e| panic!("解析 {} 失败: {e}", citizenserve_path.display()));
    assert!(!citizenserve["fields"]
        .as_array()
        .expect("CitizenServe fields 必须是数组")
        .iter()
        .any(|field| field["concept_id"] == "deployment_provider"));
    assert!(!citizenserve["value_sets"]
        .as_array()
        .expect("CitizenServe value_sets 必须是数组")
        .iter()
        .any(|value_set| value_set["value_set_id"] == "deployment_provider"));
    let contracts = citizenserve["contracts"]
        .as_array()
        .expect("CitizenServe contracts 必须是数组");
    let matching_contracts = contracts
        .iter()
        .filter(|contract| contract["contract_id"] == "citizenserve_release_identity")
        .collect::<Vec<_>>();
    assert_eq!(
        matching_contracts.len(),
        1,
        "CitizenServe 必须且只能登记一个正式发布身份合同"
    );
    let contract = matching_contracts[0];
    let string_set = |value: &Value| {
        value
            .as_array()
            .expect("合同字段必须是数组")
            .iter()
            .map(|item| item.as_str().expect("合同字段必须是字符串").to_string())
            .collect::<BTreeSet<String>>()
    };
    assert_eq!(
        string_set(&contract["paths"]),
        ["citizenserve/test/release_manifest.test.ts"]
            .into_iter()
            .map(str::to_string)
            .collect::<BTreeSet<String>>()
    );
    assert_eq!(
        string_set(&contract["fields"]),
        ["deployment_provider", "product_id"]
            .into_iter()
            .map(str::to_string)
            .collect::<BTreeSet<String>>()
    );
    assert_eq!(
        string_set(&contract["value_sets"]),
        ["deployment_provider"]
            .into_iter()
            .map(str::to_string)
            .collect::<BTreeSet<String>>()
    );
}

/// CitizenWeb 正式制品必须把 Web 表达为交付渠道；QR_V1/action 中尚未原子迁移的
/// `platform=web` 是另一项签名 wire，不能用全文件禁词误伤，也不能进入 Release 双写。
#[test]
fn citizenweb_release_identity_uses_delivery_channel() {
    let flow_root = tata_flow_root();
    let tata_console_root = flow_root
        .parent()
        .expect("TATA_CONSOLE_FLOW_ROOT 必须位于 tataconsole/flows")
        .to_path_buf();
    let implementation = |path: &Path| {
        let text = fs::read_to_string(path)
            .unwrap_or_else(|e| panic!("读取 {} 失败: {e}", path.display()));
        let line = text
            .lines()
            .find(|line| line.starts_with("const implementations = Object.freeze("))
            .unwrap_or_else(|| panic!("{} 缺少内嵌实现登记", path.display()));
        let json = line
            .strip_prefix("const implementations = Object.freeze(")
            .and_then(|value| value.strip_suffix(");"))
            .unwrap_or_else(|| panic!("{} 的内嵌实现登记格式无效", path.display()));
        let implementations: Value = serde_json::from_str(json)
            .unwrap_or_else(|e| panic!("解析 {} 内嵌实现失败: {e}", path.display()));
        implementations["citizenweb-release"]
            .as_str()
            .unwrap_or_else(|| panic!("{} 缺少 citizenweb-release 实现", path.display()))
            .to_string()
    };
    let ci_path = flow_root.join("gmb/citizenweb/ci-web.mjs");
    let release_path = flow_root.join("gmb/citizenweb/release-web.mjs");
    let ci_implementation = implementation(&ci_path);
    let release_implementation = implementation(&release_path);
    assert_eq!(
        ci_implementation, release_implementation,
        "CitizenWeb CI 与 Release 必须内嵌同一份正式制品实现"
    );
    for required in [
        "const DELIVERY_CHANNEL = 'web';",
        "['product_id', 'delivery_channel', 'software_version', 'git_commit_sha', 'tools', 'assets_sha256', 'files']",
        "['product_id', 'delivery_channel', 'software_version', 'git_commit_sha', 'assets_sha256']",
        "manifest.delivery_channel !== DELIVERY_CHANNEL",
        "delivery_channel: DELIVERY_CHANNEL",
        "sha256Bytes(stableJson(assetEntries)) !== manifest.assets_sha256",
        "官网版本标记与 Release 候选不一致",
        "候选 SHA256SUMS 不一致",
    ] {
        assert!(
            release_implementation.contains(required),
            "CitizenWeb Release 缺少交付渠道或完整性合同 {required}"
        );
    }
    assert_eq!(
        release_implementation
            .matches("delivery_channel: DELIVERY_CHANNEL")
            .count(),
        3,
        "CitizenWeb manifest、公开标记及其期望值必须各写一次交付渠道"
    );
    for forbidden in [
        "manifest.platform",
        "marker.platform",
        "platform: DELIVERY_CHANNEL",
        "platform: 'web'",
    ] {
        assert!(
            !release_implementation.contains(forbidden),
            "CitizenWeb 正式制品禁止旧 platform 或双写 {forbidden}"
        );
    }

    let publisher_path = tata_console_root.join("app/Sources/CloudflarePublisher.swift");
    let publisher = fs::read_to_string(&publisher_path)
        .unwrap_or_else(|e| panic!("读取 {} 失败: {e}", publisher_path.display()));
    for required in [
        "static func validateCitizenWebReleaseContract(",
        "manifest[\"delivery_channel\"] as? String == \"web\"",
        "marker[\"delivery_channel\"] as? String == \"web\"",
        "marker[\"software_version\"] as? String == softwareVersion",
        "marker[\"git_commit_sha\"] as? String == gitCommitSHA",
        "marker[\"assets_sha256\"] as? String == assetsSHA256",
        "input.productID == \"citizenweb\"",
        "dist/citizenweb-release.json",
    ] {
        assert!(
            publisher.contains(required),
            "CitizenWeb 原生发布器缺少独立渠道身份复核 {required}"
        );
    }

    let shared_path = tata_console_root.join("dictionary/gmb/shared.json");
    let shared_text = fs::read_to_string(&shared_path)
        .unwrap_or_else(|e| panic!("读取 {} 失败: {e}", shared_path.display()));
    let shared: Value = serde_json::from_str(&shared_text)
        .unwrap_or_else(|e| panic!("解析 {} 失败: {e}", shared_path.display()));
    let fields = shared["fields"]
        .as_array()
        .expect("GMB 共享字典 fields 必须是数组");
    let delivery_fields = fields
        .iter()
        .filter(|field| field["concept_id"] == "delivery_channel")
        .collect::<Vec<_>>();
    assert_eq!(
        delivery_fields.len(),
        1,
        "delivery_channel 字段必须只有一个真源"
    );
    assert_eq!(delivery_fields[0]["field_name"], "delivery_channel");
    assert_eq!(delivery_fields[0]["data_type"], "enum");
    assert_eq!(delivery_fields[0]["value_set_id"], "delivery_channel");

    let value_sets = shared["value_sets"]
        .as_array()
        .expect("GMB 共享字典 value_sets 必须是数组");
    let delivery_value_sets = value_sets
        .iter()
        .filter(|value_set| value_set["value_set_id"] == "delivery_channel")
        .collect::<Vec<_>>();
    assert_eq!(
        delivery_value_sets.len(),
        1,
        "delivery_channel 值集必须只有一个真源"
    );
    assert_eq!(
        delivery_value_sets[0]["values"].as_array().map(Vec::len),
        Some(1)
    );
    assert_eq!(delivery_value_sets[0]["values"][0]["value"], "web");

    let publish_record = shared["contracts"]
        .as_array()
        .expect("GMB 共享字典 contracts 必须是数组")
        .iter()
        .find(|contract| contract["contract_id"] == "publish_record")
        .expect("GMB 共享字典缺少 publish_record");
    assert!(publish_record["fields"]
        .as_array()
        .expect("publish_record.fields 必须是数组")
        .iter()
        .any(|field| field == "delivery_channel"));
    assert!(publish_record["value_sets"]
        .as_array()
        .expect("publish_record.value_sets 必须是数组")
        .iter()
        .any(|value_set| value_set == "delivery_channel"));

    let citizenweb_path = tata_console_root.join("dictionary/gmb/citizenweb.json");
    let citizenweb_text = fs::read_to_string(&citizenweb_path)
        .unwrap_or_else(|e| panic!("读取 {} 失败: {e}", citizenweb_path.display()));
    let citizenweb: Value = serde_json::from_str(&citizenweb_text)
        .unwrap_or_else(|e| panic!("解析 {} 失败: {e}", citizenweb_path.display()));
    assert_eq!(citizenweb["fields"].as_array().map(Vec::len), Some(0));
    assert_eq!(citizenweb["value_sets"].as_array().map(Vec::len), Some(0));
    let contracts = citizenweb["contracts"]
        .as_array()
        .expect("CitizenWeb contracts 必须是数组");
    assert_eq!(
        contracts.len(),
        1,
        "CitizenWeb 必须只有一个产品发布身份合同"
    );
    let contract = &contracts[0];
    assert_eq!(contract["contract_id"], "citizenweb_release_identity");
    let string_set = |value: &Value| {
        value
            .as_array()
            .expect("合同字段必须是数组")
            .iter()
            .map(|item| item.as_str().expect("合同字段必须是字符串").to_string())
            .collect::<BTreeSet<String>>()
    };
    assert_eq!(
        string_set(&contract["paths"]),
        ["citizenweb/test/release_manifest.test.mjs"]
            .into_iter()
            .map(str::to_string)
            .collect::<BTreeSet<String>>()
    );
    assert_eq!(
        string_set(&contract["fields"]),
        ["delivery_channel", "product_id"]
            .into_iter()
            .map(str::to_string)
            .collect::<BTreeSet<String>>()
    );
    assert_eq!(
        string_set(&contract["value_sets"]),
        ["delivery_channel"]
            .into_iter()
            .map(str::to_string)
            .collect::<BTreeSet<String>>()
    );
}

/// CitizenApp 的正式移动制品必须在公开 manifest 中使用标准平台名；动作、Tag 与
/// QR_V1 仍使用既有内部 `ios`/`android` wire，二者只能在原生消费边界显式映射。
#[test]
fn citizenapp_release_assets_use_standard_public_platforms() {
    let flow_root = tata_flow_root();
    let tata_console_root = flow_root
        .parent()
        .expect("TATA_CONSOLE_FLOW_ROOT 必须位于 tataconsole/flows")
        .to_path_buf();
    let action_path = flow_root.join("gmb/citizenapp/action.yml");
    let action = fs::read_to_string(&action_path)
        .unwrap_or_else(|e| panic!("读取 {} 失败: {e}", action_path.display()));
    let step = |start: &str, end: &str| {
        let start_index = action
            .find(start)
            .unwrap_or_else(|| panic!("CitizenApp action 缺少步骤 {start}"));
        let end_index = action[start_index..]
            .find(end)
            .map(|offset| start_index + offset)
            .unwrap_or_else(|| panic!("CitizenApp action 步骤 {start} 缺少结束边界 {end}"));
        &action[start_index..end_index]
    };
    let android_writer = step(
        "name: 生成并核验 Android 正式清单",
        "name: 签署 Android 正式资产构建来源",
    );
    let ios_writer = step(
        "name: 生成并核验 iOS 正式清单",
        "name: 签署 iOS 正式资产构建来源",
    );
    assert_eq!(
        android_writer.matches("platform: \"Android\"").count(),
        2,
        "CitizenApp Android APK/AAB 必须各声明一次标准公开平台"
    );
    assert_eq!(
        ios_writer.matches("platform: 'iOS'").count(),
        1,
        "CitizenApp iOS IPA 必须声明一次标准公开平台"
    );
    for (writer, forbidden) in [
        (android_writer, "platform: \"android\""),
        (ios_writer, "platform: 'ios'"),
    ] {
        assert!(
            !writer.contains(forbidden),
            "CitizenApp 正式 manifest 禁止恢复小写公开平台 {forbidden}"
        );
    }
    for internal_wire in [
        "--prefix citizenapp-android-v --product-id citizenapp",
        "--target android --workflow gmb.citizenapp.android.ci",
        "--prefix citizenapp-ios-v --product-id citizenapp",
        "--target ios --workflow gmb.citizenapp.ios.ci",
    ] {
        assert!(
            action.contains(internal_wire),
            "CitizenApp 内部 Tag/target wire 不得在本步局部改写 {internal_wire}"
        );
    }

    let release_test_path = repo_root().join("citizenapp/test/release_manifest.test.mjs");
    let release_test = fs::read_to_string(&release_test_path)
        .unwrap_or_else(|e| panic!("读取 {} 失败: {e}", release_test_path.display()));
    for required in [
        "gmb/citizenapp/action.yml",
        "中央 action 中真正随 Release 上线的 heredoc",
        "const topLevelFields = [",
        "const assetFields = ['asset_name', 'asset_sha256', 'platform'];",
        "platform: publicPlatform",
        "value.assets[0].platform = 'android'",
        "value.assets[0].platform = 'ios'",
        "正式版本 Tag 前缀与内部 target 继续使用既有小写身份",
    ] {
        assert!(
            release_test.contains(required),
            "CitizenApp Release 测试缺少真实 writer 或失败关闭合同 {required}"
        );
    }

    let publisher_path = tata_console_root.join("app/Sources/MobileStorePublisher.swift");
    let publisher = fs::read_to_string(&publisher_path)
        .unwrap_or_else(|e| panic!("读取 {} 失败: {e}", publisher_path.display()));
    let common_validator_start = publisher
        .find("private func validatePublishManifest(")
        .expect("MobileStorePublisher 缺少通用 manifest 验证器");
    let mobile_validator_start = publisher
        .find("static func validateCitizenMobileReleaseManifest(")
        .expect("MobileStorePublisher 缺少公民移动 Release 共用验证器");
    let common_validator = &publisher[common_validator_start..mobile_validator_start];
    let call_offset = common_validator
        .find("try Self.validateCitizenMobileReleaseManifest(")
        .expect("通用 manifest 验证器未调用公民移动 Release 共用验证器");
    let generic_guard_offset = common_validator
        .find("guard manifest[\"product_id\"]")
        .expect("通用 manifest 验证器缺少既有身份检查");
    assert!(
        call_offset < generic_guard_offset,
        "公民移动 Release 共用验证必须先于文件读取和既有候选检查失败关闭"
    );
    let mobile_validator_end = publisher[mobile_validator_start..]
        .find("private func publishAppleBuild(")
        .map(|offset| mobile_validator_start + offset)
        .expect("公民移动 Release 共用验证器缺少结束边界");
    let mobile_validator = &publisher[mobile_validator_start..mobile_validator_end];
    for required in [
        "guard productID == \"citizenapp\" || productID == \"citizenwallet\" else { return }",
        "let product = try StoreProduct.resolve(productID)",
        "case \"ios\"",
        "publicPlatform = \"iOS\"",
        "expectedAssetNames = [\"\\(productID).ipa\"]",
        "case \"android\"",
        "publicPlatform = \"Android\"",
        "expectedAssetNames = [\"\\(productID).apk\", \"\\(productID).aab\"]",
        "Set(manifest.keys) == expectedManifestKeys",
        "manifest[\"bundle_id\"] as? String == product.bundleID",
        "manifest[\"package_name\"] as? String == product.packageName",
        "Set(asset.keys) == expectedAssetKeys",
        "asset[\"platform\"] as? String == publicPlatform",
        "of: \"^[0-9a-f]{64}$\", options: .regularExpression",
        "assetNames.insert(assetName).inserted",
        "assetNames == expectedAssetNames",
    ] {
        assert!(
            mobile_validator.contains(required),
            "公民移动原生发布器缺少平台映射或严格字段合同 {required}"
        );
    }

    let dictionary_path = tata_console_root.join("dictionary/gmb/citizenapp.json");
    let dictionary_text = fs::read_to_string(&dictionary_path)
        .unwrap_or_else(|e| panic!("读取 {} 失败: {e}", dictionary_path.display()));
    let dictionary: Value = serde_json::from_str(&dictionary_text)
        .unwrap_or_else(|e| panic!("解析 {} 失败: {e}", dictionary_path.display()));
    let contracts = dictionary["contracts"]
        .as_array()
        .expect("CitizenApp contracts 必须是数组");
    let matching = contracts
        .iter()
        .filter(|contract| contract["contract_id"] == "citizenapp_release_identity")
        .collect::<Vec<_>>();
    assert_eq!(matching.len(), 1, "CitizenApp 必须只有一个正式发布身份合同");
    let contract = matching[0];
    let string_set = |value: &Value| {
        value
            .as_array()
            .expect("CitizenApp 发布合同字段必须是数组")
            .iter()
            .map(|item| item.as_str().expect("合同字段必须是字符串").to_string())
            .collect::<BTreeSet<String>>()
    };
    assert_eq!(
        string_set(&contract["paths"]),
        ["citizenapp/test/release_manifest.test.mjs"]
            .into_iter()
            .map(str::to_string)
            .collect::<BTreeSet<String>>()
    );
    assert_eq!(
        string_set(&contract["fields"]),
        ["platform"]
            .into_iter()
            .map(str::to_string)
            .collect::<BTreeSet<String>>()
    );
    assert!(
        contract["value_sets"].as_array().is_some_and(Vec::is_empty),
        "CitizenApp 发布合同必须复用共享 platform 字段且不得复制值集"
    );
}

/// CitizenWallet 与 CitizenApp 共用同一原生移动清单验证器；产品仓测试必须直接执行
/// TataConsole 唯一 writer，公开平台只允许 `Android`/`iOS`，内部签名 wire 保持小写。
#[test]
fn citizenwallet_release_assets_use_standard_public_platforms() {
    let flow_root = tata_flow_root();
    let tata_console_root = flow_root
        .parent()
        .expect("TATA_CONSOLE_FLOW_ROOT 必须位于 tataconsole/flows")
        .to_path_buf();
    let action_path = flow_root.join("gmb/citizenwallet/action.yml");
    let action = fs::read_to_string(&action_path)
        .unwrap_or_else(|e| panic!("读取 {} 失败: {e}", action_path.display()));
    let step = |start: &str, end: &str| {
        let start_index = action
            .find(start)
            .unwrap_or_else(|| panic!("CitizenWallet action 缺少步骤 {start}"));
        let end_index = action[start_index..]
            .find(end)
            .map(|offset| start_index + offset)
            .unwrap_or_else(|| panic!("CitizenWallet action 步骤 {start} 缺少结束边界 {end}"));
        &action[start_index..end_index]
    };
    let android_writer = step(
        "name: 生成并核验 Android 正式清单",
        "name: 签署 Android 正式资产构建来源",
    );
    let ios_writer = step(
        "name: 生成并核验 iOS 正式清单",
        "name: 签署 iOS 正式资产构建来源",
    );
    assert_eq!(
        android_writer.matches("platform: \"Android\"").count(),
        2,
        "CitizenWallet Android APK/AAB 必须各声明一次标准公开平台"
    );
    assert_eq!(
        ios_writer.matches("platform: 'iOS'").count(),
        1,
        "CitizenWallet iOS IPA 必须声明一次标准公开平台"
    );
    for (writer, forbidden) in [
        (android_writer, "platform: \"android\""),
        (ios_writer, "platform: 'ios'"),
    ] {
        assert!(
            !writer.contains(forbidden),
            "CitizenWallet 正式 manifest 禁止恢复小写公开平台 {forbidden}"
        );
    }
    for internal_wire in [
        "--prefix citizenwallet-android-v --product-id citizenwallet",
        "--target android --workflow gmb.citizenwallet.android.ci",
        "--prefix citizenwallet-ios-v --product-id citizenwallet",
        "--target ios --workflow gmb.citizenwallet.ios.ci",
    ] {
        assert!(
            action.contains(internal_wire),
            "CitizenWallet 内部 Tag/target wire 不得在本步局部改写 {internal_wire}"
        );
    }
    assert_eq!(
        action
            .matches("name: 校验正式 Release manifest 公开身份")
            .count(),
        2,
        "CitizenWallet Android/iOS CI 必须各执行一次正式 manifest 合同测试"
    );
    assert_eq!(
        action
            .matches("node --test citizenwallet/test/release_manifest.test.mjs")
            .count(),
        2,
        "CitizenWallet 真实 writer 测试不得成为只由人工运行的测试孤岛"
    );

    let release_test_path = repo_root().join("citizenwallet/test/release_manifest.test.mjs");
    let release_test = fs::read_to_string(&release_test_path)
        .unwrap_or_else(|e| panic!("读取 {} 失败: {e}", release_test_path.display()));
    for required in [
        "gmb/citizenwallet/action.yml",
        "测试必须执行中央 action 真正上线的 heredoc",
        "const topLevelFields = [",
        "const assetFields = ['asset_name', 'asset_sha256', 'platform'];",
        "publicName: 'Android'",
        "publicName: 'iOS'",
        "value.assets[0].platform = 'android'",
        "value.assets[0].platform = 'ios'",
        "步骤所属 job 与 writer 同属发布合同",
        "writer 必须绑定到对应正式 Release job",
        "['产品身份漂移'",
        "['Apple 身份漂移'",
        "['Android 身份漂移'",
        "['资产摘要漂移'",
        "['资产重复'",
        "正式 Tag 与内部 target/workflow 继续使用既有小写 wire",
    ] {
        assert!(
            release_test.contains(required),
            "CitizenWallet Release 测试缺少真实 writer 或失败关闭合同 {required}"
        );
    }

    let publisher_path = tata_console_root.join("app/Sources/MobileStorePublisher.swift");
    let publisher = fs::read_to_string(&publisher_path)
        .unwrap_or_else(|e| panic!("读取 {} 失败: {e}", publisher_path.display()));
    for required in [
        "case \"citizenwallet\"",
        "bundleID: \"ios.citizenwallet\", packageName: \"com.crcfrcn.citizenwallet\"",
        "guard productID == \"citizenapp\" || productID == \"citizenwallet\" else { return }",
        "expectedAssetNames = [\"\\(productID).ipa\"]",
        "expectedAssetNames = [\"\\(productID).apk\", \"\\(productID).aab\"]",
    ] {
        assert!(
            publisher.contains(required),
            "公民移动原生发布器缺少 CitizenWallet 共用严格合同 {required}"
        );
    }
    // 中文边界：正式发布入口必须在读取候选二进制、访问 Keychain 或调用商店网络前
    // 完成同一个清单验证；只测试 inspectCandidate 不能阻断 publishCandidate 顺序回退。
    let publish_start = publisher
        .find("func publishCandidate(")
        .expect("MobileStorePublisher 缺少正式发布入口");
    let publish_end = publisher[publish_start..]
        .find("private func publishVersion(")
        .map(|offset| publish_start + offset)
        .expect("MobileStorePublisher 正式发布入口缺少结束边界");
    let publish_candidate = &publisher[publish_start..publish_end];
    let publish_validation = publish_candidate
        .find("let githubRunNumber = try validatePublishManifest(")
        .expect("正式发布入口未执行统一清单验证");
    for side_effect in [
        "let artifactData = try checkedPublishFile(",
        "let issuerID = try textSecret(",
        "let serviceAccountData = try vault.read(",
        "let deploymentID = try publishAppleBuild(",
        "let deploymentID = try publishGoogleBundle(",
    ] {
        let side_effect_offset = publish_candidate
            .find(side_effect)
            .unwrap_or_else(|| panic!("正式发布入口缺少受保护操作 {side_effect}"));
        assert!(
            publish_validation < side_effect_offset,
            "统一清单验证必须早于候选二进制、Keychain 与商店网络操作 {side_effect}"
        );
    }
    let publisher_tests_path = tata_console_root.join("app/Tests/MobileStorePublisherTests.swift");
    let publisher_tests = fs::read_to_string(&publisher_tests_path)
        .unwrap_or_else(|e| panic!("读取 {} 失败: {e}", publisher_tests_path.display()));
    for required in [
        "testCitizenAppCandidateInspectionRejectsPublicPlatformDrift",
        "testCitizenWalletCandidateInspectionUsesTheSharedStrictManifestContract",
        "testCitizenWalletCandidateInspectionRejectsAssetPlatformDrift",
        "testCitizenWalletCandidateInspectionRejectsFieldDrift",
        "testCitizenWalletCandidateInspectionRejectsIdentityDrift",
        "testCitizenWalletCandidateInspectionRejectsSHAContractDrift",
        "testCitizenWalletCandidateInspectionRejectsAssetSetDrift",
        "String(repeating: \"0\", count: 64)",
        "合法格式但与 fixture 字节不符",
        "testTuyuProductDoesNotEnterCitizenMobileManifestContract",
    ] {
        assert!(
            publisher_tests.contains(required),
            "MobileStorePublisherTests 缺少 CitizenWallet 正反消费门禁 {required}"
        );
    }

    let dictionary_path = tata_console_root.join("dictionary/gmb/citizenwallet.json");
    let dictionary_text = fs::read_to_string(&dictionary_path)
        .unwrap_or_else(|e| panic!("读取 {} 失败: {e}", dictionary_path.display()));
    let dictionary: Value = serde_json::from_str(&dictionary_text)
        .unwrap_or_else(|e| panic!("解析 {} 失败: {e}", dictionary_path.display()));
    let contracts = dictionary["contracts"]
        .as_array()
        .expect("CitizenWallet contracts 必须是数组");
    let matching = contracts
        .iter()
        .filter(|contract| contract["contract_id"] == "citizenwallet_release_identity")
        .collect::<Vec<_>>();
    assert_eq!(
        matching.len(),
        1,
        "CitizenWallet 必须只有一个正式发布身份合同"
    );
    let contract = matching[0];
    let string_set = |value: &Value| {
        value
            .as_array()
            .expect("CitizenWallet 发布合同字段必须是数组")
            .iter()
            .map(|item| item.as_str().expect("合同字段必须是字符串").to_string())
            .collect::<BTreeSet<String>>()
    };
    assert_eq!(
        string_set(&contract["paths"]),
        ["citizenwallet/test/release_manifest.test.mjs"]
            .into_iter()
            .map(str::to_string)
            .collect::<BTreeSet<String>>()
    );
    assert_eq!(
        string_set(&contract["fields"]),
        ["platform"]
            .into_iter()
            .map(str::to_string)
            .collect::<BTreeSet<String>>()
    );
    assert!(
        contract["value_sets"].as_array().is_some_and(Vec::is_empty),
        "CitizenWallet 发布合同必须复用共享 platform 字段且不得复制值集"
    );
}

/// CitizenWallet 文档必须把公开 Android 平台名与官方 ABI 技术值分开表达。
#[test]
fn citizenwallet_documentation_separates_android_platform_from_abi() {
    let path = repo_root().join("citizenwallet/design-qa.md");
    let text =
        fs::read_to_string(&path).unwrap_or_else(|e| panic!("读取 {} 失败: {e}", path.display()));

    // Android 是公开平台名；`arm64-v8a` 只属于 Android 官方 ABI 技术值。
    assert!(
        text.contains("Android 的 `arm64-v8a` ABI 未签名 Release APK"),
        "{}: 缺少 Android 平台与 arm64-v8a ABI 的类型化表述",
        path.display()
    );
    assert!(
        !text.contains("Android ARM64"),
        "{}: 禁止把处理器架构拼进 Android 公开平台名",
        path.display()
    );
}

/// CitizenChain 源码注释必须用 Rust target triple 表达 `c_char` 的机器类型差异。
#[test]
fn citizenchain_device_password_uses_target_triples_for_c_char_types() {
    let path = repo_root().join("citizenchain/node/src/settings/device_password.rs");
    let text =
        fs::read_to_string(&path).unwrap_or_else(|e| panic!("读取 {} 失败: {e}", path.display()));

    for required in [
        "`aarch64-unknown-linux-gnu` 上为 `u8`",
        "`x86_64-unknown-linux-gnu` 上为 `i8`",
    ] {
        assert!(
            text.contains(required),
            "{}: 缺少官方 Rust target triple 与 c_char 类型合同 {required}",
            path.display()
        );
    }
    for forbidden in ["Linux ARM64", "ARM64 与 AMD64"] {
        assert!(
            !text.contains(forbidden),
            "{}: 禁止用架构拼接式公开平台名表达 Rust target 差异 {forbidden}",
            path.display()
        );
    }
}

/// CitizenChain macOS updater 必须把公开平台和交付用途拆成独立路径段。
#[test]
fn citizenchain_macos_updater_uses_typed_public_route() {
    let repo_root = repo_root();
    let tata_console_root = tata_flow_root()
        .parent()
        .expect("TATA_CONSOLE_FLOW_ROOT 必须位于 tataconsole/flows")
        .to_path_buf();
    let cases = [
        (
            "citizenchain/node/tauri.conf.json",
            repo_root.join("citizenchain/node/tauri.conf.json"),
            "/download/citizenchain/macOS/updater",
        ),
        (
            "citizenserve/src/downloads/citizenchain.ts",
            repo_root.join("citizenserve/src/downloads/citizenchain.ts"),
            "/download/citizenchain/macOS/updater",
        ),
        (
            "citizenserve/src/limits/catalog.ts",
            repo_root.join("citizenserve/src/limits/catalog.ts"),
            "macOS(?:\\/updater)?",
        ),
        (
            "TataConsole CitizenChainDownloadPublisher.swift",
            tata_console_root.join("app/Sources/CitizenChainDownloadPublisher.swift"),
            "/download/citizenchain/macOS/updater",
        ),
    ];

    let mut violations = Vec::new();
    for (label, path, required) in cases {
        let text = fs::read_to_string(&path)
            .unwrap_or_else(|e| panic!("读取 {} 失败: {e}", path.display()));
        if !text.contains(required) {
            violations.push(format!("{label}: 缺少类型化 macOS updater 路由 {required}"));
        }
        for forbidden in [concat!("macos", "-arm64-updater"), "macOS-updater"] {
            if text.contains(forbidden) {
                violations.push(format!("{label}: 禁止旧路由或复合平台名 {forbidden}"));
            }
        }
    }

    assert!(
        violations.is_empty(),
        "CitizenChain macOS updater 公开路由守卫失败:\n{}",
        violations.join("\n")
    );
}

/// CitizenChain 四端安装入口必须直接使用统一公开平台名，内部发布键不得泄漏到 URL。
#[test]
fn citizenchain_install_downloads_use_standard_public_routes() {
    let repo_root = repo_root();
    let tata_console_root = tata_flow_root()
        .parent()
        .expect("TATA_CONSOLE_FLOW_ROOT 必须位于 tataconsole/flows")
        .to_path_buf();
    let cases = [
        (
            "CitizenServe 下载映射",
            repo_root.join("citizenserve/src/downloads/citizenchain.ts"),
            [
                "'/download/citizenchain/macOS'",
                "'/download/citizenchain/Windows'",
                "'/download/citizenchain/LinuxARM'",
                "'/download/citizenchain/LinuxAMD'",
            ],
        ),
        (
            "CitizenWeb 下载菜单",
            repo_root.join("citizenweb/src/pages/Ecosystem.tsx"),
            [
                "'/download/citizenchain/macOS'",
                "'/download/citizenchain/Windows'",
                "'/download/citizenchain/LinuxARM'",
                "'/download/citizenchain/LinuxAMD'",
            ],
        ),
        (
            "TataConsole 下载发布验收",
            tata_console_root.join("app/Sources/CitizenChainDownloadPublisher.swift"),
            [
                "\"/download/citizenchain/macOS\"",
                "\"/download/citizenchain/Windows\"",
                "\"/download/citizenchain/LinuxARM\"",
                "\"/download/citizenchain/LinuxAMD\"",
            ],
        ),
    ];
    let forbidden_paths = [
        concat!("/download/citizenchain/macos", "-arm64"),
        "/download/citizenchain/windows-x86_64",
        "/download/citizenchain/linux-arm64",
        "/download/citizenchain/linux-amd64",
        "/download/citizenchain/linux-arm",
        "/download/citizenchain/linux-amd",
    ];
    let mut violations = Vec::new();
    for (label, path, required_paths) in cases {
        let text = fs::read_to_string(&path)
            .unwrap_or_else(|e| panic!("读取 {} 失败: {e}", path.display()));
        for required in required_paths {
            if !text.contains(required) {
                violations.push(format!("{label}: 缺少标准公开安装路径 {required}"));
            }
        }
        for forbidden in forbidden_paths {
            if text.contains(forbidden) {
                violations.push(format!("{label}: 禁止旧公开安装路径 {forbidden}"));
            }
        }
    }

    let catalog_path = repo_root.join("citizenserve/src/limits/catalog.ts");
    let catalog = fs::read_to_string(&catalog_path)
        .unwrap_or_else(|e| panic!("读取 {} 失败: {e}", catalog_path.display()));
    let typed_route = "citizenchain\\/(?:macOS(?:\\/updater)?|Windows|LinuxARM|LinuxAMD)";
    if !catalog.contains(typed_route) {
        violations.push(format!(
            "CitizenServe 限流白名单缺少标准公开安装路由 {typed_route}"
        ));
    }

    assert!(
        violations.is_empty(),
        "CitizenChain 四端公开安装路由守卫失败:\n{}",
        violations.join("\n")
    );
}

/// CitizenServe publication wire 与 TataConsole 动作输入是两个字段域，且必须共用一份跨仓 golden。
#[test]
fn citizenchain_download_publication_wire_is_cross_runtime_compatible() {
    let repo_root = repo_root();
    let tata_console_root = tata_flow_root()
        .parent()
        .expect("TATA_CONSOLE_FLOW_ROOT 必须位于 tataconsole/flows")
        .to_path_buf();
    let fixture_path =
        tata_console_root.join("test/citizenchain-download-publication-interop-v1.json");
    let fixture_text = fs::read_to_string(&fixture_path)
        .unwrap_or_else(|e| panic!("读取 {} 失败: {e}", fixture_path.display()));
    let fixture: Value = serde_json::from_str(&fixture_text)
        .unwrap_or_else(|e| panic!("解析 {} 失败: {e}", fixture_path.display()));
    let fixture_keys = fixture
        .as_object()
        .expect("下载发布互操作 golden 必须是 JSON 对象")
        .keys()
        .map(String::as_str)
        .collect::<BTreeSet<_>>();
    let expected_fixture_keys = [
        "action_tag_field",
        "contract_version",
        "download_path",
        "github_repository",
        "location",
        "platform",
        "publication_tag_field",
        "put_body_json",
        "snapshot_anchor",
        "snapshot_json",
    ]
    .into_iter()
    .collect::<BTreeSet<_>>();
    assert_eq!(fixture_keys, expected_fixture_keys, "golden 根字段闭集漂移");
    assert_eq!(fixture["contract_version"], 1);
    assert_eq!(fixture["github_repository"], "VoyagerRhett/GMB");
    assert_eq!(fixture["action_tag_field"], "release_tag");
    assert_eq!(fixture["publication_tag_field"], "version_tag");
    assert_eq!(fixture["platform"], "macos");
    assert_eq!(fixture["download_path"], "/download/citizenchain/macOS");
    assert_eq!(
        fixture["location"],
        "https://github.com/VoyagerRhett/GMB/releases/download/\
citizenchain-node-macos-v1.2.3/citizenchain-node-macOS-v1.2.3.dmg"
    );
    assert_eq!(
        fixture["snapshot_anchor"],
        "ccdp:macos:1:03939a59159d803ddc044c13c3aa0368006a7f0d69e3265c51b4d33ff6c9f9fc"
    );

    let put_body: Value = serde_json::from_str(
        fixture["put_body_json"]
            .as_str()
            .expect("golden put_body_json 必须是字符串"),
    )
    .expect("golden put_body_json 必须是合法 JSON");
    let put_keys = put_body
        .as_object()
        .expect("golden PUT body 必须是 JSON 对象")
        .keys()
        .map(String::as_str)
        .collect::<BTreeSet<_>>();
    assert_eq!(
        put_keys,
        ["expected_revision", "publication"]
            .into_iter()
            .collect::<BTreeSet<_>>()
    );
    let publication = put_body["publication"]
        .as_object()
        .expect("golden publication 必须是 JSON 对象");
    let publication_keys = publication
        .keys()
        .map(String::as_str)
        .collect::<BTreeSet<_>>();
    assert_eq!(
        publication_keys,
        ["asset_name", "asset_sha256", "source_sha", "version_tag"]
            .into_iter()
            .collect::<BTreeSet<_>>()
    );
    assert!(!publication.contains_key("release_tag"));

    let snapshot: Value = serde_json::from_str(
        fixture["snapshot_json"]
            .as_str()
            .expect("golden snapshot_json 必须是字符串"),
    )
    .expect("golden snapshot_json 必须是合法 JSON");
    let snapshot_object = snapshot
        .as_object()
        .expect("golden snapshot 必须是 JSON 对象");
    let snapshot_keys = snapshot_object
        .keys()
        .map(String::as_str)
        .collect::<BTreeSet<_>>();
    assert_eq!(
        snapshot_keys,
        [
            "asset_name",
            "asset_sha256",
            "platform",
            "published_at",
            "revision",
            "source_sha",
            "version_tag",
        ]
        .into_iter()
        .collect::<BTreeSet<_>>()
    );
    assert!(!snapshot_object.contains_key("release_tag"));

    let fixture_name = "citizenchain-download-publication-interop-v1.json";
    let serve_test_path =
        repo_root.join("citizenserve/test/citizenchain_download_publication.test.ts");
    let swift_test_path = tata_console_root.join("app/Tests/ViewContractTests.swift");
    let node_test_path = tata_console_root.join("test/native-ui.test.mjs");
    for path in [&serve_test_path, &swift_test_path, &node_test_path] {
        let text = fs::read_to_string(path)
            .unwrap_or_else(|e| panic!("读取 {} 失败: {e}", path.display()));
        assert!(
            text.contains(fixture_name),
            "{}: 必须消费唯一下载发布互操作 golden",
            path.display()
        );
    }

    let serve_source_path = repo_root.join("citizenserve/src/downloads/citizenchain.ts");
    let serve_source = fs::read_to_string(&serve_source_path)
        .unwrap_or_else(|e| panic!("读取 {} 失败: {e}", serve_source_path.display()));
    assert!(serve_source.contains("https://github.com/VoyagerRhett/GMB/releases/download/"));
    // 所有 GitHub 下载地址必须来自现行唯一仓库，不能只检查某条正确地址存在。
    assert_eq!(
        serve_source.matches("https://github.com/").count(),
        serve_source.matches("https://github.com/VoyagerRhett/GMB/").count(),
    );

    let swift_source_path =
        tata_console_root.join("app/Sources/CitizenChainDownloadPublisher.swift");
    let swift_source = fs::read_to_string(&swift_source_path)
        .unwrap_or_else(|e| panic!("读取 {} 失败: {e}", swift_source_path.display()));
    for required in [
        "\"version_tag\": input.releaseTag",
        "oldPublication[\"version_tag\"]",
        "\"revision\", \"source_sha\", \"version_tag\"",
        "Set(value.keys) == Set([\"product_id\", \"platform\", \"release_tag\", \"source_sha\"])",
        "https://github.com/VoyagerRhett/GMB/releases/download/",
    ] {
        assert!(
            swift_source.contains(required),
            "{}: 缺少跨字段域映射或权威仓库合同 {required}",
            swift_source_path.display()
        );
    }
    assert_eq!(
        swift_source.matches("https://github.com/").count(),
        swift_source.matches("https://github.com/VoyagerRhett/GMB/").count(),
    );
    for forbidden in [
        "\"release_tag\": input.releaseTag",
        "oldPublication[\"release_tag\"]",
    ] {
        assert!(
            !swift_source.contains(forbidden),
            "{}: 禁止 publication wire 旧字段 {forbidden}",
            swift_source_path.display()
        );
    }
}

/// CitizenChain 自定义 Release 资产必须在中央流程、发布器、下载服务和 golden 间一致。
#[test]
fn citizenchain_release_assets_are_cross_repository_consistent() {
    let repo_root = repo_root();
    let flow_root = tata_flow_root();
    let tata_console_root = flow_root
        .parent()
        .expect("TATA_CONSOLE_FLOW_ROOT 必须位于 tataconsole/flows")
        .to_path_buf();
    let action_path = flow_root.join("gmb/citizenchain-node/action.yml");
    let remote_jobs_path = flow_root.join("gmb/citizenchain-node/remote-jobs.json");
    let swift_path = tata_console_root.join("app/Sources/CitizenChainDownloadPublisher.swift");
    let serve_path = repo_root.join("citizenserve/src/downloads/citizenchain.ts");
    let fixture_path =
        tata_console_root.join("test/citizenchain-download-publication-interop-v1.json");

    let action = fs::read_to_string(&action_path)
        .unwrap_or_else(|e| panic!("读取 {} 失败: {e}", action_path.display()));
    let remote_jobs_text = fs::read_to_string(&remote_jobs_path)
        .unwrap_or_else(|e| panic!("读取 {} 失败: {e}", remote_jobs_path.display()));
    let remote_jobs: Value = serde_json::from_str(&remote_jobs_text)
        .unwrap_or_else(|e| panic!("解析 {} 失败: {e}", remote_jobs_path.display()));
    let swift = fs::read_to_string(&swift_path)
        .unwrap_or_else(|e| panic!("读取 {} 失败: {e}", swift_path.display()));
    let serve = fs::read_to_string(&serve_path)
        .unwrap_or_else(|e| panic!("读取 {} 失败: {e}", serve_path.display()));
    let fixture_text = fs::read_to_string(&fixture_path)
        .unwrap_or_else(|e| panic!("读取 {} 失败: {e}", fixture_path.display()));
    let fixture: Value = serde_json::from_str(&fixture_text)
        .unwrap_or_else(|e| panic!("解析 {} 失败: {e}", fixture_path.display()));

    // platform 是 D1/流程内部键，stem 才是公开资产平台段；Tag 前缀保持原合同。
    let contracts = [
        (
            "linux-arm",
            "citizenchain-node-LinuxARM",
            "citizenchain-node-LinuxARM.deb",
            "citizenchain-node-LinuxARM.AppImage",
            "citizenchain-node-latest-LinuxARM.json",
        ),
        (
            "linux-amd",
            "citizenchain-node-LinuxAMD",
            "citizenchain-node-LinuxAMD.deb",
            "citizenchain-node-LinuxAMD.AppImage",
            "citizenchain-node-latest-LinuxAMD.json",
        ),
        (
            "macos",
            "citizenchain-node-macOS",
            "citizenchain-node-macOS.dmg",
            "citizenchain-node-macOS.app.tar.gz",
            "citizenchain-node-latest-macOS.json",
        ),
        (
            "windows",
            "citizenchain-node-Windows",
            "citizenchain-node-Windows.exe",
            "",
            "citizenchain-node-latest-Windows.json",
        ),
    ];
    let legacy_asset_fragments = [
        "citizenchain-node-linux-arm",
        "citizenchain-node-linux-amd",
        "citizenchain-node-macos",
        "citizenchain-node-windows",
        "citizenchain-node-latest-linux-arm",
        "citizenchain-node-latest-linux-amd",
        "citizenchain-node-latest-macos",
        "citizenchain-node-latest-windows",
    ];
    let reject_legacy_asset = |label: &str, value: &str, violations: &mut Vec<String>| {
        for legacy in &legacy_asset_fragments {
            if value.contains(legacy) {
                violations.push(format!("{label}: 自定义资产字段禁止旧名称 {legacy}"));
            }
        }
    };
    let mut violations = Vec::new();

    // remote-jobs 只检查三个自定义资产字段；runner 架构、deb_arch 和内部 platform
    // 属于官方技术值或内部键，不能因为含 ARM64/amd64/macos 等字样而被误杀。
    let jobs = remote_jobs["jobs"]
        .as_array()
        .expect("remote-jobs.json 的 jobs 必须是数组");
    let contexts = jobs
        .iter()
        .enumerate()
        .filter_map(|(index, job)| {
            let context = job.get("context")?.as_object()?;
            context
                .contains_key("installer_name")
                .then_some((index, context))
        })
        .collect::<Vec<_>>();
    for &(platform, _, installer, updater, manifest) in &contracts {
        let matching = contexts
            .iter()
            .filter(|(_, context)| {
                context.get("platform").and_then(Value::as_str) == Some(platform)
            })
            .collect::<Vec<_>>();
        if matching.len() != 2 {
            violations.push(format!(
                "remote-jobs.json: {platform} 必须各有一份 CI 和 Release 资产上下文，实际 {} 份",
                matching.len()
            ));
        }
        for (index, context) in matching {
            for (field, expected) in [
                ("installer_name", installer),
                ("updater_asset_name", updater),
                ("updater_manifest_name", manifest),
            ] {
                let actual = context.get(field).and_then(Value::as_str).unwrap_or("");
                if actual != expected {
                    violations.push(format!(
                        "remote-jobs.json jobs[{index}].context.{field}: 期望 {expected:?}，实际 {actual:?}"
                    ));
                }
                reject_legacy_asset(
                    &format!("remote-jobs.json jobs[{index}].context.{field}"),
                    actual,
                    &mut violations,
                );
            }
        }
    }

    // action 中的矩阵是内嵌 JSON；解析资产字段而不是全文扫描，避免命中
    // linux-aarch64、windows-x86_64、ARM64/X64 runner 或 Debian 包架构。
    let mut action_matrix_counts = vec![0_usize; contracts.len()];
    for (line_index, line) in action.lines().enumerate() {
        let Some(marker) = line.find("desktop_matrix=") else {
            continue;
        };
        let tail = &line[marker + "desktop_matrix=".len()..];
        let start = tail.find('[').unwrap_or_else(|| {
            panic!(
                "{}:{} desktop_matrix 缺少 JSON 数组",
                action_path.display(),
                line_index + 1
            )
        });
        let end = tail.rfind(']').unwrap_or_else(|| {
            panic!(
                "{}:{} desktop_matrix 缺少 JSON 数组结尾",
                action_path.display(),
                line_index + 1
            )
        });
        let matrix: Value = serde_json::from_str(&tail[start..=end]).unwrap_or_else(|e| {
            panic!(
                "解析 {}:{} desktop_matrix 失败: {e}",
                action_path.display(),
                line_index + 1
            )
        });
        let object = matrix
            .as_array()
            .filter(|items| items.len() == 1)
            .and_then(|items| items[0].as_object())
            .unwrap_or_else(|| {
                panic!(
                    "{}:{} desktop_matrix 必须只含一个对象",
                    action_path.display(),
                    line_index + 1
                )
            });
        let platform = object
            .get("platform")
            .and_then(Value::as_str)
            .expect("desktop_matrix 缺少 platform");
        let Some((contract_index, contract)) = contracts
            .iter()
            .enumerate()
            .find(|(_, contract)| contract.0 == platform)
        else {
            violations.push(format!(
                "action.yml:{} desktop_matrix 使用未知平台 {platform}",
                line_index + 1
            ));
            continue;
        };
        action_matrix_counts[contract_index] += 1;
        for (field, expected) in [
            ("installer_name", contract.2),
            ("updater_asset_name", contract.3),
            ("updater_manifest_name", contract.4),
        ] {
            let actual = object.get(field).and_then(Value::as_str).unwrap_or("");
            if actual != expected {
                violations.push(format!(
                    "action.yml:{} {platform}.{field}: 期望 {expected:?}，实际 {actual:?}",
                    line_index + 1
                ));
            }
            reject_legacy_asset(
                &format!("action.yml:{} {platform}.{field}", line_index + 1),
                actual,
                &mut violations,
            );
        }
    }
    for (index, count) in action_matrix_counts.into_iter().enumerate() {
        if count != 2 {
            violations.push(format!(
                "action.yml: {} 必须各有一份 CI 和 Release desktop_matrix，实际 {count} 份",
                contracts[index].0
            ));
        }
    }
    for &(_, _, _, _, manifest) in &contracts {
        let output = format!("fs.writeFileSync('citizenchain-release/{manifest}'");
        if !action.contains(&output) {
            violations.push(format!("action.yml: 缺少正式 updater 清单输出 {manifest}"));
        }
    }
    for (construction, expected_count) in [
        (
            r#"versioned_installer="${INSTALLER_NAME%.deb}-v${GMB_SOFTWARE_VERSION}.deb""#,
            2,
        ),
        (
            r#"versioned_updater="${UPDATER_ASSET_NAME%.AppImage}-v${GMB_SOFTWARE_VERSION}.AppImage""#,
            2,
        ),
        (
            r#"versioned_installer="${INSTALLER_NAME%.dmg}-v${GMB_SOFTWARE_VERSION}.dmg""#,
            1,
        ),
        (
            r#"versioned_updater="${UPDATER_ASSET_NAME%.app.tar.gz}-v${GMB_SOFTWARE_VERSION}.app.tar.gz""#,
            1,
        ),
        (
            r#"$versionedName = $installerName -replace '\.exe$', "-v$env:GMB_SOFTWARE_VERSION.exe""#,
            1,
        ),
    ] {
        let actual_count = action.matches(construction).count();
        if actual_count != expected_count {
            violations.push(format!(
                "action.yml: 版本化资产构造 {construction} 应出现 {expected_count} 次，实际 {actual_count} 次"
            ));
        }
    }
    for (line_index, line) in action.lines().enumerate() {
        if line.contains("fs.writeFileSync('citizenchain-release/citizenchain-node-latest-") {
            reject_legacy_asset(
                &format!("action.yml:{} updater 清单输出", line_index + 1),
                line,
                &mut violations,
            );
        }
    }

    for &(platform, stem, _, _, manifest) in &contracts {
        for required in [
            format!("installer = \"{stem}\""),
            format!("manifest = \"{manifest}\""),
        ] {
            if !swift.contains(&required) {
                violations.push(format!("Swift {platform}: 缺少资产合同 {required}"));
            }
        }
        let updater = if platform == "windows" {
            "updater = installer".to_string()
        } else {
            format!("updater = \"{stem}\"")
        };
        if !swift.contains(&updater) {
            violations.push(format!("Swift {platform}: 缺少 updater 资产合同 {updater}"));
        }
    }
    for required in [
        r#"primary = "\(installer)-v\(version).deb""#,
        r#"updaterName = "\(updater)-v\(version).AppImage""#,
        r#"primary = "\(installer)-v\(version).dmg""#,
        r#"updaterName = "\(updater)-v\(version).app.tar.gz""#,
        r#"primary = "\(installer)-v\(version).exe""#,
    ] {
        if !swift.contains(required) {
            violations.push(format!("Swift: 缺少版本化资产构造 {required}"));
        }
    }
    for (line_index, line) in swift.lines().enumerate() {
        let trimmed = line.trim_start();
        if ["installer = ", "updater = ", "manifest = "]
            .iter()
            .any(|prefix| trimmed.starts_with(prefix))
        {
            reject_legacy_asset(
                &format!("Swift:{} 自定义资产字段", line_index + 1),
                trimmed,
                &mut violations,
            );
        }
    }

    for required in [
        "`citizenchain-node-LinuxARM-v${version}.deb`",
        "`citizenchain-node-LinuxAMD-v${version}.deb`",
        "`citizenchain-node-macOS-v${version}.dmg`",
        "`citizenchain-node-Windows-v${version}.exe`",
        "'citizenchain-node-latest-macOS.json'",
    ] {
        if !serve.contains(required) {
            violations.push(format!("CitizenServe: 缺少正式资产合同 {required}"));
        }
    }
    for (line_index, line) in serve.lines().enumerate() {
        let trimmed = line.trim_start();
        if trimmed.starts_with("asset: (version) =>")
            || trimmed.contains("? 'citizenchain-node-latest-")
        {
            reject_legacy_asset(
                &format!("CitizenServe:{} 自定义资产字段", line_index + 1),
                trimmed,
                &mut violations,
            );
        }
    }

    let golden_asset = "citizenchain-node-macOS-v1.2.3.dmg";
    let put_body: Value = serde_json::from_str(
        fixture["put_body_json"]
            .as_str()
            .expect("golden put_body_json 必须是字符串"),
    )
    .expect("golden put_body_json 必须是合法 JSON");
    let snapshot: Value = serde_json::from_str(
        fixture["snapshot_json"]
            .as_str()
            .expect("golden snapshot_json 必须是字符串"),
    )
    .expect("golden snapshot_json 必须是合法 JSON");
    let golden_values = [
        (
            "golden put_body_json.publication.asset_name",
            put_body["publication"]["asset_name"]
                .as_str()
                .expect("golden PUT 资产名必须是字符串"),
        ),
        (
            "golden snapshot_json.asset_name",
            snapshot["asset_name"]
                .as_str()
                .expect("golden snapshot 资产名必须是字符串"),
        ),
    ];
    for (label, value) in golden_values {
        if value != golden_asset {
            violations.push(format!("{label}: 期望 {golden_asset}，实际 {value}"));
        }
        reject_legacy_asset(label, value, &mut violations);
    }
    let golden_location = fixture["location"]
        .as_str()
        .expect("golden location 必须是字符串");
    let expected_location = format!(
        "https://github.com/VoyagerRhett/GMB/releases/download/\
citizenchain-node-macos-v1.2.3/{golden_asset}"
    );
    if golden_location != expected_location {
        violations.push(format!(
            "golden location: 期望 {expected_location}，实际 {golden_location}"
        ));
    }
    let golden_location_asset = golden_location
        .rsplit('/')
        .next()
        .expect("golden location 必须含资产路径段");
    reject_legacy_asset(
        "golden location 资产段",
        golden_location_asset,
        &mut violations,
    );

    assert!(
        violations.is_empty(),
        "CitizenChain 跨仓 Release 资产一致性守卫失败:\n{}",
        violations.join("\n")
    );
}

#[test]
fn qr_signing_protocol_has_no_second_registry_or_third_state() {
    let repo_root = repo_root();
    let mut violations = Vec::new();

    // 扫描根必须覆盖**全部**参与 QR/签名协议的端。漏一个端 = 守卫报绿而该端悄悄漂移:
    // 2026-08-06 的单字母键统一就因为这里缺了两个 `frontend/`,导致桌面矿工端
    // 「扫码识别账户」链路断掉而守卫毫无反应。新增任何端必须同步加进本列表。
    for root in [
        "citizenapp/lib",
        "citizenwallet/lib",
        "citizenchain/onchina/src",
        "citizenchain/onchina/frontend",
        "citizenchain/node/src",
        "citizenchain/node/frontend",
        "citizenchain/crates",
        "shared",
    ] {
        collect_files(&repo_root.join(root), &mut |path| {
            if should_scan(path) {
                scan_file(&repo_root, path, &mut violations);
            }
        });
    }

    assert!(
        violations.is_empty(),
        "QR 签名协议 guard 发现第二真源或第三状态残留:\n{}",
        violations.join("\n")
    );
}

/// 两个 React 工程的生成校验器必须逐字节相同。
#[test]
fn web_frontend_qr_modules_are_byte_identical() {
    let repo_root = repo_root();
    let node = repo_root.join("citizenchain/node/frontend/shared/qr/generated/qrBodies.g.ts");
    let onchina = repo_root.join("citizenchain/onchina/frontend/core/qr/generated/qrBodies.g.ts");

    let node_text =
        fs::read_to_string(&node).unwrap_or_else(|e| panic!("读取 {} 失败: {e}", node.display()));
    let onchina_text = fs::read_to_string(&onchina)
        .unwrap_or_else(|e| panic!("读取 {} 失败: {e}", onchina.display()));

    assert_eq!(
        node_text,
        onchina_text,
        "两个 React 前端的 QR body 生成校验器必须逐字节相同\n  {}\n  {}",
        node.display(),
        onchina.display()
    );
}

/// 生成器新增码型后，两个 React 业务适配器必须同时补齐类型映射和解析分支。
#[test]
fn web_frontend_qr_adapters_cover_all_registered_kinds() {
    let repo_root = repo_root();
    let kinds = qr_protocol::kinds().expect("读取统一 QrKind 注册表失败");

    for relative in [
        "citizenchain/node/frontend/shared/qr/citizenQr.ts",
        "citizenchain/onchina/frontend/core/citizenQr.ts",
    ] {
        let path = repo_root.join(relative);
        let text = fs::read_to_string(&path)
            .unwrap_or_else(|e| panic!("读取 {} 失败: {e}", path.display()));
        for kind in &kinds {
            assert!(
                text.contains(&format!("  {}:", kind.kind_key)),
                "{relative}: QrBodyByKind 缺少 {}",
                kind.kind_key
            );
            assert!(
                text.contains(&format!("case '{}':", kind.kind_key)),
                "{relative}: parseQrEnvelope 缺少 {}",
                kind.kind_key
            );
        }
    }
}

/// Flutter 产品不得绕过共享适配器直接依赖或导入 `mobile_scanner`。
#[test]
fn flutter_products_use_shared_scanner_adapter() {
    let repo_root = repo_root();
    let mut violations = Vec::new();

    for product in ["citizenapp", "citizenwallet"] {
        let pubspec = repo_root.join(product).join("pubspec.yaml");
        let text = fs::read_to_string(&pubspec)
            .unwrap_or_else(|e| panic!("读取 {} 失败: {e}", pubspec.display()));
        if product != "citizenwallet" && text
            .lines()
            .any(|line| line.trim_start().starts_with("mobile_scanner:"))
        {
            violations.push(format!(
                "{product}/pubspec.yaml: Flutter 产品必须依赖 {product}/packages/scanner-flutter,禁止直连 mobile_scanner"
            ));
        }

        collect_files(&repo_root.join(product).join("lib"), &mut |path| {
            if path.extension().and_then(|ext| ext.to_str()) != Some("dart") {
                return;
            }
            let text = fs::read_to_string(path)
                .unwrap_or_else(|e| panic!("读取 {} 失败: {e}", path.display()));
            if text.contains("package:mobile_scanner/mobile_scanner.dart")
                && !(product == "citizenwallet" && path.ends_with("lib/qr/scanner/mobile_scanner_backend.dart")) {
                let display = path.strip_prefix(&repo_root).unwrap_or(path).display();
                violations.push(format!(
                    "{display}: Flutter 产品禁止直接导入 mobile_scanner"
                ));
            }
        });
    }

    assert!(
        violations.is_empty(),
        "Flutter 扫码适配器守卫失败:\n{}",
        violations.join("\n")
    );
}

/// React 共享扫码器固定使用 jsQR + canvas，不得恢复浏览器原生检测分支。
#[test]
fn react_scanner_uses_only_jsqr_and_canvas() {
    let repo_root = repo_root();
    let scanner_root = repo_root.join("citizenchain/crates/scanner-react/src");
    let mut violations = Vec::new();
    let mut combined = String::new();

    collect_files(&scanner_root, &mut |path| {
        if !should_scan(path) {
            return;
        }
        let text = fs::read_to_string(path)
            .unwrap_or_else(|e| panic!("读取 {} 失败: {e}", path.display()));
        let display = path.strip_prefix(&repo_root).unwrap_or(path).display();
        if text.contains("BarcodeDetector") {
            violations.push(format!(
                "{display}: React 共享扫码器禁止恢复 BarcodeDetector"
            ));
        }
        combined.push_str(&text);
    });

    for required in ["getUserMedia", "drawImage", "getImageData", "jsQR"] {
        if !combined.contains(required) {
            violations.push(format!(
                "citizenchain/crates/scanner-react/src: 缺少统一 jsQR + canvas 路线关键调用 {required}"
            ));
        }
    }

    assert!(
        violations.is_empty(),
        "React 扫码技术路线守卫失败:\n{}",
        violations.join("\n")
    );
}

/// Node 与 OnChina 必须统一消费共享 React 扫码器，不得保留产品内设备实现。
#[test]
fn react_products_use_shared_scanner_adapter() {
    let repo_root = repo_root();
    let mut violations = Vec::new();

    for frontend in [
        "citizenchain/node/frontend",
        "citizenchain/onchina/frontend",
    ] {
        let package_json = repo_root.join(frontend).join("package.json");
        let manifest = fs::read_to_string(&package_json)
            .unwrap_or_else(|e| panic!("读取 {} 失败: {e}", package_json.display()));
        if !manifest.contains("\"@gmb/scanner-react\"") {
            violations.push(format!(
                "{frontend}/package.json: React 产品必须依赖 @gmb/scanner-react"
            ));
        }
        if manifest
            .lines()
            .any(|line| line.trim_start().starts_with("\"jsqr\":"))
        {
            violations.push(format!(
                "{frontend}/package.json: React 产品禁止直接依赖 jsqr"
            ));
        }
        let npmrc = repo_root.join(frontend).join(".npmrc");
        let npmrc_text = fs::read_to_string(&npmrc)
            .unwrap_or_else(|e| panic!("读取 {} 失败: {e}", npmrc.display()));
        if !npmrc_text
            .lines()
            .any(|line| line.trim() == "install-links=true")
        {
            violations.push(format!(
                "{frontend}/.npmrc: 本地共享扫码包必须使用 install-links=true 独立安装"
            ));
        }

        collect_files(&repo_root.join(frontend), &mut |path| {
            if !should_scan(path) {
                return;
            }
            let text = fs::read_to_string(path)
                .unwrap_or_else(|e| panic!("读取 {} 失败: {e}", path.display()));
            let display = path.strip_prefix(&repo_root).unwrap_or(path).display();
            for forbidden in ["BarcodeDetector", "from 'jsqr'", "from \"jsqr\""] {
                if text.contains(forbidden) {
                    violations.push(format!("{display}: React 产品扫码源码禁止恢复 {forbidden}"));
                }
            }
        });

        let old_scanner = repo_root
            .join(frontend)
            .join(if frontend.contains("/node/") {
                "shared/qr/cameraScanner.ts"
            } else {
                "utils/cameraScanner.ts"
            });
        if old_scanner.exists() {
            violations.push(format!(
                "{}: 产品内旧扫码设备实现必须删除",
                old_scanner
                    .strip_prefix(&repo_root)
                    .unwrap_or(&old_scanner)
                    .display()
            ));
        }

        let business_entries: &[&str] = if frontend.contains("/node/") {
            &["shared/qr/QrScanner.tsx"]
        } else {
            &[
                "core/CitizenSignaturePanel.tsx",
                "core/ScanAccountModal.tsx",
            ]
        };
        for entry in business_entries {
            let path = repo_root.join(frontend).join(entry);
            let text = fs::read_to_string(&path)
                .unwrap_or_else(|e| panic!("读取 {} 失败: {e}", path.display()));
            if !text.contains("from '@gmb/scanner-react'") {
                violations.push(format!(
                    "{frontend}/{entry}: React 扫码业务入口必须复用共享适配器"
                ));
            }
        }
    }

    assert!(
        violations.is_empty(),
        "React 产品共享扫码适配器守卫失败:\n{}",
        violations.join("\n")
    );
}

/// 每个移动端 CI 与每个节点端 CI 都必须真实验证共享扫码包。
#[test]
fn product_ci_runs_shared_scanner_gates() {
    let flow_root = tata_flow_root();
    let mut violations = Vec::new();

    for product in ["citizenapp", "citizenwallet"] {
        let workflow = format!("gmb/{product}/action.yml");
        let path = flow_root.join(&workflow);
        let text = fs::read_to_string(&path)
            .unwrap_or_else(|e| panic!("读取 {} 失败: {e}", path.display()));
        for required in [
            &format!("working-directory: {}", if product == "citizenwallet" { product.to_owned() } else { format!("{product}/packages/scanner-flutter") }),
            "flutter analyze",
            "flutter test",
        ] {
            if !text.contains(required) {
                violations.push(format!("{workflow}: 缺少 Flutter 共享扫码门禁 {required}"));
            }
        }
    }

    let workflow = "gmb/citizenchain-node/action.yml";
    let path = flow_root.join(workflow);
    let text =
        fs::read_to_string(&path).unwrap_or_else(|e| panic!("读取 {} 失败: {e}", path.display()));
    // 四个平台复用同一中央 Action；统一缓存指纹和共享适配器检查只维护一份真源。
    for required in [
        "**/package-lock.json",
        "npm --prefix citizenchain/crates/scanner-react ci",
        "npm --prefix citizenchain/crates/scanner-react run check",
        "npm --prefix citizenchain/crates/scanner-react test",
        "npm --prefix citizenchain/node/frontend ci",
        "npm --prefix citizenchain/node/frontend run build",
        "npm --prefix citizenchain/onchina/frontend ci",
        "npm --prefix citizenchain/onchina/frontend run build",
    ] {
        if !text.contains(required) {
            violations.push(format!(
                "{workflow}: 缺少 React 共享扫码或消费者门禁 {required}"
            ));
        }
    }

    assert!(
        violations.is_empty(),
        "共享扫码 CI 门禁失败:\n{}",
        violations.join("\n")
    );
}

/// Node 的 macOS 扫码必须由完整签名 App 承担，禁止恢复裸二进制启动。
#[test]
fn node_macos_camera_capability_is_bundled_and_verified() {
    let repo_root = repo_root();
    let flow_root = tata_flow_root();
    // 正式本机 App 必须用动态配置注入资源，再按同一命令顺序传入锁定编译参数。
    let tauri_build_start =
        "node frontend/node_modules/@tauri-apps/cli/tauri.js build --config \"$tauri_override\"";
    let tauri_build_locked = "--no-bundle --ci -- --locked";
    let tauri_bundle_start =
        "node frontend/node_modules/@tauri-apps/cli/tauri.js bundle --config \"$tauri_override\"";
    let tauri_bundle_app = "--bundles app --ci";
    let cases = [
        (
            "citizenchain/node/Entitlements.plist",
            &[
                "com.apple.security.device.camera",
                "com.apple.security.cs.allow-jit",
                "com.apple.security.cs.allow-unsigned-executable-memory",
                "<true/>",
            ][..],
        ),
        (
            "citizenchain/node/tauri.conf.json",
            &["\"entitlements\": \"Entitlements.plist\""][..],
        ),
        (
            "citizenchain/node/Info.plist",
            &["NSCameraUsageDescription"][..],
        ),
        (
            "citizenchain/scripts/run.sh",
            &[
                "APPLE_SIGNING_IDENTITY",
                "MACOS_SIGNING_IDENTITY='Developer ID Application: WEI CHENG (MHYMVRN6FC)'",
                "MACOS_TEAM_ID='MHYMVRN6FC'",
                "cargo build --locked --offline --release -p onchina",
                tauri_build_start,
                tauri_build_locked,
                tauri_bundle_start,
                tauri_bundle_app,
                "$TARGET_DIR/release/bundle/macos/citizenchain.app",
                "codesign --verify --deep --strict",
                "Authority=$MACOS_SIGNING_IDENTITY",
                "TeamIdentifier=$MACOS_TEAM_ID",
                "^Timestamp=",
                "com\\.apple\\.security\\.get-task-allow",
                "entitlement_key_path=",
                "plutil -extract \"$entitlement_key_path\"",
            ][..],
        ),
        (
            "citizenchain/scripts/prepare-toolchain.sh",
            &[
                "TATA_CONSOLE_CARGO_CONFIG",
                "CARGO_NET_OFFLINE",
                "CARGO_HOME/config.toml",
                "Cargo必须消费Worker准备的任务内锁定依赖并保持离线",
            ][..],
        ),
    ];

    let mut violations = Vec::new();
    for (relative, required_values) in cases {
        let path = repo_root.join(relative);
        let text = fs::read_to_string(&path)
            .unwrap_or_else(|e| panic!("读取 {} 失败: {e}", path.display()));
        for required in required_values {
            if !text.contains(required) {
                violations.push(format!("{relative}: 缺少 macOS 摄像头宿主门禁 {required}"));
            }
        }
    }

    let workflow = "gmb/citizenchain-node/action.yml";
    let workflow_text = fs::read_to_string(flow_root.join(workflow))
        .unwrap_or_else(|e| panic!("读取 {workflow} 失败: {e}"));
    for required in [
        "从最终 DMG 提取并验证 macOS App",
        "com.apple.security.device.camera",
        "com.apple.security.cs.allow-jit",
        "com.apple.security.cs.allow-unsigned-executable-memory",
        "entitlement_key_path=",
        "plutil -extract \"$entitlement_key_path\"",
    ] {
        if !workflow_text.contains(required) {
            violations.push(format!("{workflow}: 缺少 macOS 摄像头宿主门禁 {required}"));
        }
    }

    let run_script = fs::read_to_string(repo_root.join("citizenchain/scripts/run.sh"))
        .expect("读取 Node 启动脚本失败");
    for forbidden in ["-o /dev/stdout", "--stderr /dev/stderr"] {
        if run_script.contains(forbidden) {
            violations.push(format!(
                "citizenchain/scripts/run.sh: 禁止恢复会触发 LaunchServices -10810 的 {forbidden}"
            ));
        }
    }
    for forbidden in [
        "cargo tauri",
        "node frontend/node_modules/@tauri-apps/cli/tauri.js build --bundles app --ci",
        "target/debug/onchina",
        "$TARGET_DIR/debug/bundle/macos/citizenchain.app",
    ] {
        if run_script.contains(forbidden) {
            violations.push(format!(
                "citizenchain/scripts/run.sh: TataConsole 产品入口禁止旧命令或 Debug 残留 {forbidden}"
            ));
        }
    }
    let compile_position = run_script
        .find(tauri_build_start)
        .expect("上方必需值检查应已确认 Tauri 编译命令存在");
    let locked_position = run_script[compile_position..]
        .find(tauri_build_locked)
        .map(|position| compile_position + position)
        .expect("上方必需值检查应已确认 Tauri 锁定编译参数存在");
    let bundle_position = run_script
        .find(tauri_bundle_start)
        .expect("上方必需值检查应已确认 Tauri 封装命令存在");
    // 动态封装配置必须先于 App 参数，防止门禁只命中散落字符串却放过错误执行顺序。
    let bundle_app_position = run_script[bundle_position..]
        .find(tauri_bundle_app)
        .map(|position| bundle_position + position)
        .expect("上方必需值检查应已确认 Tauri 封装参数存在");
    if compile_position >= locked_position
        || locked_position >= bundle_position
        || bundle_position >= bundle_app_position
    {
        violations.push(
            "citizenchain/scripts/run.sh: Tauri 必须先完成 Release 编译再封装 macOS App"
                .to_string(),
        );
    }
    // 产品工作流已经集中到 TATA；本地脚本仍从 GMB 产品源码读取。
    for (relative, path) in [
        (
            "citizenchain/scripts/run.sh",
            repo_root.join("citizenchain/scripts/run.sh"),
        ),
        (workflow, flow_root.join(workflow)),
    ] {
        let text =
            fs::read_to_string(&path).unwrap_or_else(|e| panic!("读取 {relative} 失败: {e}"));
        if text.contains("plutil -extract \"$entitlement\"") {
            violations.push(format!(
                "{relative}: entitlement 点号未转义会被 plutil 误作多层 key path"
            ));
        }
    }

    assert!(
        violations.is_empty(),
        "Node macOS 摄像头宿主门禁失败:\n{}",
        violations.join("\n")
    );
}

fn repo_root() -> PathBuf {
    Path::new(env!("CARGO_MANIFEST_DIR"))
        .parent()
        .and_then(Path::parent)
        .and_then(Path::parent)
        .expect("qr-protocol 必须位于 citizenchain/crates/qr-protocol")
        .to_path_buf()
}

fn tata_flow_root() -> PathBuf {
    if let Some(path) = env::var_os("TATA_CONSOLE_FLOW_ROOT") {
        return PathBuf::from(path);
    }
    // 本机直接运行 cargo test 时从 GMB 与 TATA 的并列工作区解析；GitHub 始终显式注入环境变量。
    repo_root()
        .parent()
        .expect("GMB 必须位于三仓共同父目录")
        .join("TATA/tataconsole/flows")
}

fn collect_files(dir: &Path, visit: &mut impl FnMut(&Path)) {
    let Ok(entries) = fs::read_dir(dir) else {
        return;
    };
    for entry in entries.flatten() {
        let path = entry.path();
        if should_skip_path(&path) {
            continue;
        }
        if path.is_dir() {
            collect_files(&path, visit);
        } else {
            visit(&path);
        }
    }
}

fn should_skip_path(path: &Path) -> bool {
    let text = path.to_string_lossy();
    text.contains("/target/")
        || text.contains("/build/")
        || text.contains("/dist/")
        || text.contains("/.dart_tool/")
        || text.contains("/node_modules/")
        || text.contains("/generated/")
        || text.ends_with(".g.dart")
        || text.contains("/citizenchain/crates/qr-protocol/registry/")
        || text.contains("/citizenchain/crates/qr-protocol/tests/")
        || text.ends_with("/citizenchain/crates/qr-protocol/src/export.rs")
}

fn should_scan(path: &Path) -> bool {
    matches!(
        path.extension().and_then(|ext| ext.to_str()),
        Some("dart" | "rs" | "ts" | "tsx" | "js" | "jsx")
    )
}

fn scan_file(repo_root: &Path, path: &Path, violations: &mut Vec<String>) {
    let Ok(text) = fs::read_to_string(path) else {
        return;
    };
    let display = path
        .strip_prefix(repo_root)
        .unwrap_or(path)
        .to_string_lossy()
        .into_owned();

    for forbidden in [
        "gmb://account/",
        "legacyAddress",
        "GMB_ACCOUNT_RE",
        "void _requireExactKeys(",
        "function requireExactKeys(",
    ] {
        if text.contains(forbidden) {
            violations.push(format!(
                "{display}: 扫码生产代码禁止保留旧二维码格式或旧路由 {forbidden}"
            ));
        }
    }

    // 移动端只能消费 GeneratedQrActionRegistry,不得恢复手写 action/字段中文表。
    reject_contains(
        &text,
        &display,
        "actionLabels = {",
        "禁止恢复手写 actionLabels 中文表,必须消费 qr-protocol 生成产物",
        violations,
    );
    reject_contains(
        &text,
        &display,
        "actionKeyByCode = {",
        "禁止恢复手写 actionKeyByCode,必须消费 qr-protocol 生成产物",
        violations,
    );
    reject_contains(
        &text,
        &display,
        "actionLabelZhByKey = {",
        "禁止恢复手写 actionLabelZhByKey,必须消费 qr-protocol 生成产物",
        violations,
    );
    reject_contains(
        &text,
        &display,
        "fieldLabelZhByKey = {",
        "禁止恢复手写 fieldLabelZhByKey,必须消费 qr-protocol 生成产物",
        violations,
    );
    reject_contains(
        &text,
        &display,
        "_squareFieldLabels",
        "禁止在广场动作解码器恢复局部字段中文表",
        violations,
    );

    if text.contains("fieldLabelTextOrNull(String key)") && text.contains("return switch (key)") {
        violations.push(format!(
            "{display}: 禁止在 fieldLabelTextOrNull 中恢复手写字段 switch"
        ));
    }

    // OnChina 非链 action code 必须从 registry 读取,不得恢复 1/2/3 硬编码常量。
    for (symbol, value) in [
        ("ACTION_LOGIN", "1"),
        ("ACTION_CITIZEN_IDENTITY", "2"),
        ("ACTION_ONCHINA_ADMIN", "3"),
    ] {
        for (line_no, line) in text.lines().enumerate() {
            if line.contains(symbol)
                && !line.contains("_CODE")
                && (line.contains(&format!("= {value}"))
                    || line.contains(&format!(": u16 = {value}")))
            {
                violations.push(format!(
                    "{display}:{}: 禁止恢复 {symbol} = {value} 硬编码,必须从 qr-protocol registry 读取",
                    line_no + 1
                ));
            }
        }
    }
    reject_contains(
        &text,
        &display,
        "QR_ACTION_ONCHINA_ADMIN",
        "禁止恢复旧 QR_ACTION_ONCHINA_ADMIN 别名",
        violations,
    );
    reject_contains(
        &text,
        &display,
        "QR_ACTION_SQUARE_ACCOUNT",
        "禁止恢复旧 QR_ACTION_SQUARE_ACCOUNT 别名",
        violations,
    );

    // Runtime hash-only 允许列表来自 registry 生成集合,不得在端侧手写 action == A || action == B。
    if text.contains("isRuntimeHashOnly(int action) =>\n      action ==") {
        violations.push(format!(
            "{display}: 禁止恢复手写 hash-only action 列表,必须消费 GeneratedQrActionRegistry.isHashOnlyAction"
        ));
    }

    // 离线签名只允许 normal / reject 两态。
    if text.contains("enum SignDecisionStatus")
        && !text.contains("enum SignDecisionStatus { normal, reject }")
    {
        violations.push(format!(
            "{display}: SignDecisionStatus 只能是 normal/reject 两态"
        ));
    }
    for forbidden in ["decodeFailed", "partialRecognized", "warningButSignable"] {
        if text.contains(forbidden) {
            violations.push(format!(
                "{display}: 禁止恢复签名第三状态或可签名警告态 {forbidden}"
            ));
        }
    }

    // 用户确认页不得把不可理解内容兜底显示给用户后继续签名。
    for (line_no, line) in text.lines().enumerate() {
        if line.contains("载荷 ${") && line.contains("字节") {
            violations.push(format!(
                "{display}:{}: 禁止展示“载荷 N 字节”作为签名确认兜底",
                line_no + 1
            ));
        }
        let displays_numeric_action = (line.contains("动作 ${") || line.contains("动作：${"))
            && (line.contains("body.action")
                || line.contains("actionCode")
                || line.contains("action.toString")
                || line.contains("request.body.action"));
        if displays_numeric_action {
            violations.push(format!(
                "{display}:{}: 禁止展示动作数字作为签名确认兜底",
                line_no + 1
            ));
        }
    }
}

fn reject_contains(
    text: &str,
    display: &str,
    needle: &str,
    reason: &str,
    violations: &mut Vec<String>,
) {
    if text.contains(needle) {
        violations.push(format!("{display}: {reason}"));
    }
}
