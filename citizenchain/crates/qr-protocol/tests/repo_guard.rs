use std::fs;
use std::path::{Path, PathBuf};

fn repository_root() -> PathBuf {
    Path::new(env!("CARGO_MANIFEST_DIR"))
        .parent()
        .and_then(Path::parent)
        .and_then(Path::parent)
        .expect("qr-protocol必须位于citizenchain/crates/qr-protocol")
        .to_path_buf()
}

fn collect_files(root: &Path, output: &mut Vec<PathBuf>) {
    let ignored = [
        ".git",
        "node_modules",
        "target",
        "build",
        ".dart_tool",
        "vendor",
    ];
    let Ok(entries) = fs::read_dir(root) else {
        return;
    };
    for entry in entries.flatten() {
        let path = entry.path();
        if path
            .file_name()
            .and_then(|value| value.to_str())
            .is_some_and(|value| ignored.contains(&value))
        {
            continue;
        }
        if path.is_dir() {
            collect_files(&path, output);
        } else if path.is_file() {
            output.push(path);
        }
    }
}

fn source_file(path: &Path) -> bool {
    matches!(
        path.extension().and_then(|value| value.to_str()),
        Some(
            "c" | "cc"
                | "cpp"
                | "dart"
                | "h"
                | "hpp"
                | "java"
                | "js"
                | "json"
                | "kts"
                | "md"
                | "mjs"
                | "proto"
                | "py"
                | "rs"
                | "sh"
                | "sql"
                | "swift"
                | "toml"
                | "ts"
                | "tsx"
                | "yaml"
                | "yml"
        )
    )
}

#[test]
fn github_entry_only_runs_product_ci_and_release() {
    let root = repository_root();
    let workflow_root = root.join(".github/workflows");
    let entries = fs::read_dir(&workflow_root)
        .expect("读取GMB Workflow目录失败")
        .flatten()
        .filter(|entry| entry.path().is_file())
        .map(|entry| entry.file_name().to_string_lossy().to_string())
        .collect::<Vec<_>>();
    assert_eq!(entries, ["repository.yml"]);
    let workflow = fs::read_to_string(workflow_root.join("repository.yml"))
        .expect("读取GMB repository.yml失败");
    let forbidden = [
        ["TATA", "_CONSOLE"].concat(),
        ["Tata", "Console"].concat(),
        ["tata", "console"].concat(),
        [".tata", "-flow"].concat(),
        ["塔塔", "门禁"].concat(),
        [".publish", "'"].concat(),
    ];
    for value in forbidden {
        assert!(!workflow.contains(&value), "Workflow包含禁止边界：{value}");
    }
    assert!(workflow.contains("产品CI与Release"));
    assert!(workflow.contains("/scripts/ci/"));
    assert!(workflow.contains("/scripts/release/"));
}

#[test]
fn product_sources_do_not_depend_on_the_control_program() {
    let root = repository_root();
    let protected_runtime = root.join("citizenchain/runtime");
    let forbidden = [
        ["TATA", "_CONSOLE"].concat(),
        ["Tata", "Console"].concat(),
        ["tata", "console"].concat(),
        [".tata", "-flow"].concat(),
    ];
    let mut files = Vec::new();
    collect_files(&root, &mut files);
    let mut violations = Vec::new();
    for path in files {
        if path.starts_with(&protected_runtime) || !source_file(&path) {
            continue;
        }
        let Ok(source) = fs::read_to_string(&path) else {
            continue;
        };
        for value in &forbidden {
            if source.contains(value) {
                violations.push(format!("{}: {value}", path.display()));
            }
        }
    }
    assert!(
        violations.is_empty(),
        "产品源码仍依赖控制程序：\n{}",
        violations.join("\n")
    );
}

#[test]
fn product_flow_directories_have_one_final_name() {
    let root = repository_root();
    for product in [
        "citizenapp",
        "citizenwallet",
        "citizensdk",
        "citizenchain",
        "citizenserve",
        "citizenweb",
        "citizenchatserver",
    ] {
        assert!(
            root.join(product).join("scripts").is_dir(),
            "{product}缺少scripts目录"
        );
    }
    for forbidden in ["pipeline", "pipeline-support", "packaging"] {
        assert!(
            !root.join(forbidden).exists(),
            "仓库根保留禁止流程目录：{forbidden}"
        );
    }
}

#[test]
fn citizenchain_owns_one_exact_protoc_dependency_path() {
    let root = repository_root();
    let scripts = root.join("citizenchain/scripts");
    let contract: serde_json::Value = serde_json::from_str(
        &fs::read_to_string(scripts.join("dependencies.json"))
            .expect("读取CitizenChain依赖声明失败"),
    )
    .expect("CitizenChain依赖声明不是有效JSON");
    assert_eq!(contract["schema"], 1);
    assert_eq!(contract["tools"]["protoc"]["version"], "35.0");
    assert_eq!(
        contract["tools"]["protoc"]["source"],
        "https://github.com/protocolbuffers/protobuf/releases/tag/v35.0"
    );
    let archives = contract["tools"]["protoc"]["archives"]
        .as_object()
        .expect("CitizenChain protoc缺少四端归档");
    assert_eq!(archives.len(), 4);
    for platform in ["macos", "windows", "linux-arm", "linux-amd"] {
        let archive = archives
            .get(platform)
            .expect("CitizenChain protoc缺少平台归档");
        assert!(archive["url"]
            .as_str()
            .is_some_and(|value| value.starts_with(
                "https://github.com/protocolbuffers/protobuf/releases/download/v35.0/protoc-35.0-"
            )));
        assert!(archive["sha256"].as_str().is_some_and(
            |value| value.len() == 64 && value.bytes().all(|byte| byte.is_ascii_hexdigit())
        ));
    }

    let dependency_source = fs::read_to_string(scripts.join("dependencies.mjs"))
        .expect("读取CitizenChain依赖准备器失败");
    assert!(dependency_source.contains("libprotoc ${expectedVersion}"));
    let local_source = fs::read_to_string(scripts.join("prepare-toolchain.sh"))
        .expect("读取CitizenChain本机工具准备器失败");
    assert!(local_source.contains("dependencies.mjs\" prepare protoc"));
    assert!(local_source.contains("export PROTOC"));

    let mut files = Vec::new();
    collect_files(&scripts.join("node"), &mut files);
    collect_files(&scripts.join("runtime"), &mut files);
    let mut prepared_jobs = 0;
    let mut violations = Vec::new();
    for path in files {
        if path.extension().and_then(|value| value.to_str()) != Some("mjs")
            || path.file_name().and_then(|value| value.to_str()) == Some("test.mjs")
        {
            continue;
        }
        let source = fs::read_to_string(&path).expect("读取CitizenChain流程脚本失败");
        for forbidden in [
            ["protobuf", "compiler"].join("-"),
            ["command", "-v", "protoc"].join(" "),
        ] {
            if source.contains(forbidden.as_str()) {
                violations.push(format!("{}: {forbidden}", path.display()));
            }
        }
        if source.contains("dependencies.mjs prepare protoc") {
            prepared_jobs += 1;
            assert!(source.contains("RUNNER_TEMP/citizenchain-protoc"));
            assert!(source.contains("PROTOC=%s") || source.contains("PROTOC=$protoc_executable"));
        }
    }
    assert_eq!(
        prepared_jobs, 14,
        "CitizenChain protoc必须接入十个CI Job和四个Release Job"
    );
    assert!(
        violations.is_empty(),
        "CitizenChain仍保留系统protoc：\n{}",
        violations.join("\n")
    );
}

#[test]
fn runtime_upgrade_implementation_is_not_in_gmb() {
    let root = repository_root();
    let mut files = Vec::new();
    collect_files(&root, &mut files);
    for name in [
        "build_request.mjs",
        "fetch_wasm.mjs",
        "submit_request.mjs",
        "tx_common.mjs",
    ] {
        assert!(
            files
                .iter()
                .all(|path| path.file_name().and_then(|value| value.to_str()) != Some(name)),
            "GMB产品目录禁止保存Runtime开发升级实现：{name}"
        );
    }
}

#[test]
fn only_qr_v1_is_versioned() {
    let root = repository_root();
    let mut files = Vec::new();
    collect_files(&root, &mut files);
    let prefix = ["QR", "_V"].concat();
    let mut violations = Vec::new();
    for path in files {
        if !source_file(&path) {
            continue;
        }
        let Ok(source) = fs::read_to_string(&path) else {
            continue;
        };
        for token in
            source.split(|character: char| !character.is_ascii_alphanumeric() && character != '_')
        {
            if token.starts_with(&prefix) && token != "QR_V1" {
                violations.push(format!("{}: {token}", path.display()));
            }
        }
    }
    assert!(
        violations.is_empty(),
        "发现禁止协议版本：\n{}",
        violations.join("\n")
    );
}
