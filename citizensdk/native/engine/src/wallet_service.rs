//! CitizenChain 无根热钱包的生命周期协调。
//!
//! 这里逐项承接已经在 Dart `WalletService` 验证的公开事实、provisioning/cleanup
//! 所有权和失败恢复语义。秘密写入前必须先用 `WalletProfileStore` 的 CAS 取得精确
//! generation/owner 所有权；助记词、master mini-secret 和 child mini-secret 始终只在
//! Rust [`SecretBuffer`] 中生存，不能由本服务导出私钥。

use std::{
    collections::BTreeSet,
    sync::{Arc, Mutex, OnceLock},
    time::{SystemTime, UNIX_EPOCH},
};

use citizen_sdk_contracts::{
    citizen_ss58_address, parse_citizen_ss58_address,
    store::{EncryptedSecretBlobState, EncryptedSecretBlobStore, WalletProfileStore},
    AccountId32, ChainSigner, ColdWalletAccount, ContractErrorCode, ContractResult,
    DefaultAccountChangeAuthorization, SecretBuffer, SecretOwner, SecretRef, SecretVault,
    Sr25519PublicKey, Sr25519Signature, VaultAvailability, VaultGeneration, WalletAccount,
    WalletCleanupPlan, WalletOrigin, WalletProfile, WalletProvisioningPlan, WalletSignMode,
    WalletState, CITIZENCHAIN_GENESIS_HASH, CITIZEN_WALLET_INDEX,
    DEFAULT_ACCOUNT_CHANGE_NONCE_BYTES, MAX_COLD_WALLET_ACCOUNTS, MAX_EXTERNAL_SIGNING_TTL_SECONDS,
    MAX_WALLET_ACCOUNT_INDEX,
};
use futures::lock::Mutex as AsyncMutex;
use zeroize::Zeroizing;

use crate::{
    error::EngineError,
    wallet_derivation::{
        derive_wallet_accounts, generate_mnemonic, mint_owner, WalletEntropySource, WalletWordCount,
    },
};

const MAX_CAS_ATTEMPTS: usize = 32;
const MAX_CLEANUP_QUEUE: usize = 64;

static WALLET_OPERATION_GATE: OnceLock<AsyncMutex<()>> = OnceLock::new();
static PRIVATE_KEY_VIEW_LEASES: OnceLock<Mutex<BTreeSet<(u32, [u8; 16])>>> = OnceLock::new();

fn wallet_operation_gate() -> &'static AsyncMutex<()> {
    WALLET_OPERATION_GATE.get_or_init(|| AsyncMutex::new(()))
}

fn private_key_view_leases() -> &'static Mutex<BTreeSet<(u32, [u8; 16])>> {
    PRIVATE_KEY_VIEW_LEASES.get_or_init(|| Mutex::new(BTreeSet::new()))
}

/// 只包含公开账户归属；租约按持久 generation 隔离，跨实例不依赖 store Arc 地址。
pub(crate) struct WalletPrivateKeyView {
    account: WalletAccount,
    wallet_index: u32,
    generation: VaultGeneration,
}

impl Drop for WalletPrivateKeyView {
    fn drop(&mut self) {
        if let Ok(mut leases) = private_key_view_leases().lock() {
            leases.remove(&(self.wallet_index, *self.generation.as_bytes()));
        }
    }
}

fn require_no_private_key_view(state: &WalletState) -> Result<(), EngineError> {
    let leases = private_key_view_leases()
        .lock()
        .map_err(|_| EngineError::StatePoisoned)?;
    let active =
        |index: u32, generation: VaultGeneration| leases.contains(&(index, *generation.as_bytes()));
    if state
        .profile()
        .is_some_and(|profile| active(profile.wallet_index(), profile.generation()))
        || state
            .provisioning()
            .is_some_and(|plan| active(plan.wallet_index(), plan.generation()))
        || state
            .cleanup()
            .is_some_and(|plan| active(plan.wallet_index(), plan.generation()))
        || state
            .cleanup_queue()
            .iter()
            .any(|plan| active(plan.wallet_index(), plan.generation()))
    {
        return Err(conflict("钱包安全查看尚未清理，拒绝关联钱包变更"));
    }
    Ok(())
}

/// 可注入的毫秒时钟；测试不依赖墙钟，正式实现使用 Unix epoch。
pub trait WalletClock: Send + Sync {
    fn now_millis(&self) -> ContractResult<u64>;
}

#[derive(Clone, Copy, Debug, Default)]
pub struct SystemWalletClock;

impl WalletClock for SystemWalletClock {
    fn now_millis(&self) -> ContractResult<u64> {
        let millis = SystemTime::now()
            .duration_since(UNIX_EPOCH)
            .map_err(|_| {
                citizen_sdk_contracts::ContractError::new(
                    ContractErrorCode::Unavailable,
                    "系统时钟早于 Unix epoch",
                )
            })?
            .as_millis();
        u64::try_from(millis).map_err(|_| {
            citizen_sdk_contracts::ContractError::new(
                ContractErrorCode::Internal,
                "系统毫秒时间超出 u64",
            )
        })
    }
}

/// 尚未落盘的钱包创建会话。
///
/// 用户必须先通过受控绑定读取并确认备份助记词，随后再消费本对象提交钱包。会话析构前，
/// 助记词和可选 password 都由 Rust 可清零缓冲区持有；准备阶段不会写 profile、密文或 KEK。
pub struct PreparedWalletCreation {
    mnemonic: SecretBuffer,
    password: Zeroizing<String>,
}

impl PreparedWalletCreation {
    /// 只允许受控 Rust/C ABI 句柄在用户主动展示时短暂借用恢复词字节。
    /// 调用方若复制明文，就进入受信任宿主边界并负责及时清零。
    pub fn with_mnemonic<R>(&self, access: impl FnOnce(&[u8]) -> R) -> R {
        self.mnemonic.with_secret(access)
    }
}

impl core::fmt::Debug for PreparedWalletCreation {
    fn fmt(&self, formatter: &mut core::fmt::Formatter<'_>) -> core::fmt::Result {
        formatter
            .debug_struct("PreparedWalletCreation")
            .field("mnemonic", &"[REDACTED]")
            .field("password", &"[REDACTED]")
            .finish()
    }
}

struct PendingSecret {
    secret_ref: SecretRef,
    secret: SecretBuffer,
}

/// 产品无关的钱包服务；平台只需注入真实 vault 与两个强原子仓储。
#[derive(Clone)]
pub struct WalletService {
    signer: Arc<dyn ChainSigner>,
    vault: Arc<dyn SecretVault>,
    profiles: Arc<dyn WalletProfileStore>,
    encrypted_secrets: Arc<dyn EncryptedSecretBlobStore>,
    entropy: Arc<dyn WalletEntropySource>,
    clock: Arc<dyn WalletClock>,
}

/// 独立签名服务只读取 SDK 安全账户归属资料，不创建钱包、不执行备份或账户管理。
/// 与钱包共用操作门和 exact generation/owner 复核，秘密仅由金库解锁至可清零缓冲区。
#[derive(Clone)]
pub(crate) struct SigningService {
    signer: Arc<dyn ChainSigner>,
    vault: Arc<dyn SecretVault>,
    profiles: Arc<dyn WalletProfileStore>,
    encrypted_secrets: Arc<dyn EncryptedSecretBlobStore>,
}

impl SigningService {
    pub(crate) fn new(
        signer: Arc<dyn ChainSigner>,
        vault: Arc<dyn SecretVault>,
        profiles: Arc<dyn WalletProfileStore>,
        encrypted_secrets: Arc<dyn EncryptedSecretBlobStore>,
    ) -> Self {
        Self {
            signer,
            vault,
            profiles,
            encrypted_secrets,
        }
    }

    /// 使用指定本机账户进行 sr25519 签名；不存在任何私钥导出旁路。
    pub async fn sign(
        &self,
        account_id: AccountId32,
        message: Vec<u8>,
    ) -> Result<Sr25519Signature, EngineError> {
        self.sign_guarded(account_id, message, &|| Ok(())).await
    }

    /// QR 在认证前后复查有效期与取消；已经派发的金库 future 必须实际排空。
    pub(crate) async fn sign_guarded(
        &self,
        account_id: AccountId32,
        message: Vec<u8>,
        ensure_current: &(dyn Fn() -> Result<(), EngineError> + Send + Sync),
    ) -> Result<Sr25519Signature, EngineError> {
        let _guard = wallet_operation_gate().lock().await;
        ensure_current()?;
        require_secure_device(self.vault.as_ref()).await?;
        let (profile, account) = current_account(self.profiles.as_ref(), account_id, None).await?;
        let snapshot = self.encrypted_secrets.load(account.secret_ref()).await?;
        let envelope = snapshot.envelope().cloned().ok_or_else(|| {
            error(
                ContractErrorCode::AuthenticationRequired,
                "指定账户的设备密文不存在",
            )
        })?;
        ensure_current()?;
        let secret = self.vault.open(account.secret_ref(), envelope).await?;
        ensure_current()?;

        // 用户认证可能阻塞；解锁后再次核对 exact generation/owner，删除或重建不得越过签名。
        let (_, current) = current_account(
            self.profiles.as_ref(),
            account_id,
            Some((profile.generation(), account.secret_ref().owner())),
        )
        .await?;
        if current.secret_ref() != account.secret_ref() {
            return Err(conflict("签名账户 SecretRef 已改变"));
        }
        let public_key = self.signer.public_key(&secret).await?;
        if public_key.as_bytes() != account_id.as_bytes() {
            return Err(error(
                ContractErrorCode::Integrity,
                "设备密文与钱包 AccountId 不一致",
            ));
        }
        ensure_current()?;
        self.signer
            .sign(&secret, message)
            .await
            .map_err(EngineError::from)
    }
}

async fn require_secure_device(vault: &dyn SecretVault) -> Result<(), EngineError> {
    match vault.availability().await? {
        VaultAvailability::Available => Ok(()),
        VaultAvailability::NoStrongUserAuthentication => Err(error(
            ContractErrorCode::AuthenticationRequired,
            "设备没有可用的强用户认证",
        )),
        VaultAvailability::Unsupported => Err(error(
            ContractErrorCode::Unsupported,
            "当前设备不支持 CitizenSDK 系统金库",
        )),
        VaultAvailability::Unavailable => Err(error(
            ContractErrorCode::Unavailable,
            "当前设备系统金库暂不可用",
        )),
    }
}

async fn current_account(
    profiles: &dyn WalletProfileStore,
    account_id: AccountId32,
    expected: Option<(VaultGeneration, SecretOwner)>,
) -> Result<(WalletProfile, WalletAccount), EngineError> {
    let state = profiles.load().await?;
    let profile =
        stable_profile(&state).ok_or_else(|| error(ContractErrorCode::NotFound, "钱包不存在"))?;
    let account = profile
        .account_by_id(account_id)
        .cloned()
        .ok_or_else(|| error(ContractErrorCode::NotFound, "账户不存在"))?;
    if let Some((generation, owner)) = expected {
        if profile.generation() != generation || account.secret_ref().owner() != owner {
            return Err(conflict("签名账户 generation/owner 已改变"));
        }
    }
    Ok((profile, account))
}

impl WalletService {
    /// 仅内部查看替换同一宿主的带归属观察器金库；普通钱包/签名实例不受影响。
    pub(crate) fn with_private_key_view_vault(
        mut self,
        vault: Option<Arc<dyn SecretVault>>,
    ) -> Self {
        if let Some(vault) = vault {
            self.vault = vault;
        }
        self
    }

    /// 内部查看准备只读取稳定归属，不认证、不解密、不执行恢复或持久写入。
    pub(crate) async fn prepare_private_key_view(
        &self,
        account_id: AccountId32,
    ) -> Result<Arc<WalletPrivateKeyView>, EngineError> {
        let _guard = wallet_operation_gate().lock().await;
        let state = self.profiles.load().await?;
        if state.provisioning().is_some()
            || state.cleanup().is_some()
            || !state.cleanup_queue().is_empty()
        {
            return Err(conflict("钱包存在未完成操作，不能开始安全查看"));
        }
        let profile = state
            .profile()
            .ok_or_else(|| error(ContractErrorCode::NotFound, "钱包不存在"))?;
        let account = profile
            .account_by_id(account_id)
            .cloned()
            .ok_or_else(|| error(ContractErrorCode::NotFound, "账户不存在"))?;
        let mut leases = private_key_view_leases()
            .lock()
            .map_err(|_| EngineError::StatePoisoned)?;
        if !leases.insert((profile.wallet_index(), *profile.generation().as_bytes())) {
            return Err(conflict("钱包已有安全查看会话"));
        }
        Ok(Arc::new(WalletPrivateKeyView {
            account,
            wallet_index: profile.wallet_index(),
            generation: profile.generation(),
        }))
    }

    /// 仅 SDK 内部状态机调用；授权期间用 generation 租约保护，不持钱包门等待系统 UI。
    pub(crate) async fn reveal_private_key_view(
        &self,
        view: &WalletPrivateKeyView,
        active: impl Fn() -> Result<(), EngineError>,
        display: impl FnOnce(&[u8]) -> Result<(), EngineError>,
    ) -> Result<(), EngineError> {
        active()?;
        require_secure_device(self.vault.as_ref()).await?;
        let snapshot = self
            .encrypted_secrets
            .load(view.account.secret_ref())
            .await?;
        let envelope = snapshot.envelope().cloned().ok_or_else(|| {
            error(
                ContractErrorCode::AuthenticationRequired,
                "指定账户的设备密文不存在",
            )
        })?;
        // 尚未进入真实授权时可以停止；一旦 open 已派发，必须把它实际排空。
        active()?;
        let secret = self.vault.open(view.account.secret_ref(), envelope).await?;
        let _guard = wallet_operation_gate().lock().await;
        let (_, current) = current_account(
            self.profiles.as_ref(),
            view.account.account_id(),
            Some((view.generation, view.account.secret_ref().owner())),
        )
        .await?;
        if current.secret_ref() != view.account.secret_ref() {
            return Err(conflict("查看账户 SecretRef 已改变"));
        }
        if secret.with_secret(|bytes| bytes.len()) != 32 {
            return Err(error(
                ContractErrorCode::Integrity,
                "账户秘密长度不符合安全查看合同",
            ));
        }
        let public_key = self.signer.public_key(&secret).await?;
        if public_key.as_bytes() != view.account.account_id().as_bytes() {
            return Err(error(
                ContractErrorCode::Integrity,
                "设备密文与钱包 AccountId 不一致",
            ));
        }
        // 借用仅在同步内部显示调用期间有效；无秘密返回值，结束后 SecretBuffer 析构清零。
        secret.with_secret(display)
    }

    pub fn new(
        signer: Arc<dyn ChainSigner>,
        vault: Arc<dyn SecretVault>,
        profiles: Arc<dyn WalletProfileStore>,
        encrypted_secrets: Arc<dyn EncryptedSecretBlobStore>,
        entropy: Arc<dyn WalletEntropySource>,
        clock: Arc<dyn WalletClock>,
    ) -> Self {
        Self {
            signer,
            vault,
            profiles,
            encrypted_secrets,
            entropy,
            clock,
        }
    }

    /// 返回当前可见公开 profile；在途追加账户只暴露提交前的稳定 profile。
    pub async fn profile(&self) -> Result<Option<WalletProfile>, EngineError> {
        let _guard = wallet_operation_gate().lock().await;
        let state = self.profiles.load().await?;
        Ok(stable_profile(&state))
    }

    /// 返回稳定可见的钱包目录；在途热账户目标和内部 lifecycle 计划均不会进入公开投影。
    pub async fn state(&self) -> Result<WalletState, EngineError> {
        let _guard = wallet_operation_gate().lock().await;
        let state = self.profiles.load().await?;
        visible_wallet_state(&state)
    }

    /// 导入一个仅公钥冷账户。该路径只读写公开状态，不查询或调用设备金库。
    pub async fn import_cold_account(
        &self,
        account_id: AccountId32,
        name: &str,
    ) -> Result<ColdWalletAccount, EngineError> {
        let _guard = wallet_operation_gate().lock().await;
        self.import_cold_account_locked(account_id, name).await
    }

    /// SS58 导入先在合同层严格还原 AccountId，再进入与 AccountId 导入相同的唯一写路径。
    pub async fn import_cold_ss58_account(
        &self,
        ss58_address: &str,
        name: &str,
    ) -> Result<ColdWalletAccount, EngineError> {
        let account_id = parse_citizen_ss58_address(ss58_address)?;
        let _guard = wallet_operation_gate().lock().await;
        self.import_cold_account_locked(account_id, name).await
    }

    /// 公开重排入口：调用方必须基于同一 revision，且不得改变首项默认账户。
    ///
    /// 默认账户变更必须走原默认账户签名授权；这里在同一把钱包操作锁内完成
    /// revision 与首项检查，避免把普通排序伪装成默认账户切换。
    pub async fn reorder_accounts_without_default_change(
        &self,
        expected_revision: u64,
        ordered_account_ids: Vec<AccountId32>,
    ) -> Result<WalletState, EngineError> {
        let _guard = wallet_operation_gate().lock().await;
        let state = self.catalog_mutation_state().await?;
        if state.revision() != expected_revision {
            return Err(conflict("钱包目录 revision 已变化，请重新读取后重排"));
        }
        if ordered_account_ids.first().copied() != state.default_account_id() {
            return Err(error(
                ContractErrorCode::InvalidArgument,
                "普通重排不得改变第一项默认账户",
            ));
        }
        self.commit_catalog_state(
            &state,
            state.cold_accounts().to_vec(),
            ordered_account_ids,
            state.next_cold_wallet_index(),
        )
        .await
    }

    /// Freeze an SDK-owned default-account mutation before either hot or external signing.
    ///
    /// The snapshot binds the exact revision and complete account set. No app identity, CID,
    /// business action, or caller-provided signing message participates in this wallet primitive.
    pub async fn prepare_default_account_change(
        &self,
        expected_revision: u64,
        ordered_account_ids: Vec<AccountId32>,
        ttl_seconds: u64,
    ) -> Result<DefaultAccountChangeAuthorization, EngineError> {
        if ttl_seconds == 0 || ttl_seconds > MAX_EXTERNAL_SIGNING_TTL_SECONDS {
            return Err(error(
                ContractErrorCode::InvalidArgument,
                "默认账户授权期限必须位于 1..300 秒",
            ));
        }
        let _guard = wallet_operation_gate().lock().await;
        let state = self.catalog_mutation_state().await?;
        if state.revision() != expected_revision {
            return Err(conflict("钱包目录 revision 已变化，请重新发起默认账户变更"));
        }
        let current_default = state
            .default_account_id()
            .ok_or_else(|| error(ContractErrorCode::InvalidState, "空钱包不能变更默认账户"))?;
        let now = self.clock.now_millis()? / 1_000;
        if now == 0 {
            return Err(error(ContractErrorCode::Unavailable, "系统时钟不可用"));
        }
        let expires_at = now
            .checked_add(ttl_seconds)
            .filter(|value| *value <= i64::MAX as u64)
            .ok_or_else(|| error(ContractErrorCode::InvalidArgument, "默认账户授权期限溢出"))?;
        let mut nonce = [0_u8; DEFAULT_ACCOUNT_CHANGE_NONCE_BYTES];
        self.entropy.fill(&mut nonce)?;
        Ok(DefaultAccountChangeAuthorization::try_new(
            CITIZENCHAIN_GENESIS_HASH,
            expected_revision,
            current_default,
            state.ordered_account_ids().to_vec(),
            ordered_account_ids,
            expires_at,
            nonce,
        )?)
    }

    /// Verify the original default account's signature and atomically commit the frozen order.
    /// Invalid signatures never write; a valid but stale authorization fails its exact CAS checks.
    pub async fn commit_default_account_change(
        &self,
        authorization: &DefaultAccountChangeAuthorization,
        signature: Sr25519Signature,
    ) -> Result<WalletState, EngineError> {
        self.require_default_change_current(authorization)?;
        let intent = authorization.signing_intent()?;
        let message = intent.signing_message()?;
        let verified = self
            .signer
            .verify(
                Sr25519PublicKey::from_bytes(
                    authorization.current_default_account_id().into_bytes(),
                ),
                message,
                signature,
            )
            .await?;
        if !verified {
            return Err(error(
                ContractErrorCode::Integrity,
                "默认账户变更签名未通过原默认账户复核",
            ));
        }

        let _guard = wallet_operation_gate().lock().await;
        self.require_default_change_current(authorization)?;
        let state = self.catalog_mutation_state().await?;
        if state.revision() != authorization.expected_revision()
            || state.default_account_id() != Some(authorization.current_default_account_id())
            || state.ordered_account_ids() != authorization.before_account_ids()
        {
            return Err(conflict(
                "签名期间钱包 revision、原默认账户或账户闭集已经变化",
            ));
        }
        self.commit_catalog_state(
            &state,
            state.cold_accounts().to_vec(),
            authorization.ordered_account_ids().to_vec(),
            state.next_cold_wallet_index(),
        )
        .await
    }

    fn require_default_change_current(
        &self,
        authorization: &DefaultAccountChangeAuthorization,
    ) -> Result<(), EngineError> {
        let now = self.clock.now_millis()? / 1_000;
        if now == 0 || now >= authorization.expires_at() {
            return Err(error(ContractErrorCode::Timeout, "默认账户变更授权已过期"));
        }
        Ok(())
    }

    /// 冷账户改名只变更公开展示事实，不生成或访问任何秘密。
    pub async fn rename_cold_account(
        &self,
        account_id: AccountId32,
        name: &str,
    ) -> Result<ColdWalletAccount, EngineError> {
        let _guard = wallet_operation_gate().lock().await;
        let state = self.catalog_mutation_state().await?;
        let Some(position) = state
            .cold_accounts()
            .iter()
            .position(|account| account.account_id() == account_id)
        else {
            return Err(error(ContractErrorCode::NotFound, "冷账户不存在"));
        };
        let mut cold_accounts = state.cold_accounts().to_vec();
        let renamed = cold_accounts[position].try_with_name(name)?;
        cold_accounts[position] = renamed.clone();
        self.commit_catalog_state(
            &state,
            cold_accounts,
            state.ordered_account_ids().to_vec(),
            state.next_cold_wallet_index(),
        )
        .await?;
        Ok(renamed)
    }

    /// 删除冷账户只移除公开事实和全局顺序项；已分配 wallet index 永不复用。
    pub async fn delete_cold_account(&self, account_id: AccountId32) -> Result<(), EngineError> {
        let _guard = wallet_operation_gate().lock().await;
        let state = self.catalog_mutation_state().await?;
        let Some(position) = state
            .cold_accounts()
            .iter()
            .position(|account| account.account_id() == account_id)
        else {
            return Err(error(ContractErrorCode::NotFound, "冷账户不存在"));
        };
        let mut cold_accounts = state.cold_accounts().to_vec();
        cold_accounts.remove(position);
        let ordered = state
            .ordered_account_ids()
            .iter()
            .copied()
            .filter(|candidate| *candidate != account_id)
            .collect();
        self.commit_catalog_state(
            &state,
            cold_accounts,
            ordered,
            state.next_cold_wallet_index(),
        )
        .await?;
        Ok(())
    }

    /// 查询稳定账户的签名分流；未完成 provisioning 的热账户不会提前可见。
    pub async fn account_sign_mode(
        &self,
        account_id: AccountId32,
    ) -> Result<Option<WalletSignMode>, EngineError> {
        let _guard = wallet_operation_gate().lock().await;
        let state = self.profiles.load().await?;
        if stable_profile(&state)
            .as_ref()
            .is_some_and(|profile| profile.account_by_id(account_id).is_some())
        {
            Ok(Some(WalletSignMode::Hot))
        } else if state.cold_account_by_id(account_id).is_some() {
            Ok(Some(WalletSignMode::Cold))
        } else {
            Ok(None)
        }
    }

    /// 完整验证硬件密钥、每个密文和 child 公钥后才返回可用 profile。
    pub async fn usable_profile(&self) -> Result<Option<WalletProfile>, EngineError> {
        let _guard = wallet_operation_gate().lock().await;
        self.usable_profile_locked().await
    }

    /// 生成一次性助记词会话，但不持久化任何钱包事实。
    pub async fn prepare_create(
        &self,
        word_count: WalletWordCount,
        password: Zeroizing<String>,
    ) -> Result<PreparedWalletCreation, EngineError> {
        let _guard = wallet_operation_gate().lock().await;
        require_secure_device(self.vault.as_ref()).await?;
        let state = self.reconcile_locked().await?;
        if state.profile().is_some() {
            return Err(error(
                ContractErrorCode::InvalidState,
                "当前设备已经存在 CitizenChain 热钱包",
            ));
        }

        let mnemonic = generate_mnemonic(self.entropy.as_ref(), word_count)?;
        Ok(PreparedWalletCreation { mnemonic, password })
    }

    /// 用户已经确认备份后，消费一次性会话并提交钱包。
    ///
    /// 此方法之前的崩溃不会留下持久钱包；进入本方法前用户已经取得恢复词，因此提交后的
    /// 进程终止不会形成“设备有钱包但用户从未见过助记词”的不可恢复状态。
    pub async fn commit_create_after_backup(
        &self,
        prepared: PreparedWalletCreation,
    ) -> Result<WalletProfile, EngineError> {
        let _guard = wallet_operation_gate().lock().await;
        require_secure_device(self.vault.as_ref()).await?;
        let state = self.reconcile_locked().await?;
        if state.profile().is_some() {
            return Err(error(
                ContractErrorCode::InvalidState,
                "当前设备已经存在 CitizenChain 热钱包",
            ));
        }

        let (profile, pending, plan) = self
            .prepare_new_wallet(
                &prepared.mnemonic,
                &prepared.password,
                WalletOrigin::Created,
            )
            .await?;
        let expected_profile = profile.clone();
        let claimed = self
            .commit_state(
                &state,
                Some(profile),
                Some(plan.clone()),
                None,
                state.cleanup_queue().to_vec(),
            )
            .await?;
        if let Err(original) = self.finish_provisioning(&claimed, pending).await {
            self.rollback_provisioning(&plan).await?;
            return Err(original);
        }
        Ok(expected_profile)
    }

    pub async fn import(
        &self,
        mnemonic: &SecretBuffer,
        password: &str,
    ) -> Result<WalletProfile, EngineError> {
        let _guard = wallet_operation_gate().lock().await;
        require_secure_device(self.vault.as_ref()).await?;
        let state = self.reconcile_locked().await?;
        if state.profile().is_some() {
            return Err(error(
                ContractErrorCode::InvalidState,
                "当前设备已经存在 CitizenChain 热钱包",
            ));
        }
        let (profile, pending, plan) = self
            .prepare_new_wallet(mnemonic, password, WalletOrigin::Imported)
            .await?;
        let claimed = self
            .commit_state(
                &state,
                Some(profile),
                Some(plan.clone()),
                None,
                state.cleanup_queue().to_vec(),
            )
            .await?;
        if let Err(original) = self.finish_provisioning(&claimed, pending).await {
            self.rollback_provisioning(&plan).await?;
            return Err(original);
        }
        self.profiles
            .load()
            .await?
            .profile()
            .cloned()
            .ok_or_else(|| error(ContractErrorCode::Integrity, "导入钱包完成后 profile 缺失"))
    }

    /// 追加 `//index` 账户。账户按 index 排序追加，写后异常必须由公开事实回读收敛。
    pub async fn add_accounts(
        &self,
        mnemonic: &SecretBuffer,
        password: &str,
        indices: &[u32],
    ) -> Result<Vec<WalletAccount>, EngineError> {
        let _guard = wallet_operation_gate().lock().await;
        if indices.is_empty() {
            return Err(error(
                ContractErrorCode::InvalidArgument,
                "追加账户 index 列表不能为空",
            ));
        }
        require_secure_device(self.vault.as_ref()).await?;
        let state = self.reconcile_locked().await?;
        let profile = state
            .profile()
            .cloned()
            .ok_or_else(|| error(ContractErrorCode::NotFound, "钱包不存在"))?;

        let existing: BTreeSet<_> = profile
            .accounts()
            .iter()
            .map(WalletAccount::index)
            .collect();
        let mut unique = BTreeSet::new();
        for index in indices {
            if *index == 0
                || *index > MAX_WALLET_ACCOUNT_INDEX
                || !unique.insert(*index)
                || existing.contains(index)
            {
                return Err(error(
                    ContractErrorCode::InvalidArgument,
                    "追加账户 index 必须唯一、尚不存在且位于 1..1989",
                ));
            }
        }
        self.require_existing_profile_secrets(&profile).await?;

        // 助记词/password 必须先由账户0公钥反证属于当前钱包。
        let owner_check =
            derive_wallet_accounts(self.signer.clone(), mnemonic, password, &[0]).await?;
        let owner_public_key = owner_check
            .first()
            .ok_or_else(|| error(ContractErrorCode::Internal, "账户0归属派生结果缺失"))?
            .public_key();
        if owner_public_key.as_bytes() != profile.master_account_id().as_bytes() {
            return Err(error(
                ContractErrorCode::AuthenticationRequired,
                "助记词或 password 与当前钱包不符",
            ));
        }
        self.require_usable_account(&profile, profile.master_account_id())
            .await?;

        let generation = profile.generation();
        let mut forbidden: BTreeSet<[u8; 16]> = profile
            .accounts()
            .iter()
            .map(|account| *account.secret_ref().owner().as_bytes())
            .collect();
        forbidden.insert(*generation.as_bytes());
        let mut owners = Vec::with_capacity(unique.len());
        for _ in &unique {
            let owner = mint_owner(self.entropy.as_ref(), &forbidden)?;
            forbidden.insert(owner);
            owners.push(SecretOwner::from_bytes(owner));
        }
        let operation_id = mint_owner(self.entropy.as_ref(), &forbidden)?;
        let sorted_indices: Vec<_> = unique.into_iter().collect();
        let derived =
            derive_wallet_accounts(self.signer.clone(), mnemonic, password, &sorted_indices)
                .await?;
        let created_at = self.clock.now_millis()?;
        let mut added = Vec::with_capacity(derived.len());
        let mut pending = Vec::with_capacity(derived.len());
        for (derived, owner) in derived.into_iter().zip(owners) {
            let account_id = AccountId32::from_bytes(*derived.public_key().as_bytes());
            let secret_ref =
                SecretRef::account_mini_secret(CITIZEN_WALLET_INDEX, generation, owner, account_id);
            let account = WalletAccount::try_new(
                derived.index(),
                account_id,
                secret_ref,
                citizen_ss58_address(account_id),
                format!("账户{}", derived.index()),
                created_at,
            )?;
            added.push(account);
            pending.push(PendingSecret {
                secret_ref,
                secret: derived.into_secret(),
            });
        }
        let mut accounts = profile.accounts().to_vec();
        accounts.extend(added.iter().cloned());
        let target = WalletProfile::try_new(
            profile.wallet_index(),
            generation,
            profile.master_account_id(),
            profile.origin(),
            profile.created_at_millis(),
            profile.active_account_id(),
            accounts,
        )?;
        let plan = WalletProvisioningPlan::try_new(
            operation_id,
            CITIZEN_WALLET_INDEX,
            generation,
            Some(profile),
            added.iter().map(WalletAccount::secret_ref).collect(),
            false,
        )?;
        let claimed = self
            .commit_state(
                &state,
                Some(target),
                Some(plan.clone()),
                None,
                state.cleanup_queue().to_vec(),
            )
            .await?;
        if let Err(original) = self.finish_provisioning(&claimed, pending).await {
            self.rollback_provisioning(&plan).await?;
            return Err(original);
        }
        Ok(added)
    }

    pub async fn set_active_account(
        &self,
        account_id: AccountId32,
    ) -> Result<WalletProfile, EngineError> {
        let _guard = wallet_operation_gate().lock().await;
        let state = self.reconcile_locked().await?;
        let profile = state
            .profile()
            .ok_or_else(|| error(ContractErrorCode::NotFound, "钱包不存在"))?
            .try_with_active_account(account_id)?;
        let committed = self
            .commit_state(
                &state,
                Some(profile),
                None,
                None,
                state.cleanup_queue().to_vec(),
            )
            .await?;
        committed
            .profile()
            .cloned()
            .ok_or_else(|| error(ContractErrorCode::Integrity, "active profile 写入后缺失"))
    }

    pub async fn rename_account(
        &self,
        account_id: AccountId32,
        name: &str,
    ) -> Result<WalletProfile, EngineError> {
        let _guard = wallet_operation_gate().lock().await;
        let state = self.profiles.load().await?;
        require_no_private_key_view(&state)?;
        if state.provisioning().is_some()
            || state.cleanup().is_some()
            || !state.cleanup_queue().is_empty()
        {
            return Err(error(
                ContractErrorCode::InvalidState,
                "钱包仍有未完成的本机操作计划",
            ));
        }
        let profile = state
            .profile()
            .ok_or_else(|| error(ContractErrorCode::NotFound, "钱包不存在"))?
            .try_with_account_name(account_id, name)?;
        let committed = self
            .commit_state(&state, Some(profile), None, None, Vec::new())
            .await?;
        committed
            .profile()
            .cloned()
            .ok_or_else(|| error(ContractErrorCode::Integrity, "重命名写入后 profile 缺失"))
    }

    pub async fn delete_account(&self, account_id: AccountId32) -> Result<(), EngineError> {
        let _guard = wallet_operation_gate().lock().await;
        let state = self.reconcile_locked().await?;
        let profile = state
            .profile()
            .cloned()
            .ok_or_else(|| error(ContractErrorCode::NotFound, "钱包不存在"))?;
        let account = profile
            .account_by_id(account_id)
            .cloned()
            .ok_or_else(|| error(ContractErrorCode::NotFound, "账户不存在"))?;
        if account.index() == 0 {
            if profile.accounts().len() > 1 {
                return Err(error(
                    ContractErrorCode::InvalidState,
                    "账户0是钱包锚点，存在其它账户时不能单独删除",
                ));
            }
            return self.delete_wallet_locked(&state, &profile).await;
        }
        let (next_profile, removed) = profile.try_without_child_account(account_id)?;
        let operation_id = self.operation_id_for_profile(&profile)?;
        let cleanup = WalletCleanupPlan::try_new(
            operation_id,
            profile.wallet_index(),
            profile.generation(),
            vec![removed.secret_ref()],
            false,
        )?;
        let committed = self
            .commit_state(
                &state,
                Some(next_profile),
                None,
                Some(cleanup),
                state.cleanup_queue().to_vec(),
            )
            .await?;
        self.finish_active_cleanup(committed).await?;
        Ok(())
    }

    pub async fn delete_wallet(&self) -> Result<(), EngineError> {
        let _guard = wallet_operation_gate().lock().await;
        let state = self.reconcile_locked().await?;
        let profile = state
            .profile()
            .cloned()
            .ok_or_else(|| error(ContractErrorCode::NotFound, "钱包不存在"))?;
        self.delete_wallet_locked(&state, &profile).await
    }

    pub async fn reconcile_cleanup(&self) -> Result<(), EngineError> {
        let _guard = wallet_operation_gate().lock().await;
        self.reconcile_locked().await?;
        Ok(())
    }

    async fn prepare_new_wallet(
        &self,
        mnemonic: &SecretBuffer,
        password: &str,
        origin: WalletOrigin,
    ) -> Result<(WalletProfile, Vec<PendingSecret>, WalletProvisioningPlan), EngineError> {
        let generation_bytes = mint_owner(self.entropy.as_ref(), &BTreeSet::new())?;
        let generation = VaultGeneration::from_bytes(generation_bytes);
        let mut forbidden = BTreeSet::from([generation_bytes]);
        let owner_bytes = mint_owner(self.entropy.as_ref(), &forbidden)?;
        forbidden.insert(owner_bytes);
        let operation_id = mint_owner(self.entropy.as_ref(), &forbidden)?;
        let owner = SecretOwner::from_bytes(owner_bytes);
        let mut derived = derive_wallet_accounts(self.signer.clone(), mnemonic, password, &[0])
            .await?
            .into_iter();
        let derived = derived
            .next()
            .ok_or_else(|| error(ContractErrorCode::Internal, "账户0派生未返回结果"))?;
        let account_id = AccountId32::from_bytes(*derived.public_key().as_bytes());
        let secret_ref =
            SecretRef::account_mini_secret(CITIZEN_WALLET_INDEX, generation, owner, account_id);
        let created_at = self.clock.now_millis()?;
        let account = WalletAccount::try_new(
            0,
            account_id,
            secret_ref,
            citizen_ss58_address(account_id),
            "账户0",
            created_at,
        )?;
        let profile = WalletProfile::try_new(
            CITIZEN_WALLET_INDEX,
            generation,
            account_id,
            origin,
            created_at,
            account_id,
            vec![account],
        )?;
        let plan = WalletProvisioningPlan::try_new(
            operation_id,
            CITIZEN_WALLET_INDEX,
            generation,
            None,
            vec![secret_ref],
            true,
        )?;
        Ok((
            profile,
            vec![PendingSecret {
                secret_ref,
                secret: derived.into_secret(),
            }],
            plan,
        ))
    }

    async fn finish_provisioning(
        &self,
        claimed: &WalletState,
        pending: Vec<PendingSecret>,
    ) -> Result<(), EngineError> {
        let operation_id = *claimed
            .provisioning()
            .ok_or_else(|| error(ContractErrorCode::Integrity, "provisioning 计划缺失"))?
            .operation_id();
        for pending_secret in pending {
            self.persist_secret(operation_id, pending_secret).await?;
        }
        self.verify_provisioned(claimed).await?;
        let latest = self.profiles.load().await?;
        if latest.profile() != claimed.profile()
            || latest.provisioning() != claimed.provisioning()
            || latest.cleanup().is_some()
        {
            return Err(conflict("provisioning 完成前公开事实已改变"));
        }
        self.commit_state(
            &latest,
            latest.profile().cloned(),
            None,
            None,
            latest.cleanup_queue().to_vec(),
        )
        .await?;
        Ok(())
    }

    async fn persist_secret(
        &self,
        operation_id: [u8; 16],
        pending: PendingSecret,
    ) -> Result<(), EngineError> {
        let envelope = self
            .vault
            .seal(operation_id, pending.secret_ref, pending.secret)
            .await?;
        self.require_secret_write_ownership(operation_id, pending.secret_ref)
            .await?;
        let current = self.encrypted_secrets.load(pending.secret_ref).await?;
        match current.state() {
            EncryptedSecretBlobState::Vacant => {}
            EncryptedSecretBlobState::Sealed {
                provisioning_operation_id,
                envelope: existing,
            } if *provisioning_operation_id == operation_id && existing == &envelope => {
                return Ok(());
            }
            EncryptedSecretBlobState::Sealed { .. } => {
                return Err(conflict("秘密引用已经由不同 provisioning 或密文占用"));
            }
            EncryptedSecretBlobState::Tombstone { .. } => {
                return Err(conflict("秘密引用已经退休，late writer 不得复活密文"));
            }
        }
        let candidate = EncryptedSecretBlobState::Sealed {
            provisioning_operation_id: operation_id,
            envelope,
        };
        match self
            .encrypted_secrets
            .compare_and_swap(pending.secret_ref, current.revision(), candidate.clone())
            .await
        {
            Ok(snapshot) if snapshot.state() == &candidate => Ok(()),
            Ok(_) => Err(error(
                ContractErrorCode::Integrity,
                "设备密文写入后返回了不同事实",
            )),
            Err(write_error) => {
                let observed = self.encrypted_secrets.load(pending.secret_ref).await;
                if observed
                    .as_ref()
                    .is_ok_and(|snapshot| snapshot.state() == &candidate)
                {
                    Ok(())
                } else {
                    Err(EngineError::from(write_error))
                }
            }
        }
    }

    /// seal 可能触发生物识别并跨越其它进程的恢复动作；返回后必须重新核对公开所有权。
    /// 最后的跨存储竞态仍由 blob tombstone 与 vault generation retirement 双重封死。
    async fn require_secret_write_ownership(
        &self,
        operation_id: [u8; 16],
        secret_ref: SecretRef,
    ) -> Result<(), EngineError> {
        let state = self.profiles.load().await?;
        let provisioning_owns = state.provisioning().is_some_and(|plan| {
            plan.operation_id() == &operation_id && plan.secret_refs().contains(&secret_ref)
        });
        let committed_owns = state.provisioning().is_none()
            && state.profile().is_some_and(|profile| {
                profile
                    .accounts()
                    .iter()
                    .any(|account| account.secret_ref() == secret_ref)
            });
        if provisioning_owns || committed_owns {
            Ok(())
        } else {
            Err(conflict(
                "seal 返回后 provisioning/profile 已不再拥有该秘密引用",
            ))
        }
    }

    async fn verify_provisioned(&self, expected: &WalletState) -> Result<(), EngineError> {
        let persisted = self.profiles.load().await?;
        if persisted.profile() != expected.profile()
            || persisted.provisioning() != expected.provisioning()
            || persisted.cleanup() != expected.cleanup()
        {
            return Err(conflict("provisioning 写入后公开事实复核失败"));
        }
        let plan = persisted
            .provisioning()
            .ok_or_else(|| error(ContractErrorCode::Integrity, "provisioning 计划缺失"))?;
        if !self
            .vault
            .has_wallet_key(plan.wallet_index(), plan.generation())
            .await?
        {
            return Err(error(
                ContractErrorCode::Integrity,
                "钱包硬件密钥写入后复核失败",
            ));
        }
        for secret_ref in plan.secret_refs() {
            self.require_secret_matches(*secret_ref).await?;
        }
        Ok(())
    }

    async fn usable_profile_locked(&self) -> Result<Option<WalletProfile>, EngineError> {
        let state = self.profiles.load().await?;
        let profile = stable_profile(&state);
        let Some(profile) = profile else {
            return Ok(None);
        };
        if state.cleanup().is_some()
            || !self
                .vault
                .has_wallet_key(profile.wallet_index(), profile.generation())
                .await?
        {
            return Ok(None);
        }
        for account in profile.accounts() {
            if !self.secret_is_usable(account.secret_ref()).await? {
                return Ok(None);
            }
        }
        if self.profiles.load().await? != state {
            return Err(conflict("钱包完整核验期间公开事实发生变化"));
        }
        Ok(Some(profile))
    }

    async fn require_existing_profile_secrets(
        &self,
        profile: &WalletProfile,
    ) -> Result<(), EngineError> {
        if !self
            .vault
            .has_wallet_key(profile.wallet_index(), profile.generation())
            .await?
        {
            return Err(error(
                ContractErrorCode::AuthenticationRequired,
                "钱包硬件密钥不存在",
            ));
        }
        for account in profile.accounts() {
            let snapshot = self.encrypted_secrets.load(account.secret_ref()).await?;
            if snapshot.envelope().is_none() {
                return Err(error(
                    ContractErrorCode::Integrity,
                    "现有账户设备密文不存在",
                ));
            }
        }
        Ok(())
    }

    async fn require_usable_account(
        &self,
        profile: &WalletProfile,
        account_id: AccountId32,
    ) -> Result<(), EngineError> {
        let account = profile
            .account_by_id(account_id)
            .ok_or_else(|| error(ContractErrorCode::NotFound, "账户不存在"))?;
        self.require_secret_matches(account.secret_ref()).await
    }

    async fn require_secret_matches(&self, secret_ref: SecretRef) -> Result<(), EngineError> {
        let snapshot = self.encrypted_secrets.load(secret_ref).await?;
        let envelope = snapshot
            .envelope()
            .cloned()
            .ok_or_else(|| error(ContractErrorCode::NotFound, "账户设备密文不存在"))?;
        let secret = self.vault.open(secret_ref, envelope).await?;
        let public_key = self.signer.public_key(&secret).await?;
        if public_key.as_bytes() != secret_ref.account_id().as_bytes() {
            return Err(error(
                ContractErrorCode::Integrity,
                "设备密文与 AccountId 不一致",
            ));
        }
        Ok(())
    }

    /// `usable_profile` 只把“密文缺失/公钥错配”解释为不可用；仓储、认证和金库异常
    /// 必须原样上抛，不能伪装成设备上没有钱包。
    async fn secret_is_usable(&self, secret_ref: SecretRef) -> Result<bool, EngineError> {
        let snapshot = self.encrypted_secrets.load(secret_ref).await?;
        let Some(envelope) = snapshot.envelope().cloned() else {
            return Ok(false);
        };
        let secret = self.vault.open(secret_ref, envelope).await?;
        let public_key = self.signer.public_key(&secret).await?;
        Ok(public_key.as_bytes() == secret_ref.account_id().as_bytes())
    }

    async fn delete_wallet_locked(
        &self,
        state: &WalletState,
        profile: &WalletProfile,
    ) -> Result<(), EngineError> {
        let cleanup = WalletCleanupPlan::try_new(
            self.operation_id_for_profile(profile)?,
            profile.wallet_index(),
            profile.generation(),
            profile
                .accounts()
                .iter()
                .map(WalletAccount::secret_ref)
                .collect(),
            true,
        )?;
        let committed = self
            .commit_state(
                state,
                None,
                None,
                Some(cleanup),
                state.cleanup_queue().to_vec(),
            )
            .await?;
        self.finish_active_cleanup(committed).await?;
        Ok(())
    }

    fn operation_id_for_profile(&self, profile: &WalletProfile) -> Result<[u8; 16], EngineError> {
        let mut forbidden: BTreeSet<[u8; 16]> = profile
            .accounts()
            .iter()
            .map(|account| *account.secret_ref().owner().as_bytes())
            .collect();
        forbidden.insert(*profile.generation().as_bytes());
        mint_owner(self.entropy.as_ref(), &forbidden)
    }

    async fn reconcile_locked(&self) -> Result<WalletState, EngineError> {
        let mut state = self.profiles.load().await?;
        require_no_private_key_view(&state)?;
        // 与已验证 Dart 实现保持相同恢复优先级：先清理补偿队列，再完成活动 cleanup，
        // 最后才把崩溃遗留 provisioning 转成 cleanup。这样一个暂时失败的活动计划
        // 不会无限阻塞此前已经取得所有权的独立孤儿清理。
        for _ in 0..(MAX_CLEANUP_QUEUE + 3) {
            if let Some(next_cleanup) = state.cleanup_queue().first().cloned() {
                state = self.finish_queued_cleanup(next_cleanup).await?;
                continue;
            }
            if state.cleanup().is_some() {
                state = self.finish_active_cleanup(state).await?;
                continue;
            }
            if let Some(provisioning) = state.provisioning().cloned() {
                let cleanup = cleanup_from_provisioning(&provisioning)?;
                state = self
                    .commit_state(
                        &state,
                        provisioning.previous_profile().cloned(),
                        None,
                        Some(cleanup),
                        state.cleanup_queue().to_vec(),
                    )
                    .await?;
                continue;
            }
            return Ok(state);
        }
        Err(conflict("钱包待恢复计划数量超过合同上限"))
    }

    async fn rollback_provisioning(
        &self,
        expected: &WalletProvisioningPlan,
    ) -> Result<(), EngineError> {
        let cleanup = cleanup_from_provisioning(expected)?;
        for _ in 0..MAX_CAS_ATTEMPTS {
            let state = self.profiles.load().await?;
            if state.cleanup() == Some(&cleanup) {
                self.finish_active_cleanup(state).await?;
                return Ok(());
            }
            if state.cleanup_queue().contains(&cleanup) {
                self.finish_queued_cleanup(cleanup.clone()).await?;
                return Ok(());
            }
            if state.provisioning() == Some(expected) && state.cleanup().is_none() {
                let transitioned = self
                    .commit_state(
                        &state,
                        expected.previous_profile().cloned(),
                        None,
                        Some(cleanup.clone()),
                        state.cleanup_queue().to_vec(),
                    )
                    .await;
                match transitioned {
                    Ok(owned) => {
                        self.finish_active_cleanup(owned).await?;
                        return Ok(());
                    }
                    Err(error) if is_conflict(&error) => continue,
                    Err(error) => return Err(error),
                }
            }
            if self.cleanup_targets_absent(&cleanup).await? {
                return Ok(());
            }
            if state.cleanup_queue().len() >= MAX_CLEANUP_QUEUE {
                return Err(conflict("钱包 cleanup queue 已满"));
            }
            let mut queue = state.cleanup_queue().to_vec();
            queue.push(cleanup.clone());
            match self
                .commit_state(
                    &state,
                    state.profile().cloned(),
                    state.provisioning().cloned(),
                    state.cleanup().cloned(),
                    queue,
                )
                .await
            {
                Ok(_) => {
                    self.reconcile_locked().await?;
                    return Ok(());
                }
                Err(error) if is_conflict(&error) => continue,
                Err(error) => return Err(error),
            }
        }
        Err(conflict("无法取得 provisioning cleanup 所有权"))
    }

    async fn finish_active_cleanup(&self, state: WalletState) -> Result<WalletState, EngineError> {
        let expected = state
            .cleanup()
            .cloned()
            .ok_or_else(|| conflict("没有活动 cleanup 计划"))?;
        for _ in 0..MAX_CAS_ATTEMPTS {
            let latest = self.profiles.load().await?;
            if latest.cleanup().is_none() {
                if latest.cleanup_queue().contains(&expected) {
                    return self.finish_queued_cleanup(expected).await;
                }
                if self.cleanup_targets_absent(&expected).await? {
                    return Ok(latest);
                }
                return Err(conflict("cleanup 所有权消失但物理目标仍存在"));
            }
            if latest.cleanup() != Some(&expected) {
                return Err(conflict("活动 cleanup 已被不同计划替换"));
            }
            self.cleanup_targets(&expected).await?;
            match self
                .commit_state(
                    &latest,
                    latest.profile().cloned(),
                    latest.provisioning().cloned(),
                    None,
                    latest.cleanup_queue().to_vec(),
                )
                .await
            {
                Ok(committed) => return Ok(committed),
                Err(error) if is_conflict(&error) => continue,
                Err(error) => return Err(error),
            }
        }
        Err(conflict("cleanup 完成事实超过最大 CAS 重试次数"))
    }

    /// 完成队列中的 exact cleanup 而不夺走当前活动 cleanup 的所有权。
    ///
    /// 每次物理删除后只移除同一个计划；其它 profile/provisioning/cleanup 和队列顺序
    /// 原样保留。写后冲突时重新回读并幂等重放，绝不靠“最后一次看到的 revision”猜成功。
    async fn finish_queued_cleanup(
        &self,
        expected: WalletCleanupPlan,
    ) -> Result<WalletState, EngineError> {
        for _ in 0..MAX_CAS_ATTEMPTS {
            let latest = self.profiles.load().await?;
            let Some(position) = latest
                .cleanup_queue()
                .iter()
                .position(|plan| plan == &expected)
            else {
                if self.cleanup_targets_absent(&expected).await? {
                    return Ok(latest);
                }
                return Err(conflict("队列 cleanup 所有权消失但物理目标仍存在"));
            };
            self.cleanup_targets(&expected).await?;
            let mut queue = latest.cleanup_queue().to_vec();
            queue.remove(position);
            match self
                .commit_state(
                    &latest,
                    latest.profile().cloned(),
                    latest.provisioning().cloned(),
                    latest.cleanup().cloned(),
                    queue,
                )
                .await
            {
                Ok(committed) => return Ok(committed),
                Err(error) if is_conflict(&error) => continue,
                Err(error) => return Err(error),
            }
        }
        Err(conflict("队列 cleanup 完成事实超过最大 CAS 重试次数"))
    }

    async fn cleanup_targets(&self, cleanup: &WalletCleanupPlan) -> Result<(), EngineError> {
        let mut first_failure = None;
        for secret_ref in cleanup.secret_refs() {
            if let Err(error) = self
                .delete_encrypted_secret(*secret_ref, *cleanup.operation_id())
                .await
            {
                if first_failure.is_none() {
                    first_failure = Some(error);
                }
            }
        }
        if cleanup.delete_wallet_key() {
            let deletion = self
                .vault
                .delete_wallet_key(
                    *cleanup.operation_id(),
                    cleanup.wallet_index(),
                    cleanup.generation(),
                )
                .await;
            if let Err(error) = deletion {
                if first_failure.is_none() {
                    first_failure = Some(EngineError::from(error));
                }
            } else {
                match self
                    .vault
                    .has_wallet_key(cleanup.wallet_index(), cleanup.generation())
                    .await
                {
                    Ok(false) => {}
                    Ok(true) => {
                        if first_failure.is_none() {
                            first_failure = Some(error(
                                ContractErrorCode::Storage,
                                "钱包硬件密钥删除后仍存在",
                            ));
                        }
                    }
                    Err(error) => {
                        if first_failure.is_none() {
                            first_failure = Some(EngineError::from(error));
                        }
                    }
                }
            }
        }
        match first_failure {
            Some(error) => Err(error),
            None => Ok(()),
        }
    }

    async fn delete_encrypted_secret(
        &self,
        secret_ref: SecretRef,
        cleanup_operation_id: [u8; 16],
    ) -> Result<(), EngineError> {
        for _ in 0..MAX_CAS_ATTEMPTS {
            let snapshot = self.encrypted_secrets.load(secret_ref).await?;
            if snapshot.is_tombstone() {
                return Ok(());
            }
            let candidate = EncryptedSecretBlobState::Tombstone {
                cleanup_operation_id,
            };
            match self
                .encrypted_secrets
                .compare_and_swap(secret_ref, snapshot.revision(), candidate.clone())
                .await
            {
                Ok(observed) if observed.state() == &candidate || observed.is_tombstone() => {
                    return Ok(());
                }
                Ok(_) => {
                    return Err(error(
                        ContractErrorCode::Integrity,
                        "账户密文删除后返回了不同事实",
                    ));
                }
                Err(write_error) => {
                    let observed = self.encrypted_secrets.load(secret_ref).await;
                    if observed
                        .as_ref()
                        .is_ok_and(|snapshot| snapshot.is_tombstone())
                    {
                        return Ok(());
                    }
                    if write_error.code() != ContractErrorCode::Conflict {
                        return Err(EngineError::from(write_error));
                    }
                }
            }
        }
        Err(conflict("账户密文删除超过最大 CAS 重试次数"))
    }

    async fn cleanup_targets_absent(
        &self,
        cleanup: &WalletCleanupPlan,
    ) -> Result<bool, EngineError> {
        for secret_ref in cleanup.secret_refs() {
            if !self
                .encrypted_secrets
                .load(*secret_ref)
                .await?
                .is_tombstone()
            {
                return Ok(false);
            }
        }
        if cleanup.delete_wallet_key()
            && self
                .vault
                .has_wallet_key(cleanup.wallet_index(), cleanup.generation())
                .await?
        {
            return Ok(false);
        }
        Ok(true)
    }

    async fn commit_state(
        &self,
        current: &WalletState,
        profile: Option<WalletProfile>,
        provisioning: Option<WalletProvisioningPlan>,
        cleanup: Option<WalletCleanupPlan>,
        cleanup_queue: Vec<WalletCleanupPlan>,
    ) -> Result<WalletState, EngineError> {
        require_no_private_key_view(current)?;
        let next_revision = current
            .revision()
            .checked_add(1)
            .ok_or_else(|| error(ContractErrorCode::InvalidState, "钱包 revision 已耗尽"))?;
        let ordered_account_ids = order_after_hot_profile_change(current, profile.as_ref());
        let candidate = WalletState::try_from_catalog_parts(
            next_revision,
            profile,
            current.cold_accounts().to_vec(),
            ordered_account_ids,
            current.next_cold_wallet_index(),
            provisioning,
            cleanup,
            cleanup_queue,
        )?;
        self.commit_candidate(current, candidate).await
    }

    async fn import_cold_account_locked(
        &self,
        account_id: AccountId32,
        name: &str,
    ) -> Result<ColdWalletAccount, EngineError> {
        let state = self.catalog_mutation_state().await?;
        if state.account_sign_mode(account_id).is_some() {
            return Err(conflict("该 AccountId 已存在于热钱包或冷账户"));
        }
        if state.cold_accounts().len() >= MAX_COLD_WALLET_ACCOUNTS {
            return Err(error(
                ContractErrorCode::InvalidState,
                "冷账户数量已达到持久化合同上限",
            ));
        }
        let wallet_index = state.next_cold_wallet_index();
        let next_cold_wallet_index = wallet_index.checked_add(1).ok_or_else(|| {
            error(
                ContractErrorCode::InvalidState,
                "冷账户 wallet index 已耗尽",
            )
        })?;
        let account = ColdWalletAccount::try_new(
            wallet_index,
            account_id,
            citizen_ss58_address(account_id),
            name,
            self.clock.now_millis()?,
        )?;
        let mut cold_accounts = state.cold_accounts().to_vec();
        cold_accounts.push(account.clone());
        let mut ordered = state.ordered_account_ids().to_vec();
        ordered.push(account_id);
        self.commit_catalog_state(&state, cold_accounts, ordered, next_cold_wallet_index)
            .await?;
        Ok(account)
    }

    /// 冷账户/顺序写入不得为方便而重放热钱包 cleanup，因为那会触发金库调用。
    async fn catalog_mutation_state(&self) -> Result<WalletState, EngineError> {
        let state = self.profiles.load().await?;
        require_no_private_key_view(&state)?;
        if state.provisioning().is_some()
            || state.cleanup().is_some()
            || !state.cleanup_queue().is_empty()
        {
            return Err(error(
                ContractErrorCode::InvalidState,
                "钱包仍有未完成的热钱包操作计划",
            ));
        }
        Ok(state)
    }

    async fn commit_catalog_state(
        &self,
        current: &WalletState,
        cold_accounts: Vec<ColdWalletAccount>,
        ordered_account_ids: Vec<AccountId32>,
        next_cold_wallet_index: u32,
    ) -> Result<WalletState, EngineError> {
        require_no_private_key_view(current)?;
        let next_revision = current
            .revision()
            .checked_add(1)
            .ok_or_else(|| error(ContractErrorCode::InvalidState, "钱包 revision 已耗尽"))?;
        let candidate = WalletState::try_from_catalog_parts(
            next_revision,
            current.profile().cloned(),
            cold_accounts,
            ordered_account_ids,
            next_cold_wallet_index,
            None,
            None,
            Vec::new(),
        )?;
        self.commit_candidate(current, candidate).await
    }

    async fn commit_candidate(
        &self,
        current: &WalletState,
        candidate: WalletState,
    ) -> Result<WalletState, EngineError> {
        match self
            .profiles
            .compare_and_swap(current.revision(), candidate.clone())
            .await
        {
            Ok(observed) if observed == candidate => Ok(observed),
            Ok(_) => Err(error(
                ContractErrorCode::Integrity,
                "钱包 CAS 返回的公开事实与候选不一致",
            )),
            Err(write_error) => {
                let observed = self.profiles.load().await;
                if observed.as_ref().is_ok_and(|state| state == &candidate) {
                    Ok(candidate)
                } else {
                    Err(EngineError::from(write_error))
                }
            }
        }
    }
}

/// 热 profile 变化时保留所有仍存在账户的相对顺序，并把新增热账户稳定追加到末尾。
fn order_after_hot_profile_change(
    current: &WalletState,
    profile: Option<&WalletProfile>,
) -> Vec<AccountId32> {
    let valid_ids: BTreeSet<_> = profile
        .into_iter()
        .flat_map(WalletProfile::accounts)
        .map(WalletAccount::account_id)
        .chain(
            current
                .cold_accounts()
                .iter()
                .map(ColdWalletAccount::account_id),
        )
        .collect();
    let mut ordered: Vec<_> = current
        .ordered_account_ids()
        .iter()
        .copied()
        .filter(|account_id| valid_ids.contains(account_id))
        .collect();
    if let Some(profile) = profile {
        for account in profile.accounts() {
            if !ordered.contains(&account.account_id()) {
                ordered.push(account.account_id());
            }
        }
    }
    for account in current.cold_accounts() {
        if !ordered.contains(&account.account_id()) {
            ordered.push(account.account_id());
        }
    }
    ordered
}

/// 把持久状态投影成稳定公开事实；revision 只用于观察，不能拿该副本执行 CAS。
fn visible_wallet_state(state: &WalletState) -> Result<WalletState, EngineError> {
    let profile = stable_profile(state);
    let ordered_account_ids = order_after_hot_profile_change(state, profile.as_ref());
    WalletState::try_from_catalog_parts(
        state.revision(),
        profile,
        state.cold_accounts().to_vec(),
        ordered_account_ids,
        state.next_cold_wallet_index(),
        None,
        None,
        Vec::new(),
    )
    .map_err(EngineError::from)
}

fn cleanup_from_provisioning(
    provisioning: &WalletProvisioningPlan,
) -> Result<WalletCleanupPlan, EngineError> {
    WalletCleanupPlan::try_new(
        *provisioning.operation_id(),
        provisioning.wallet_index(),
        provisioning.generation(),
        provisioning.secret_refs().to_vec(),
        provisioning.delete_wallet_key_on_rollback(),
    )
    .map_err(EngineError::from)
}

/// Provisioning 期间只允许读取操作开始前已经提交的公开 profile。创建钱包的
/// `previous_profile` 明确为 `None`；不能再回退到尚未完成密文写入与复核的目标 profile。
fn stable_profile(state: &WalletState) -> Option<WalletProfile> {
    match state.provisioning() {
        Some(plan) => plan.previous_profile().cloned(),
        None => state.profile().cloned(),
    }
}

fn error(code: ContractErrorCode, message: impl Into<String>) -> EngineError {
    EngineError::contract(code, message)
}

fn conflict(message: impl Into<String>) -> EngineError {
    error(ContractErrorCode::Conflict, message)
}

fn is_conflict(error: &EngineError) -> bool {
    matches!(
        error,
        EngineError::Contract(contract) if contract.code() == ContractErrorCode::Conflict
    )
}
