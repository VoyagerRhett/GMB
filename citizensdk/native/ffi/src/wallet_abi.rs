//! Typed account, wallet and finalized-history projection for CitizenSDK ABI v1.
//!
//! Secret inputs are copied synchronously into Rust-owned zeroizing containers
//! before an asynchronous request is accepted. The only secret output is the
//! one-time recovery phrase owned by a prepared-wallet handle. The separate
//! private SDK bridge at the end of this file only lends an account mini-secret
//! synchronously to the SDK-owned native display; it is absent from public
//! headers, ordinary results and application callbacks.

use std::{
    collections::HashMap,
    future::Future,
    panic::{catch_unwind, AssertUnwindSafe},
    ptr,
    sync::{
        atomic::{AtomicU64, Ordering},
        Arc, Mutex, MutexGuard, OnceLock,
    },
};

use citizen_sdk_contracts::{
    AccountId32, ExecutionConclusion, ExtrinsicWatchEvent, FinalizedAccountBalance,
    FinalizedTransferRecord, HistoryTransactionStatus, SecretBuffer, TransactionHistoryRecord,
    TransactionHistoryState, WalletAccount, WalletOrigin, WalletProfile,
};
#[cfg(feature = "chain")]
use citizen_sdk_engine::BestFeeSnapshot;
use citizen_sdk_engine::{
    EngineError, PreparedWalletCreation, WalletTransferCancellation, WalletTransferObserver,
    WalletTransferResolution, WalletTransferWatchResult, WalletTransferWatchStage,
    WalletTransferWatchUpdate, WalletWordCount,
};
use futures_util::FutureExt;
use zeroize::Zeroizing;

use crate::{
    abi::*,
    accept_and_write, accept_and_write_watch, block_to_abi, copy_to_host, copy_view,
    error::{FfiError, FfiResult},
    execution_to_abi, ffi_status, handles,
    ownership::{self, ResultPayload},
    read_versioned,
    requests::RequestCancellation,
    require_output,
    runtime::NativeRuntime,
    validate_output_versioned, wrong_result, MAX_ABI_INPUT_BYTES,
};

const MAX_WALLET_SECRET_INPUT_BYTES: usize = 1024;
const MAX_WALLET_NAME_BYTES: usize = 1024;
const MAX_TRANSFER_REMARK_BYTES: usize = citizen_sdk_contracts::MAX_TRANSFER_REMARK_BYTES;
const MAX_ACCOUNT_BATCH: usize = citizen_sdk_contracts::MAX_WALLET_ACCOUNT_INDEX as usize + 1;

/// 仅 SDK 构建时生成的私有头声明此布局；禁止加入公开 ABI 类型和业务绑定。
#[repr(C)]
#[derive(Clone, Copy)]
pub(crate) struct CitizenSdkInternalPrivateKeyViewV1 {
    pub struct_size: u32,
    pub abi_version: u32,
    pub context: *mut std::ffi::c_void,
    pub display:
        Option<unsafe extern "C" fn(*mut std::ffi::c_void, u64, CitizenSdkBytesView) -> i32>,
    pub settled: Option<unsafe extern "C" fn(*mut std::ffi::c_void, u64, i32)>,
    pub authorizing: Option<unsafe extern "C" fn(*mut std::ffi::c_void, u64, u64) -> i32>,
}

impl CitizenSdkInternalPrivateKeyViewV1 {
    fn authorize(&self, view_id: u64, host_operation_id: u64) -> i32 {
        // SAFETY: open 完整验证此 SDK 私有表，阶段租约保证 context 直到 auth 排空都有效。
        unsafe {
            (self.authorizing.expect("validated authorizing"))(
                self.context,
                view_id,
                host_operation_id,
            )
        }
    }
}

// SAFETY: 私有 SDK 平台桥接保证 context 和代码直到唯一最终 request 完成均有效；
// display 是线程安全的同步复制，settled 只派发无秘密状态，二者不等待 UI 线程。
unsafe impl Send for CitizenSdkInternalPrivateKeyViewV1 {}
unsafe impl Sync for CitizenSdkInternalPrivateKeyViewV1 {}

struct PrivateKeyViewSlot {
    view_id: u64,
    request_id: CitizenSdkRequestId,
    runtime: Arc<NativeRuntime>,
    core: Arc<citizen_sdk_engine::engine::InternalPrivateKeyView>,
    callbacks: CitizenSdkInternalPrivateKeyViewV1,
}

static NEXT_PRIVATE_KEY_VIEW: AtomicU64 = AtomicU64::new(1);
static PRIVATE_KEY_VIEWS: OnceLock<Mutex<HashMap<u64, Arc<PrivateKeyViewSlot>>>> = OnceLock::new();

#[cfg(test)]
mod private_key_view_tests {
    use super::*;

    #[test]
    fn private_table_has_exact_layout_and_rejects_invalid_inputs_without_admission() {
        use std::mem::{offset_of, size_of};
        if size_of::<usize>() == 8 {
            assert_eq!(size_of::<CitizenSdkInternalPrivateKeyViewV1>(), 40);
            assert_eq!(
                offset_of!(CitizenSdkInternalPrivateKeyViewV1, struct_size),
                0
            );
            assert_eq!(
                offset_of!(CitizenSdkInternalPrivateKeyViewV1, abi_version),
                4
            );
            assert_eq!(offset_of!(CitizenSdkInternalPrivateKeyViewV1, context), 8);
            assert_eq!(offset_of!(CitizenSdkInternalPrivateKeyViewV1, display), 16);
            assert_eq!(offset_of!(CitizenSdkInternalPrivateKeyViewV1, settled), 24);
            assert_eq!(
                offset_of!(CitizenSdkInternalPrivateKeyViewV1, authorizing),
                32
            );
        }
        let mut view_id = 91;
        let mut request_id = 92;
        let mut table = CitizenSdkInternalPrivateKeyViewV1 {
            struct_size: 8,
            abi_version: 1,
            context: ptr::null_mut(),
            display: None,
            settled: None,
            authorizing: None,
        };
        let account = CitizenSdkAccountId { bytes: [0; 32] };
        let invalid = if cfg!(feature = "wallet") {
            CitizenSdkErrorCode::InvalidArgument
        } else {
            CitizenSdkErrorCode::Unsupported
        } as i32;
        unsafe {
            assert_eq!(
                citizensdk_internal_private_key_view_open(
                    0,
                    ptr::null(),
                    ptr::null(),
                    &mut view_id,
                    &mut request_id
                ),
                invalid
            );
            assert_eq!(
                citizensdk_internal_private_key_view_open(
                    0,
                    &account,
                    &table,
                    &mut view_id,
                    &mut request_id
                ),
                invalid
            );
            table.struct_size = size_of::<CitizenSdkInternalPrivateKeyViewV1>() as u32;
            table.abi_version = 2;
            assert_eq!(
                citizensdk_internal_private_key_view_open(
                    0,
                    &account,
                    &table,
                    &mut view_id,
                    &mut request_id
                ),
                CitizenSdkErrorCode::Unsupported as i32
            );
            table.abi_version = 1;
            assert_eq!(
                citizensdk_internal_private_key_view_open(
                    0,
                    &account,
                    &table,
                    &mut view_id,
                    &mut request_id
                ),
                invalid
            );
            assert_eq!(
                citizensdk_internal_private_key_view_open(
                    0,
                    &account,
                    &table,
                    ptr::null_mut(),
                    &mut request_id
                ),
                invalid
            );
        }
        assert_eq!((view_id, request_id), (91, 92));
        if !cfg!(feature = "wallet") {
            unsafe {
                assert_eq!(
                    citizensdk_internal_private_key_view_reveal(0, 0),
                    CitizenSdkErrorCode::Unsupported as i32
                );
                assert_eq!(
                    citizensdk_internal_private_key_view_cancel(0, 0),
                    CitizenSdkErrorCode::Unsupported as i32
                );
                assert_eq!(
                    citizensdk_internal_private_key_view_finish(0, 0),
                    CitizenSdkErrorCode::Unsupported as i32
                );
            }
        }
    }
}

fn private_key_views() -> &'static Mutex<HashMap<u64, Arc<PrivateKeyViewSlot>>> {
    PRIVATE_KEY_VIEWS.get_or_init(|| Mutex::new(HashMap::new()))
}

fn module_unsupported(module: &str) -> FfiError {
    FfiError::new(
        CitizenSdkErrorCode::Unsupported,
        format!("{module} module is not compiled"),
    )
}

fn private_key_view_slot(
    handle: CitizenSdkHandle,
    view_id: u64,
) -> FfiResult<Arc<PrivateKeyViewSlot>> {
    handles::get(handle)?;
    private_key_views()
        .lock()
        .map_err(|_| FfiError::internal("安全查看注册表已损坏"))?
        .get(&view_id)
        .filter(|slot| slot.runtime.handle() == handle)
        .cloned()
        .ok_or_else(|| {
            FfiError::new(
                CitizenSdkErrorCode::NotFound,
                "查看不属于此 SDK 实例或已结束",
            )
        })
}

fn private_key_view_error(code: CitizenSdkErrorCode) -> EngineError {
    if code == CitizenSdkErrorCode::Cancelled {
        EngineError::Cancelled
    } else {
        crate::host_providers::host_error(code, "SDK 内部安全查看阶段失败").into()
    }
}

/// 所有回调都在注册表和 Core 通知锁之外执行；通知本身算在生命周期排空中。
fn pump_private_key_view(slot: &Arc<PrivateKeyViewSlot>) -> FfiResult<()> {
    if let Some(outcome) = slot.core.take_notification()? {
        let code = outcome.map_or_else(
            |error| FfiError::from(error).code,
            |_| CitizenSdkErrorCode::Ok,
        );
        // SAFETY: open 已验证函数存在；Core notifying 租约阻止反调 finish 提前释放 context。
        unsafe {
            (slot.callbacks.settled.expect("validated settled"))(
                slot.callbacks.context,
                slot.view_id,
                code as i32,
            )
        };
        slot.core.finish_notification()?;
    }
    if let Some(outcome) = slot.core.take_completion()? {
        private_key_views()
            .lock()
            .map_err(|_| FfiError::internal("安全查看注册表已损坏"))?
            .remove(&slot.view_id);
        slot.runtime.complete_request(
            slot.request_id,
            outcome
                .map(|()| ResultPayload::Empty)
                .map_err(FfiError::from),
        );
    }
    Ok(())
}

fn enqueue_private_key_view(slot: &Arc<PrivateKeyViewSlot>) -> FfiResult<()> {
    let job = Arc::clone(slot);
    crate::requests::execute_private_view(move || {
        // 捕获整个阶段的 Rust panic，不打印秘密或 panic payload；授权 future 不做取消竞速。
        let outcome = catch_unwind(AssertUnwindSafe(|| {
            job.runtime
                .drive(job.core.run_work(|bytes| {
                    // SAFETY: Core 已复核账户/代际/公钥/取消状态，bytes 仅在本次同步调用内有效。
                    let code = unsafe {
                        (job.callbacks.display.expect("validated display"))(
                            job.callbacks.context,
                            job.view_id,
                            CitizenSdkBytesView {
                                data: bytes.as_ptr(),
                                len: bytes.len() as u64,
                            },
                        )
                    };
                    match crate::host_providers::decode_host_error_code(code) {
                        Ok(CitizenSdkErrorCode::Ok) => Ok(()),
                        Ok(code) => Err(private_key_view_error(code)),
                        Err(_) => Err(private_key_view_error(CitizenSdkErrorCode::Internal)),
                    }
                }))
                .map_err(|error| private_key_view_error(error.code))?
        }))
        .unwrap_or_else(|_| Err(private_key_view_error(CitizenSdkErrorCode::Panic)));
        if let Err(error) = outcome {
            let _ = job.core.fail(error);
        }
        // working 仍为真时先发阶段通知，settled 内 finish 也不能提前结束此作业。
        let _ = pump_private_key_view(&job);
        let _ = job.core.release_work();
        if matches!(job.core.reserve_work(), Ok(true)) {
            if let Err(error) = enqueue_private_key_view(&job) {
                let _ = job.core.fail(private_key_view_error(error.code));
                let _ = job.core.release_work();
            }
        }
        let _ = pump_private_key_view(&job);
    })
}

/// # Safety
/// 仅 SDK 自有平台桥接调用；表和输出必须有效，context 必须存续到唯一最终 request。
#[no_mangle]
pub(crate) unsafe extern "C" fn citizensdk_internal_private_key_view_open(
    handle: CitizenSdkHandle,
    account_id: *const CitizenSdkAccountId,
    view: *const CitizenSdkInternalPrivateKeyViewV1,
    out_view_id: *mut u64,
    out_request_id: *mut CitizenSdkRequestId,
) -> i32 {
    ffi_status(|| {
        if !cfg!(feature = "wallet") {
            return Err(module_unsupported("wallet"));
        }
        require_output(out_view_id, "view id")?;
        require_output(out_request_id, "request id")?;
        if account_id.is_null() {
            return Err(FfiError::invalid("account_id is null"));
        }
        let callbacks = read_versioned(view, "internal private-key view")?;
        if callbacks.context.is_null()
            || callbacks.display.is_none()
            || callbacks.settled.is_none()
            || callbacks.authorizing.is_none()
        {
            return Err(FfiError::invalid(
                "安全查看必须由 SDK 自有显示上下文和完整回调承载",
            ));
        }
        let runtime = handles::get(handle)?;
        let view_id = NEXT_PRIVATE_KEY_VIEW
            .fetch_update(Ordering::SeqCst, Ordering::SeqCst, |value| {
                value.checked_add(1).filter(|next| *next != 0)
            })
            .map_err(|_| FfiError::internal("安全查看编号已耗尽"))?;
        let private_key_view_vault =
            runtime.private_key_view_vault(Arc::new(move |operation_id| {
                let status = callbacks.authorize(view_id, operation_id);
                if status != CitizenSdkErrorCode::Ok as i32 {
                    // 在实际 unwrap 派发前保留查看的精确取消语义；普通金库仍独立映射认证取消10。
                    if let Ok(slot) = private_key_view_slot(handle, view_id) {
                        let code = crate::host_providers::decode_host_error_code(status)
                            .unwrap_or(CitizenSdkErrorCode::Internal);
                        let _ = slot.core.fail(private_key_view_error(code));
                    }
                }
                status
            }));
        let core = runtime.engine().internal_private_key_view(
            AccountId32::from_bytes(ptr::read(account_id).bytes),
            private_key_view_vault,
        )?;
        let (request_id, _) = runtime.begin_request(false)?;
        let slot = Arc::new(PrivateKeyViewSlot {
            view_id,
            request_id,
            runtime,
            core,
            callbacks,
        });
        let accepted = (|| {
            private_key_views()
                .lock()
                .map_err(|_| FfiError::internal("安全查看注册表已损坏"))?
                .insert(view_id, Arc::clone(&slot));
            if !slot.core.reserve_work()? {
                return Err(FfiError::internal("安全查看准备未登记"));
            }
            enqueue_private_key_view(&slot)
        })();
        if let Err(error) = accepted {
            if let Ok(mut registry) = private_key_views().lock() {
                registry.remove(&view_id);
            }
            slot.runtime.reject_request(request_id);
            return Err(error);
        }
        // 已接受阶段可以先于此处完成；原生必须按 context/view_id 处理早到通知。
        ptr::write(out_view_id, view_id);
        ptr::write(out_request_id, request_id);
        Ok(())
    })
}

/// # Safety
/// 只能由 SDK 自有确认操作调用；成功只代表登记，不表示授权或显示已完成。
#[no_mangle]
pub(crate) unsafe extern "C" fn citizensdk_internal_private_key_view_reveal(
    handle: CitizenSdkHandle,
    view_id: u64,
) -> i32 {
    ffi_status(|| {
        if !cfg!(feature = "wallet") {
            return Err(module_unsupported("wallet"));
        }
        let slot = private_key_view_slot(handle, view_id)?;
        slot.core.confirm()?;
        if slot.core.reserve_work()? {
            if let Err(error) = enqueue_private_key_view(&slot) {
                slot.core.fail(private_key_view_error(error.code))?;
                slot.core.release_work()?;
                pump_private_key_view(&slot)?;
                return Err(error);
            }
        }
        Ok(())
    })
}

/// # Safety
/// 撤销只能阻止显示，不能释放仍在授权中的宿主上下文或代替 finish。
#[no_mangle]
pub(crate) unsafe extern "C" fn citizensdk_internal_private_key_view_cancel(
    handle: CitizenSdkHandle,
    view_id: u64,
) -> i32 {
    ffi_status(|| {
        if !cfg!(feature = "wallet") {
            return Err(module_unsupported("wallet"));
        }
        let slot = private_key_view_slot(handle, view_id)?;
        slot.core.cancel()?;
        pump_private_key_view(&slot)
    })
}

/// # Safety
/// SDK 原生界面关闭且可擦除显示 buffer 已清零后才能调用；必须等最终 request 再销毁 context。
#[no_mangle]
pub(crate) unsafe extern "C" fn citizensdk_internal_private_key_view_finish(
    handle: CitizenSdkHandle,
    view_id: u64,
) -> i32 {
    ffi_status(|| {
        if !cfg!(feature = "wallet") {
            return Err(module_unsupported("wallet"));
        }
        let slot = private_key_view_slot(handle, view_id)?;
        slot.core.finish()?;
        pump_private_key_view(&slot)
    })
}

/// 把 Engine 已经持久化或核验后的高层钱包阶段投影到 ABI v1 既有的
/// `WATCH_UPDATE` 结果。`Pending` 尚无对应的 v1 watch 状态，`Interrupted`
/// 也不能伪装成链状态，所以二者只保留在持久历史/终态错误中，不发失真事件。
fn wallet_transfer_watch_event(stage: &WalletTransferWatchStage) -> Option<ExtrinsicWatchEvent> {
    match stage {
        WalletTransferWatchStage::Pending | WalletTransferWatchStage::Interrupted { .. } => None,
        WalletTransferWatchStage::Ready => Some(ExtrinsicWatchEvent::Ready),
        WalletTransferWatchStage::Broadcast { peer_count } => {
            Some(ExtrinsicWatchEvent::Broadcast {
                peer_count: *peer_count,
            })
        }
        WalletTransferWatchStage::Future => Some(ExtrinsicWatchEvent::Future),
        WalletTransferWatchStage::InBlock { block } => {
            Some(ExtrinsicWatchEvent::InBlock { block: *block })
        }
        WalletTransferWatchStage::Retracted { block } => {
            Some(ExtrinsicWatchEvent::Retracted { block: *block })
        }
        WalletTransferWatchStage::FinalityTimeout { block } => {
            Some(ExtrinsicWatchEvent::FinalityTimeout { block: *block })
        }
        WalletTransferWatchStage::Dropped => Some(ExtrinsicWatchEvent::Dropped),
        WalletTransferWatchStage::Finalized { conclusion } => {
            let block = match conclusion {
                ExecutionConclusion::Success { block, .. }
                | ExecutionConclusion::Failed { block, .. } => (*block).try_into().ok(),
                ExecutionConclusion::Unverified { block, .. } => {
                    block.and_then(|value| value.try_into().ok())
                }
            }?;
            Some(ExtrinsicWatchEvent::Finalized { block })
        }
        // ABI v1 已有 Invalid 和 Usurped；必须根据 Engine 保留的原始拒绝事实
        // 原样投影，不得丢失替代交易哈希。
        WalletTransferWatchStage::PoolRejected {
            replacement_hash: Some(replacement_hash),
            ..
        } => Some(ExtrinsicWatchEvent::Usurped {
            replacement_hash: *replacement_hash,
        }),
        WalletTransferWatchStage::PoolRejected {
            replacement_hash: None,
            ..
        } => Some(ExtrinsicWatchEvent::Invalid),
    }
}

struct AbiWalletTransferObserver {
    runtime: Arc<NativeRuntime>,
    request_id: CitizenSdkRequestId,
}

impl WalletTransferObserver for AbiWalletTransferObserver {
    fn on_update(&self, update: WalletTransferWatchUpdate) {
        let Some(event) = wallet_transfer_watch_event(update.stage()) else {
            return;
        };
        // 观察器属于展示边界。队列关闭/满不能回滚已经持久化的交易事实，
        // NativeRuntime 会在投递失败时回收刚创建的 result handle。
        let _ = self.runtime.publish_watch_update(self.request_id, event);
    }
}

struct PreparedWalletEntry {
    owner: CitizenSdkHandle,
    prepared: PreparedWalletCreation,
}

enum PreparedWalletSlot {
    Available(PreparedWalletEntry),
    Claimed { owner: CitizenSdkHandle },
}

struct PreparedWalletClaim {
    handle: CitizenSdkPreparedWalletHandle,
    owner: CitizenSdkHandle,
    prepared: Option<PreparedWalletCreation>,
    consumed: bool,
}

impl PreparedWalletClaim {
    fn consume(mut self) -> FfiResult<PreparedWalletCreation> {
        let mut registry = lock_prepared_wallets()?;
        match registry.remove(&self.handle) {
            Some(PreparedWalletSlot::Claimed { owner }) if owner == self.owner => {}
            Some(slot) => {
                registry.insert(self.handle, slot);
                return Err(FfiError::internal(
                    "prepared wallet claim changed before request execution",
                ));
            }
            None => {
                return Err(FfiError::new(
                    CitizenSdkErrorCode::InvalidHandle,
                    "prepared wallet was released before request execution",
                ));
            }
        }
        self.consumed = true;
        self.prepared
            .take()
            .ok_or_else(|| FfiError::internal("prepared wallet claim is empty"))
    }
}

impl Drop for PreparedWalletClaim {
    fn drop(&mut self) {
        if self.consumed {
            return;
        }
        let Some(prepared) = self.prepared.take() else {
            return;
        };
        let mut registry = prepared_wallets()
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner);
        if matches!(
            registry.get(&self.handle),
            Some(PreparedWalletSlot::Claimed { owner }) if *owner == self.owner
        ) {
            registry.insert(
                self.handle,
                PreparedWalletSlot::Available(PreparedWalletEntry {
                    owner: self.owner,
                    prepared,
                }),
            );
        }
        // If teardown already removed the marker, dropping `prepared` here
        // zeroizes the recovery phrase instead of resurrecting a dead handle.
    }
}

static NEXT_PREPARED_WALLET: AtomicU64 = AtomicU64::new(1);
static PREPARED_WALLETS: OnceLock<
    Mutex<HashMap<CitizenSdkPreparedWalletHandle, PreparedWalletSlot>>,
> = OnceLock::new();

fn prepared_wallets() -> &'static Mutex<HashMap<CitizenSdkPreparedWalletHandle, PreparedWalletSlot>>
{
    PREPARED_WALLETS.get_or_init(|| Mutex::new(HashMap::new()))
}

fn lock_prepared_wallets(
) -> FfiResult<MutexGuard<'static, HashMap<CitizenSdkPreparedWalletHandle, PreparedWalletSlot>>> {
    prepared_wallets()
        .lock()
        .map_err(|_| FfiError::internal("prepared wallet registry is poisoned"))
}

fn next_prepared_wallet_handle() -> FfiResult<CitizenSdkPreparedWalletHandle> {
    NEXT_PREPARED_WALLET
        .fetch_update(Ordering::SeqCst, Ordering::SeqCst, |value| {
            value.checked_add(1).filter(|next| *next != 0)
        })
        .map_err(|_| FfiError::internal("prepared wallet handle space is exhausted"))
}

fn insert_prepared_wallet(
    owner: CitizenSdkHandle,
    prepared: PreparedWalletCreation,
) -> FfiResult<CitizenSdkPreparedWalletHandle> {
    let handle = next_prepared_wallet_handle()?;
    let replaced = lock_prepared_wallets()?.insert(
        handle,
        PreparedWalletSlot::Available(PreparedWalletEntry { owner, prepared }),
    );
    if replaced.is_some() {
        return Err(FfiError::internal(
            "monotonic prepared wallet handle collided with an existing slot",
        ));
    }
    Ok(handle)
}

fn claim_prepared_wallet(
    handle: CitizenSdkPreparedWalletHandle,
    owner: CitizenSdkHandle,
) -> FfiResult<PreparedWalletClaim> {
    if handle == 0 {
        return Err(FfiError::new(
            CitizenSdkErrorCode::InvalidHandle,
            "prepared wallet handle 0 is invalid",
        ));
    }
    let mut registry = lock_prepared_wallets()?;
    let slot = registry.remove(&handle).ok_or_else(|| {
        FfiError::new(
            CitizenSdkErrorCode::InvalidHandle,
            "prepared wallet is unknown or already consumed",
        )
    })?;
    match slot {
        PreparedWalletSlot::Available(entry) if entry.owner == owner => {
            registry.insert(handle, PreparedWalletSlot::Claimed { owner });
            Ok(PreparedWalletClaim {
                handle,
                owner,
                prepared: Some(entry.prepared),
                consumed: false,
            })
        }
        PreparedWalletSlot::Available(entry) => {
            registry.insert(handle, PreparedWalletSlot::Available(entry));
            Err(FfiError::new(
                CitizenSdkErrorCode::InvalidHandle,
                "prepared wallet belongs to another CitizenSDK instance",
            ))
        }
        PreparedWalletSlot::Claimed { owner: actual } => {
            registry.insert(handle, PreparedWalletSlot::Claimed { owner: actual });
            require_prepared_owner(actual, owner)?;
            Err(FfiError::new(
                CitizenSdkErrorCode::Busy,
                "prepared wallet is already being committed",
            ))
        }
    }
}

/// Teardown hook used by `NativeRuntime`: all uncommitted recovery phrases for
/// this instance are dropped and zeroized. A claimed entry can only coexist
/// with an outstanding request, which the existing destroy preflight rejects.
pub(crate) fn drop_prepared_for_owner(owner: CitizenSdkHandle) {
    let mut registry = prepared_wallets()
        .lock()
        .unwrap_or_else(std::sync::PoisonError::into_inner);
    registry.retain(|_, slot| match slot {
        PreparedWalletSlot::Available(entry) => entry.owner != owner,
        PreparedWalletSlot::Claimed { owner: entry_owner } => *entry_owner != owner,
    });
}

#[no_mangle]
/// Creates a host-composed instance after synchronously copying all vtables.
///
/// 安全存储与金库必须成组；公开资源按实际模块成组验证。
/// 此便利入口使用完整本地组合或链/交易/历史组合，显式选择模块使用统一模块创建入口。
///
/// # Safety
/// `options`, `host_services`, their pointed-to vtables, and `out_handle` must
/// remain readable/writable for this call. Copied callback contexts must stay
/// valid until successful instance destruction returns.
pub unsafe extern "C" fn citizensdk_create_with_host(
    options: *const CitizenSdkCreateOptions,
    host_services: *const CitizenSdkHostServicesV1,
    out_handle: *mut CitizenSdkHandle,
) -> i32 {
    ffi_status(|| {
        let options = read_versioned(options, "create options")?;
        let host_services = read_versioned(host_services, "host services")?;
        let bits = if host_services.secure_store.is_null() {
            citizen_sdk_contracts::Modules::CHAIN
                | citizen_sdk_contracts::Modules::TRANSACTIONS
                | citizen_sdk_contracts::Modules::HISTORY
        } else {
            citizen_sdk_contracts::Modules::ALL
        };
        let modules = crate::composition::validate_modules(bits)?;
        // 所有创建入口都经过唯一产品装配，不再复制链资产校验或运行时构造。
        crate::create_instance(&options, Some(&host_services), modules, out_handle)
    })
}

#[no_mangle]
/// 同步复制 SDK 固定链身份的 genesis_hash，不要求启动或联网。
///
/// # Safety
/// `out_genesis_hash` 必须可写 32 字节；调用期间不得并发销毁实例。
pub unsafe extern "C" fn citizensdk_get_genesis_hash(
    handle: CitizenSdkHandle,
    out_genesis_hash: *mut u8,
) -> i32 {
    #[cfg(not(feature = "chain"))]
    {
        let _ = (handle, out_genesis_hash);
        ffi_status(|| {
            Err(FfiError::new(
                CitizenSdkErrorCode::Unsupported,
                "当前构建不包含 chain 模块",
            ))
        })
    }
    #[cfg(feature = "chain")]
    {
        ffi_status(|| {
            require_output(out_genesis_hash, "out_genesis_hash")?;
            let runtime = handles::get(handle)?;
            let genesis_hash = runtime.engine().genesis_hash()?;
            ptr::copy_nonoverlapping(genesis_hash.as_bytes().as_ptr(), out_genesis_hash, 32);
            Ok(())
        })
    }
}

#[no_mangle]
/// 批量读取同一 finalized 块的余额，保留输入顺序和重复项。
///
/// 空输入允许 NULL，仍执行 Engine 模块/生命周期门但不读取链或钱包存储。
/// 与其他有限链读取共用请求排空合同；受理后不支持取消。
///
/// # Safety
/// 非空 `account_ids` 必须可读 `account_count` 项，`out_request_id` 必须可写。
pub unsafe extern "C" fn citizensdk_get_finalized_account_balances(
    handle: CitizenSdkHandle,
    account_ids: *const CitizenSdkAccountId,
    account_count: u32,
    out_request_id: *mut CitizenSdkRequestId,
) -> i32 {
    #[cfg(not(feature = "chain"))]
    {
        let _ = (handle, account_ids, account_count, out_request_id);
        ffi_status(|| {
            Err(FfiError::new(
                CitizenSdkErrorCode::Unsupported,
                "当前构建不包含 chain 模块",
            ))
        })
    }
    #[cfg(feature = "chain")]
    {
        ffi_status(|| {
            let runtime = handles::get(handle)?;
            let accounts = if account_count == 0 {
                Vec::new()
            } else {
                copy_account_ids(account_ids, account_count)?
            };
            accept_and_write(runtime, out_request_id, move |runtime, _, _| {
                // 非空查询独立刷新真实链就绪，不要求宿主先订阅或刷新能力。
                // 空查询保持零 provider/仓储访问，仍由 Engine 校验模块与生命周期。
                if !accounts.is_empty() {
                    runtime.refresh_chain_readiness()?;
                }
                let balances =
                    runtime.drive(runtime.engine().finalized_account_balances(accounts))??;
                Ok(ResultPayload::AccountBalances(balances))
            })
        })
    }
}

#[no_mangle]
/// Reads one finalized CitizenChain account balance.
///
/// # Safety
/// `account_id` and `out_request_id` must be readable/writable respectively.
pub unsafe extern "C" fn citizensdk_get_finalized_account_balance(
    handle: CitizenSdkHandle,
    account_id: *const CitizenSdkAccountId,
    out_request_id: *mut CitizenSdkRequestId,
) -> i32 {
    #[cfg(not(feature = "chain"))]
    {
        let _ = (handle, account_id, out_request_id);
        ffi_status(|| {
            Err(FfiError::new(
                CitizenSdkErrorCode::Unsupported,
                "当前构建不包含所需模块",
            ))
        })
    }
    #[cfg(feature = "chain")]
    {
        ffi_status(|| {
            let runtime = handles::get(handle)?;
            let account_id = account_id_from_pointer(account_id, "account_id")?;
            accept_and_write(runtime, out_request_id, move |runtime, _, _| {
                runtime.refresh_provider_capabilities()?;
                let balance =
                    runtime.drive(runtime.engine().finalized_account_balance(account_id))??;
                Ok(ResultPayload::AccountBalance(balance))
            })
        })
    }
}

#[no_mangle]
/// Reads the exact-best Runtime nonce; this is not a transaction-pool lease.
///
/// # Safety
/// `account_id` and `out_request_id` must be readable/writable respectively.
pub unsafe extern "C" fn citizensdk_get_account_nonce(
    handle: CitizenSdkHandle,
    account_id: *const CitizenSdkAccountId,
    out_request_id: *mut CitizenSdkRequestId,
) -> i32 {
    #[cfg(not(feature = "chain"))]
    {
        let _ = (handle, account_id, out_request_id);
        ffi_status(|| {
            Err(FfiError::new(
                CitizenSdkErrorCode::Unsupported,
                "当前构建不包含所需模块",
            ))
        })
    }
    #[cfg(feature = "chain")]
    {
        ffi_status(|| {
            let runtime = handles::get(handle)?;
            let account_id = account_id_from_pointer(account_id, "account_id")?;
            accept_and_write(runtime, out_request_id, move |runtime, _, _| {
                runtime.refresh_provider_capabilities()?;
                let nonce = runtime.drive(runtime.engine().account_next_index(account_id))??;
                Ok(ResultPayload::AccountNonce(nonce))
            })
        })
    }
}

#[no_mangle]
/// Reads one exact-best fee policy and existential deposit snapshot.
///
/// # Safety
/// `out_request_id` must be writable for one request identifier.
pub unsafe extern "C" fn citizensdk_get_best_fee_snapshot(
    handle: CitizenSdkHandle,
    out_request_id: *mut CitizenSdkRequestId,
) -> i32 {
    #[cfg(not(feature = "chain"))]
    {
        let _ = (handle, out_request_id);
        ffi_status(|| {
            Err(FfiError::new(
                CitizenSdkErrorCode::Unsupported,
                "当前构建不包含所需模块",
            ))
        })
    }
    #[cfg(feature = "chain")]
    {
        ffi_status(|| {
            let runtime = handles::get(handle)?;
            accept_and_write(runtime, out_request_id, move |runtime, _, _| {
                runtime.refresh_provider_capabilities()?;
                let snapshot = runtime.drive(runtime.engine().best_fee_snapshot())??;
                Ok(ResultPayload::FeeSnapshot(snapshot))
            })
        })
    }
}

#[no_mangle]
/// 同步复用派生密码校验，不返回规范化密码，不创建持久化状态。
///
/// # Safety
/// `password` 在调用期间必须按声明长度可读。
pub unsafe extern "C" fn citizensdk_validate_wallet_password(password: CitizenSdkBytesView) -> i32 {
    #[cfg(not(feature = "wallet"))]
    {
        let _ = (password);
        ffi_status(|| {
            Err(FfiError::new(
                CitizenSdkErrorCode::Unsupported,
                "当前构建不包含所需模块",
            ))
        })
    }
    #[cfg(feature = "wallet")]
    {
        ffi_status(|| {
            let password = secret_utf8(password, "wallet password", MAX_WALLET_SECRET_INPUT_BYTES)?;
            citizen_sdk_engine::validate_wallet_password(&password)?;
            Ok(())
        })
    }
}

#[no_mangle]
/// 同步复用 English BIP-39 输入校验；错误不回显单词。
///
/// # Safety
/// `mnemonic` 在调用期间必须按声明长度可读。
pub unsafe extern "C" fn citizensdk_validate_wallet_mnemonic(
    mnemonic: CitizenSdkBytesView,
    word_count: u32,
) -> i32 {
    #[cfg(not(feature = "wallet"))]
    {
        let _ = (mnemonic, word_count);
        ffi_status(|| {
            Err(FfiError::new(
                CitizenSdkErrorCode::Unsupported,
                "当前构建不包含所需模块",
            ))
        })
    }
    #[cfg(feature = "wallet")]
    {
        ffi_status(|| {
            let word_count = wallet_word_count(word_count)?;
            let mnemonic = secret_utf8(mnemonic, "wallet mnemonic", MAX_WALLET_SECRET_INPUT_BYTES)?;
            citizen_sdk_engine::validate_wallet_mnemonic(&mnemonic, word_count)?;
            Ok(())
        })
    }
}

#[no_mangle]
/// 同步查询本地官方词表，最多六词，以 LF 分隔且无尾随 LF/NUL。
/// 容量不足时不部分写入；查询所需长度不要求提供输出缓冲区。
///
/// # Safety
/// `prefix` 必须可读；`out_required` 必须可写；非空输出缓冲按容量可写。
pub unsafe extern "C" fn citizensdk_wallet_word_suggestions(
    prefix: CitizenSdkBytesView,
    buffer: *mut u8,
    capacity: u64,
    out_required: *mut u64,
) -> i32 {
    #[cfg(not(feature = "wallet"))]
    {
        let _ = (prefix, buffer, capacity, out_required);
        ffi_status(|| {
            Err(FfiError::new(
                CitizenSdkErrorCode::Unsupported,
                "当前构建不包含所需模块",
            ))
        })
    }
    #[cfg(feature = "wallet")]
    {
        ffi_status(|| {
            require_output(out_required, "out_required")?;
            ptr::write(out_required, 0);
            let prefix = secret_utf8(prefix, "wallet word prefix", MAX_WALLET_SECRET_INPUT_BYTES)?;
            let words = citizen_sdk_engine::wallet_word_suggestions(&prefix)?;
            copy_to_host(words.join("\n"), buffer, capacity, out_required)
        })
    }
}

#[no_mangle]
/// Loads the current public wallet profile without exporting any secret.
///
/// # Safety
/// `out_request_id` must be writable for one request identifier.
pub unsafe extern "C" fn citizensdk_get_wallet_profile(
    handle: CitizenSdkHandle,
    out_request_id: *mut CitizenSdkRequestId,
) -> i32 {
    #[cfg(not(feature = "wallet"))]
    {
        let _ = (handle, out_request_id);
        ffi_status(|| {
            Err(FfiError::new(
                CitizenSdkErrorCode::Unsupported,
                "当前构建不包含所需模块",
            ))
        })
    }
    #[cfg(feature = "wallet")]
    {
        ffi_status(|| {
            let runtime = handles::get(handle)?;
            accept_and_write(runtime, out_request_id, move |runtime, _, _| {
                runtime.refresh_provider_capabilities()?;
                let profile = runtime.drive(runtime.engine().wallet_profile())??;
                Ok(ResultPayload::WalletProfile(profile))
            })
        })
    }
}

#[no_mangle]
/// Creates a non-persistent, SDK-owned recovery-phrase session.
///
/// # Safety
/// `password` is borrowed only for this call and `out_request_id` is writable.
pub unsafe extern "C" fn citizensdk_prepare_wallet_creation(
    handle: CitizenSdkHandle,
    word_count: u32,
    password: CitizenSdkBytesView,
    out_request_id: *mut CitizenSdkRequestId,
) -> i32 {
    #[cfg(not(feature = "wallet"))]
    {
        let _ = (handle, word_count, password, out_request_id);
        ffi_status(|| {
            Err(FfiError::new(
                CitizenSdkErrorCode::Unsupported,
                "当前构建不包含所需模块",
            ))
        })
    }
    #[cfg(feature = "wallet")]
    {
        ffi_status(|| {
            let runtime = handles::get(handle)?;
            let word_count = wallet_word_count(word_count)?;
            let password = secret_utf8(password, "wallet password", MAX_WALLET_SECRET_INPUT_BYTES)?;
            accept_and_write(runtime, out_request_id, move |runtime, _, _| {
                runtime.refresh_provider_capabilities()?;
                let prepared = runtime.drive(
                    runtime
                        .engine()
                        .prepare_wallet_creation(word_count, password),
                )??;
                let prepared_handle = insert_prepared_wallet(runtime.handle(), prepared)?;
                Ok(ResultPayload::PreparedWallet(prepared_handle))
            })
        })
    }
}

#[no_mangle]
/// Copies or size-queries the recovery phrase while its prepared handle lives.
///
/// # Safety
/// Output pointers must satisfy the usual CitizenSDK copy-function contract.
pub unsafe extern "C" fn citizensdk_prepared_wallet_copy_mnemonic(
    handle: CitizenSdkHandle,
    prepared_wallet: CitizenSdkPreparedWalletHandle,
    buffer: *mut u8,
    capacity: u64,
    out_required: *mut u64,
) -> i32 {
    #[cfg(not(feature = "wallet"))]
    {
        let _ = (handle, prepared_wallet, buffer, capacity, out_required);
        ffi_status(|| {
            Err(FfiError::new(
                CitizenSdkErrorCode::Unsupported,
                "当前构建不包含所需模块",
            ))
        })
    }
    #[cfg(feature = "wallet")]
    {
        ffi_status(|| {
            let _runtime = handles::get(handle)?;
            let registry = lock_prepared_wallets()?;
            let slot = registry.get(&prepared_wallet).ok_or_else(|| {
                FfiError::new(
                    CitizenSdkErrorCode::InvalidHandle,
                    "prepared wallet is unknown or already released",
                )
            })?;
            match slot {
                PreparedWalletSlot::Available(entry) => {
                    require_prepared_owner(entry.owner, handle)?;
                    entry
                        .prepared
                        .with_mnemonic(|bytes| copy_to_host(bytes, buffer, capacity, out_required))
                }
                PreparedWalletSlot::Claimed { owner } => {
                    require_prepared_owner(*owner, handle)?;
                    Err(FfiError::new(
                        CitizenSdkErrorCode::Busy,
                        "prepared wallet is being committed",
                    ))
                }
            }
        })
    }
}

#[no_mangle]
/// Releases an uncommitted prepared wallet exactly once and zeroizes secrets.
pub extern "C" fn citizensdk_prepared_wallet_release(
    handle: CitizenSdkHandle,
    prepared_wallet: CitizenSdkPreparedWalletHandle,
) -> i32 {
    #[cfg(not(feature = "wallet"))]
    {
        let _ = (handle, prepared_wallet);
        ffi_status(|| {
            Err(FfiError::new(
                CitizenSdkErrorCode::Unsupported,
                "当前构建不包含所需模块",
            ))
        })
    }
    #[cfg(feature = "wallet")]
    {
        ffi_status(|| {
            let _runtime = handles::get(handle)?;
            let mut registry = lock_prepared_wallets()?;
            let slot = registry.remove(&prepared_wallet).ok_or_else(|| {
                FfiError::new(
                    CitizenSdkErrorCode::InvalidHandle,
                    "prepared wallet is unknown or already released",
                )
            })?;
            match slot {
                PreparedWalletSlot::Available(entry) if entry.owner == handle => Ok(()),
                PreparedWalletSlot::Available(entry) => {
                    registry.insert(prepared_wallet, PreparedWalletSlot::Available(entry));
                    Err(FfiError::new(
                        CitizenSdkErrorCode::InvalidHandle,
                        "prepared wallet belongs to another CitizenSDK instance",
                    ))
                }
                PreparedWalletSlot::Claimed { owner } => {
                    registry.insert(prepared_wallet, PreparedWalletSlot::Claimed { owner });
                    require_prepared_owner(owner, handle)?;
                    Err(FfiError::new(
                        CitizenSdkErrorCode::Busy,
                        "prepared wallet is being committed",
                    ))
                }
            }
        })
    }
}

fn require_prepared_owner(actual: CitizenSdkHandle, requested: CitizenSdkHandle) -> FfiResult<()> {
    if actual == requested {
        Ok(())
    } else {
        Err(FfiError::new(
            CitizenSdkErrorCode::InvalidHandle,
            "prepared wallet belongs to another CitizenSDK instance",
        ))
    }
}

#[no_mangle]
/// Consumes a prepared session after the user confirms recovery-phrase backup.
///
/// # Safety
/// `out_request_id` must be writable for one request identifier.
pub unsafe extern "C" fn citizensdk_commit_wallet_creation(
    handle: CitizenSdkHandle,
    prepared_wallet: CitizenSdkPreparedWalletHandle,
    out_request_id: *mut CitizenSdkRequestId,
) -> i32 {
    #[cfg(not(feature = "wallet"))]
    {
        let _ = (handle, prepared_wallet, out_request_id);
        ffi_status(|| {
            Err(FfiError::new(
                CitizenSdkErrorCode::Unsupported,
                "当前构建不包含所需模块",
            ))
        })
    }
    #[cfg(feature = "wallet")]
    {
        ffi_status(|| {
            let runtime = handles::get(handle)?;
            let claim = claim_prepared_wallet(prepared_wallet, handle)?;
            accept_and_write(runtime, out_request_id, move |runtime, _, _| {
                let prepared = claim.consume()?;
                runtime.refresh_provider_capabilities()?;
                let profile = runtime.drive(
                    runtime
                        .engine()
                        .commit_wallet_creation_after_backup(prepared),
                )??;
                Ok(ResultPayload::WalletProfile(Some(profile)))
            })
        })
    }
}

#[no_mangle]
/// Imports a wallet from a borrowed recovery phrase and optional password.
///
/// # Safety
/// Secret views are borrowed only for this call; `out_request_id` is writable.
pub unsafe extern "C" fn citizensdk_import_wallet(
    handle: CitizenSdkHandle,
    mnemonic: CitizenSdkBytesView,
    password: CitizenSdkBytesView,
    out_request_id: *mut CitizenSdkRequestId,
) -> i32 {
    #[cfg(not(feature = "wallet"))]
    {
        let _ = (handle, mnemonic, password, out_request_id);
        ffi_status(|| {
            Err(FfiError::new(
                CitizenSdkErrorCode::Unsupported,
                "当前构建不包含所需模块",
            ))
        })
    }
    #[cfg(feature = "wallet")]
    {
        ffi_status(|| {
            let runtime = handles::get(handle)?;
            let mnemonic =
                secret_buffer(mnemonic, "wallet mnemonic", MAX_WALLET_SECRET_INPUT_BYTES)?;
            let password = secret_utf8(password, "wallet password", MAX_WALLET_SECRET_INPUT_BYTES)?;
            accept_and_write(runtime, out_request_id, move |runtime, _, _| {
                runtime.refresh_provider_capabilities()?;
                let profile =
                    runtime.drive(runtime.engine().import_wallet(mnemonic, password))??;
                Ok(ResultPayload::WalletProfile(Some(profile)))
            })
        })
    }
}

#[no_mangle]
/// Derives and persists additional `//index` accounts for the current wallet.
///
/// # Safety
/// Secret/index inputs are borrowed only for this call; output is writable.
pub unsafe extern "C" fn citizensdk_add_wallet_accounts(
    handle: CitizenSdkHandle,
    mnemonic: CitizenSdkBytesView,
    password: CitizenSdkBytesView,
    indices: *const u32,
    index_count: u32,
    out_request_id: *mut CitizenSdkRequestId,
) -> i32 {
    #[cfg(not(feature = "wallet"))]
    {
        let _ = (
            handle,
            mnemonic,
            password,
            indices,
            index_count,
            out_request_id,
        );
        ffi_status(|| {
            Err(FfiError::new(
                CitizenSdkErrorCode::Unsupported,
                "当前构建不包含所需模块",
            ))
        })
    }
    #[cfg(feature = "wallet")]
    {
        ffi_status(|| {
            let runtime = handles::get(handle)?;
            let mnemonic =
                secret_buffer(mnemonic, "wallet mnemonic", MAX_WALLET_SECRET_INPUT_BYTES)?;
            let password = secret_utf8(password, "wallet password", MAX_WALLET_SECRET_INPUT_BYTES)?;
            let indices = copy_indices(indices, index_count)?;
            accept_and_write(runtime, out_request_id, move |runtime, _, _| {
                runtime.refresh_provider_capabilities()?;
                let accounts = runtime.drive(
                    runtime
                        .engine()
                        .add_wallet_accounts(mnemonic, password, indices),
                )??;
                Ok(ResultPayload::WalletAccounts(accounts))
            })
        })
    }
}

#[no_mangle]
/// Selects the active public wallet account.
///
/// # Safety
/// `account_id` and `out_request_id` must be readable/writable respectively.
pub unsafe extern "C" fn citizensdk_set_active_wallet_account(
    handle: CitizenSdkHandle,
    account_id: *const CitizenSdkAccountId,
    out_request_id: *mut CitizenSdkRequestId,
) -> i32 {
    #[cfg(not(feature = "wallet"))]
    {
        let _ = (handle, account_id, out_request_id);
        ffi_status(|| {
            Err(FfiError::new(
                CitizenSdkErrorCode::Unsupported,
                "当前构建不包含所需模块",
            ))
        })
    }
    #[cfg(feature = "wallet")]
    {
        wallet_profile_mutation(handle, account_id, out_request_id, |engine, account_id| {
            engine.set_active_wallet_account(account_id)
        })
    }
}

#[no_mangle]
/// Renames one public wallet account; the name is UTF-8 without a trailing NUL.
///
/// # Safety
/// Inputs are borrowed only for this call and `out_request_id` is writable.
pub unsafe extern "C" fn citizensdk_rename_wallet_account(
    handle: CitizenSdkHandle,
    account_id: *const CitizenSdkAccountId,
    name: CitizenSdkBytesView,
    out_request_id: *mut CitizenSdkRequestId,
) -> i32 {
    #[cfg(not(feature = "wallet"))]
    {
        let _ = (handle, account_id, name, out_request_id);
        ffi_status(|| {
            Err(FfiError::new(
                CitizenSdkErrorCode::Unsupported,
                "当前构建不包含所需模块",
            ))
        })
    }
    #[cfg(feature = "wallet")]
    {
        ffi_status(|| {
            let runtime = handles::get(handle)?;
            let account_id = account_id_from_pointer(account_id, "account_id")?;
            let name = utf8(name, "wallet account name", MAX_WALLET_NAME_BYTES)?;
            accept_and_write(runtime, out_request_id, move |runtime, _, _| {
                runtime.refresh_provider_capabilities()?;
                let profile =
                    runtime.drive(runtime.engine().rename_wallet_account(account_id, name))??;
                Ok(ResultPayload::WalletProfile(Some(profile)))
            })
        })
    }
}

#[no_mangle]
/// Deletes one wallet account under the Engine's anchor-account rules.
///
/// # Safety
/// `account_id` and `out_request_id` must be readable/writable respectively.
pub unsafe extern "C" fn citizensdk_delete_wallet_account(
    handle: CitizenSdkHandle,
    account_id: *const CitizenSdkAccountId,
    out_request_id: *mut CitizenSdkRequestId,
) -> i32 {
    #[cfg(not(feature = "wallet"))]
    {
        let _ = (handle, account_id, out_request_id);
        ffi_status(|| {
            Err(FfiError::new(
                CitizenSdkErrorCode::Unsupported,
                "当前构建不包含所需模块",
            ))
        })
    }
    #[cfg(feature = "wallet")]
    {
        ffi_status(|| {
            let runtime = handles::get(handle)?;
            let account_id = account_id_from_pointer(account_id, "account_id")?;
            accept_and_write(runtime, out_request_id, move |runtime, _, _| {
                runtime.refresh_provider_capabilities()?;
                runtime.drive(runtime.engine().delete_wallet_account(account_id))??;
                Ok(ResultPayload::Empty)
            })
        })
    }
}

#[no_mangle]
/// Retires the entire wallet generation and all of its secret slots.
///
/// # Safety
/// `out_request_id` must be writable for one request identifier.
pub unsafe extern "C" fn citizensdk_delete_wallet(
    handle: CitizenSdkHandle,
    out_request_id: *mut CitizenSdkRequestId,
) -> i32 {
    #[cfg(not(feature = "wallet"))]
    {
        let _ = (handle, out_request_id);
        ffi_status(|| {
            Err(FfiError::new(
                CitizenSdkErrorCode::Unsupported,
                "当前构建不包含所需模块",
            ))
        })
    }
    #[cfg(feature = "wallet")]
    {
        ffi_status(|| {
            let runtime = handles::get(handle)?;
            accept_and_write(runtime, out_request_id, move |runtime, _, _| {
                runtime.refresh_provider_capabilities()?;
                runtime.drive(runtime.engine().delete_wallet())??;
                Ok(ResultPayload::Empty)
            })
        })
    }
}

#[no_mangle]
/// Completes durable cleanup plans left by an interrupted wallet operation.
///
/// # Safety
/// `out_request_id` must be writable for one request identifier.
pub unsafe extern "C" fn citizensdk_reconcile_wallet_cleanup(
    handle: CitizenSdkHandle,
    out_request_id: *mut CitizenSdkRequestId,
) -> i32 {
    #[cfg(not(feature = "wallet"))]
    {
        let _ = (handle, out_request_id);
        ffi_status(|| {
            Err(FfiError::new(
                CitizenSdkErrorCode::Unsupported,
                "当前构建不包含所需模块",
            ))
        })
    }
    #[cfg(feature = "wallet")]
    {
        ffi_status(|| {
            let runtime = handles::get(handle)?;
            accept_and_write(runtime, out_request_id, move |runtime, _, _| {
                runtime.refresh_provider_capabilities()?;
                runtime.drive(runtime.engine().reconcile_wallet_cleanup())??;
                Ok(ResultPayload::Empty)
            })
        })
    }
}

#[no_mangle]
/// Signs an application payload with the selected wallet account in Rust.
///
/// # Safety
/// Inputs are borrowed only for this call and `out_request_id` is writable.
pub unsafe extern "C" fn citizensdk_sign_wallet_payload(
    handle: CitizenSdkHandle,
    account_id: *const CitizenSdkAccountId,
    message: CitizenSdkBytesView,
    out_request_id: *mut CitizenSdkRequestId,
) -> i32 {
    #[cfg(not(feature = "signing"))]
    {
        let _ = (handle, account_id, message, out_request_id);
        ffi_status(|| {
            Err(FfiError::new(
                CitizenSdkErrorCode::Unsupported,
                "当前构建不包含所需模块",
            ))
        })
    }
    #[cfg(feature = "signing")]
    {
        ffi_status(|| {
            let runtime = handles::get(handle)?;
            let account_id = account_id_from_pointer(account_id, "account_id")?;
            let message = copy_view(message, "signing message", MAX_ABI_INPUT_BYTES)?;
            accept_and_write(runtime, out_request_id, move |runtime, _, _| {
                runtime.refresh_provider_capabilities()?;
                let signature =
                    runtime.drive(runtime.engine().sign_wallet_payload(account_id, message))??;
                Ok(ResultPayload::Signature(signature))
            })
        })
    }
}

/// Drives the Engine's complete submit-and-watch future until a proven terminal
/// result, or cooperatively cancels and drains the accepted request. Cancellation
/// never drops the Engine future: an in-flight host store/CAS or vault operation
/// must really return before its lease and request completion are released.
/// This does not roll back a durable `Pending`/`InBlock` record.
/// 同参数再次调用 transfer 会核验并恢复原始授权字节，
/// 先同步 finalized 证据再决定是否重广播，不重新签名或更换 nonce。
#[cfg(feature = "chain")]
async fn wallet_transfer_or_cancellation<F>(
    transfer: F,
    cancellation: RequestCancellation,
    transfer_cancellation: WalletTransferCancellation,
) -> FfiResult<WalletTransferWatchResult>
where
    F: Future<Output = Result<WalletTransferWatchResult, EngineError>>,
{
    let budget_token = transfer_cancellation.clone();
    wallet_transfer_or_cancellation_and_budget(
        transfer,
        cancellation,
        transfer_cancellation,
        wallet_transfer_budget(&budget_token),
    )
    .await
}

async fn wallet_transfer_or_cancellation_and_budget<F, B>(
    transfer: F,
    cancellation: RequestCancellation,
    transfer_cancellation: WalletTransferCancellation,
    budget: B,
) -> FfiResult<WalletTransferWatchResult>
where
    F: Future<Output = Result<WalletTransferWatchResult, EngineError>>,
    B: Future<Output = ()>,
{
    let transfer = transfer.fuse();
    let cancellation = cancellation.fuse();
    let budget = budget.fuse();
    futures_util::pin_mut!(transfer, cancellation, budget);
    futures_util::select_biased! {
        _ = cancellation => {
            transfer_cancellation.cancel();
            // Keep polling the same future, including an already-entered CAS. Its
            // generation/request guard stops further reads or broadcast after drain.
            let _ = transfer.await;
            Err(FfiError::new(
                CitizenSdkErrorCode::Cancelled,
                "wallet transfer watch was cancelled after draining; durable pending/in-block history was retained",
            ))
        },
        result = transfer => result.map_err(FfiError::from),
        _ = budget => {
            transfer_cancellation.cancel();
            let _ = transfer.await;
            Err(FfiError::new(CitizenSdkErrorCode::Timeout,
                "wallet transfer observation budget expired after draining; execution remains unverified and durable history was retained"))
        },
    }
}

/// 计时器只唤醒协调取消，不拥有 Engine future；阶段切换由 Engine 的真实 watch 事实驱动。
#[cfg(feature = "chain")]
async fn wallet_transfer_budget(token: &WalletTransferCancellation) {
    loop {
        let remaining = token
            .remaining_budget()
            .unwrap_or(std::time::Duration::from_secs(1));
        if remaining.is_zero() {
            return;
        }
        tokio::time::sleep(remaining.min(std::time::Duration::from_secs(1))).await;
    }
}

#[no_mangle]
/// Builds, signs, records-before-broadcast, submits and verifies one transfer.
/// No signed extrinsic bytes are returned to the host. The complete terminal
/// watch uses the dedicated long-lived pool and may be cancelled without
/// clearing an already durable `Pending`/`InBlock` record. 已持久的完整授权与构造事实
/// 同次 CAS 写入；恢复不会把取消误作撤回，也不会从交易哈希重造另一笔转账。
///
/// # Safety
/// Account IDs/views are borrowed only for this call; output is writable.
pub unsafe extern "C" fn citizensdk_transfer_with_remark(
    handle: CitizenSdkHandle,
    source_account_id: *const CitizenSdkAccountId,
    destination_account_id: *const CitizenSdkAccountId,
    amount_fen: CitizenSdkU128,
    remark: CitizenSdkBytesView,
    out_request_id: *mut CitizenSdkRequestId,
) -> i32 {
    #[cfg(not(all(
        feature = "wallet",
        feature = "signing",
        feature = "chain",
        feature = "transactions",
        feature = "history"
    )))]
    {
        let _ = (
            handle,
            source_account_id,
            destination_account_id,
            amount_fen,
            remark,
            out_request_id,
        );
        ffi_status(|| {
            Err(FfiError::new(
                CitizenSdkErrorCode::Unsupported,
                "当前构建不包含所需模块",
            ))
        })
    }
    #[cfg(all(
        feature = "wallet",
        feature = "signing",
        feature = "chain",
        feature = "transactions",
        feature = "history"
    ))]
    {
        ffi_status(|| {
            let runtime = handles::get(handle)?;
            let source = account_id_from_pointer(source_account_id, "source_account_id")?;
            let destination =
                account_id_from_pointer(destination_account_id, "destination_account_id")?;
            let remark = utf8(remark, "transfer remark", MAX_TRANSFER_REMARK_BYTES)?;
            let amount_fen = u128_from_abi(amount_fen);
            accept_and_write_watch(
                runtime,
                out_request_id,
                move |runtime, request_id, cancellation| {
                    runtime.refresh_provider_capabilities()?;
                    let cancellation = cancellation.ok_or_else(|| {
                        FfiError::internal("wallet transfer cancellation channel is missing")
                    })?;
                    let observer: Arc<dyn WalletTransferObserver> =
                        Arc::new(AbiWalletTransferObserver {
                            runtime: Arc::clone(runtime),
                            request_id,
                        });
                    let transfer_cancellation = WalletTransferCancellation::default();
                    let transfer = runtime.drive(wallet_transfer_or_cancellation(
                        runtime.engine().transfer_with_remark_and_watch(
                            source,
                            destination,
                            amount_fen,
                            remark,
                            observer,
                            transfer_cancellation.clone(),
                        ),
                        cancellation,
                        transfer_cancellation,
                    ))??;
                    Ok(ResultPayload::WalletTransfer(transfer))
                },
            )
        })
    }
}

#[no_mangle]
/// Initializes tracked-account cursors at the current finalized head.
///
/// # Safety
/// `account_ids[0..account_count]` is readable and output is writable.
pub unsafe extern "C" fn citizensdk_initialize_finalized_history(
    handle: CitizenSdkHandle,
    account_ids: *const CitizenSdkAccountId,
    account_count: u32,
    out_request_id: *mut CitizenSdkRequestId,
) -> i32 {
    #[cfg(not(feature = "history"))]
    {
        let _ = (handle, account_ids, account_count, out_request_id);
        ffi_status(|| {
            Err(FfiError::new(
                CitizenSdkErrorCode::Unsupported,
                "当前构建不包含所需模块",
            ))
        })
    }
    #[cfg(feature = "history")]
    {
        history_request(
            handle,
            account_ids,
            account_count,
            out_request_id,
            |engine, accounts| engine.initialize_finalized_history(accounts),
        )
    }
}

#[no_mangle]
/// Scans at most the Core's fixed 120-block finalized batch.
///
/// # Safety
/// `account_ids[0..account_count]` is readable and output is writable.
pub unsafe extern "C" fn citizensdk_sync_finalized_history_batch(
    handle: CitizenSdkHandle,
    account_ids: *const CitizenSdkAccountId,
    account_count: u32,
    out_request_id: *mut CitizenSdkRequestId,
) -> i32 {
    #[cfg(not(feature = "history"))]
    {
        let _ = (handle, account_ids, account_count, out_request_id);
        ffi_status(|| {
            Err(FfiError::new(
                CitizenSdkErrorCode::Unsupported,
                "当前构建不包含所需模块",
            ))
        })
    }
    #[cfg(feature = "history")]
    {
        history_request(
            handle,
            account_ids,
            account_count,
            out_request_id,
            |engine, accounts| engine.sync_finalized_history_batch(accounts),
        )
    }
}

#[no_mangle]
/// Copies one typed finalized-balance result.
///
/// # Safety
/// `out_info` must contain a supported ABI prefix and be writable.
pub unsafe extern "C" fn citizensdk_result_get_account_balance(
    result: CitizenSdkResultHandle,
    out_info: *mut CitizenSdkAccountBalanceInfo,
) -> i32 {
    ffi_status(|| {
        validate_output_versioned(out_info, "account balance info")?;
        let owned = ownership::get(result)?;
        let ResultPayload::AccountBalance(balance) = owned.payload else {
            return Err(wrong_result("account balance"));
        };
        ptr::write(out_info, account_balance_to_abi(balance));
        Ok(())
    })
}

#[no_mangle]
/// 读取完整批量余额结果的项数，空批量合法返回零。
///
/// # Safety
/// `out_count` 必须可写；结果句柄必须存活到调用返回。
pub unsafe extern "C" fn citizensdk_result_get_account_balance_count(
    result: CitizenSdkResultHandle,
    out_count: *mut u32,
) -> i32 {
    ffi_status(|| {
        require_output(out_count, "out_count")?;
        let count = ownership::account_balance_count(result)?;
        ptr::write(out_count, count);
        Ok(())
    })
}

#[no_mangle]
/// 按输入索引复制批量余额中的一项；失败不修改输出结构。
///
/// # Safety
/// `out_info` 必须包含受支持的 ABI 前缀且可写；结果句柄必须保持存活。
pub unsafe extern "C" fn citizensdk_result_get_account_balance_at(
    result: CitizenSdkResultHandle,
    index: u32,
    out_info: *mut CitizenSdkAccountBalanceInfo,
) -> i32 {
    ffi_status(|| {
        validate_output_versioned(out_info, "account balance info")?;
        let balance = ownership::account_balance_at(result, index)?;
        ptr::write(out_info, account_balance_to_abi(balance));
        Ok(())
    })
}

#[no_mangle]
/// Copies one exact-best Runtime nonce result.
///
/// # Safety
/// `out_info` must contain a supported ABI prefix and be writable.
pub unsafe extern "C" fn citizensdk_result_get_account_nonce(
    result: CitizenSdkResultHandle,
    out_info: *mut CitizenSdkAccountNonceInfo,
) -> i32 {
    ffi_status(|| {
        validate_output_versioned(out_info, "account nonce info")?;
        let owned = ownership::get(result)?;
        let ResultPayload::AccountNonce(nonce) = owned.payload else {
            return Err(wrong_result("account nonce"));
        };
        ptr::write(
            out_info,
            CitizenSdkAccountNonceInfo {
                best_block: block_to_abi(nonce.best_block()),
                account_id: account_id_to_abi(nonce.account_id()),
                nonce: nonce.value(),
                ..CitizenSdkAccountNonceInfo::default()
            },
        );
        Ok(())
    })
}

#[no_mangle]
/// Copies one exact-best fee-policy result.
///
/// # Safety
/// `out_info` must contain a supported ABI prefix and be writable.
pub unsafe extern "C" fn citizensdk_result_get_fee_snapshot(
    result: CitizenSdkResultHandle,
    out_info: *mut CitizenSdkFeeSnapshotInfo,
) -> i32 {
    #[cfg(not(feature = "chain"))]
    {
        let _ = (result, out_info);
        ffi_status(|| {
            Err(FfiError::new(
                CitizenSdkErrorCode::Unsupported,
                "当前构建不包含所需模块",
            ))
        })
    }
    #[cfg(feature = "chain")]
    {
        ffi_status(|| {
            validate_output_versioned(out_info, "fee snapshot info")?;
            let owned = ownership::get(result)?;
            let ResultPayload::FeeSnapshot(snapshot) = owned.payload else {
                return Err(wrong_result("fee snapshot"));
            };
            ptr::write(out_info, fee_snapshot_to_abi(snapshot));
            Ok(())
        })
    }
}

#[no_mangle]
/// Applies the Core's exact Perbill rounding to a retained fee snapshot.
///
/// # Safety
/// Both output pointers must be writable for one `citizensdk_u128_t`.
pub unsafe extern "C" fn citizensdk_result_estimate_fee(
    result: CitizenSdkResultHandle,
    amount_fen: CitizenSdkU128,
    out_estimated_fee_fen: *mut CitizenSdkU128,
    out_minimum_self_pay_fen: *mut CitizenSdkU128,
) -> i32 {
    #[cfg(not(feature = "chain"))]
    {
        let _ = (
            result,
            amount_fen,
            out_estimated_fee_fen,
            out_minimum_self_pay_fen,
        );
        ffi_status(|| {
            Err(FfiError::new(
                CitizenSdkErrorCode::Unsupported,
                "当前构建不包含所需模块",
            ))
        })
    }
    #[cfg(feature = "chain")]
    {
        ffi_status(|| {
            require_output(out_estimated_fee_fen, "out_estimated_fee_fen")?;
            require_output(out_minimum_self_pay_fen, "out_minimum_self_pay_fen")?;
            let owned = ownership::get(result)?;
            let ResultPayload::FeeSnapshot(snapshot) = owned.payload else {
                return Err(wrong_result("fee snapshot"));
            };
            let estimated = snapshot.estimate_fee_fen(u128_from_abi(amount_fen))?;
            let minimum_self_pay = snapshot.minimum_self_pay_fen()?;
            ptr::write(out_estimated_fee_fen, u128_to_abi(estimated));
            ptr::write(out_minimum_self_pay_fen, u128_to_abi(minimum_self_pay));
            Ok(())
        })
    }
}

#[no_mangle]
/// Copies the secret-free wallet profile descriptor; `present=0` is valid.
///
/// # Safety
/// `out_info` must contain a supported ABI prefix and be writable.
pub unsafe extern "C" fn citizensdk_result_get_wallet_profile(
    result: CitizenSdkResultHandle,
    out_info: *mut CitizenSdkWalletProfileInfo,
) -> i32 {
    ffi_status(|| {
        validate_output_versioned(out_info, "wallet profile info")?;
        let owned = ownership::get(result)?;
        let ResultPayload::WalletProfile(profile) = owned.payload else {
            return Err(wrong_result("wallet profile"));
        };
        ptr::write(out_info, wallet_profile_to_abi(profile.as_ref())?);
        Ok(())
    })
}

#[no_mangle]
/// Returns account count for a profile or add-accounts result.
///
/// # Safety
/// `out_count` must be writable for one `u32`.
pub unsafe extern "C" fn citizensdk_result_get_wallet_account_count(
    result: CitizenSdkResultHandle,
    out_count: *mut u32,
) -> i32 {
    ffi_status(|| {
        require_output(out_count, "out_count")?;
        let owned = ownership::get(result)?;
        let (accounts, _) = wallet_accounts(&owned.payload)?;
        let count = u32::try_from(accounts.len())
            .map_err(|_| FfiError::internal("wallet account result is too large"))?;
        ptr::write(out_count, count);
        Ok(())
    })
}

#[no_mangle]
/// Copies one wallet account and size-queries/copies its two UTF-8 labels.
///
/// # Safety
/// Every output pointer follows the documented CitizenSDK copy contract.
#[allow(clippy::too_many_arguments)]
pub unsafe extern "C" fn citizensdk_result_get_wallet_account(
    result: CitizenSdkResultHandle,
    index: u32,
    out_info: *mut CitizenSdkWalletAccountInfo,
    ss58_buffer: *mut u8,
    ss58_capacity: u64,
    out_ss58_required: *mut u64,
    name_buffer: *mut u8,
    name_capacity: u64,
    out_name_required: *mut u64,
) -> i32 {
    ffi_status(|| {
        validate_output_versioned(out_info, "wallet account info")?;
        let owned = ownership::get(result)?;
        let (accounts, active) = wallet_accounts(&owned.payload)?;
        let account = accounts
            .get(index as usize)
            .ok_or_else(|| FfiError::invalid("wallet account index is out of range"))?;
        copy_pair(
            account.ss58_address().as_bytes(),
            ss58_buffer,
            ss58_capacity,
            out_ss58_required,
            account.name().as_bytes(),
            name_buffer,
            name_capacity,
            out_name_required,
        )?;
        ptr::write(
            out_info,
            CitizenSdkWalletAccountInfo {
                index: account.index(),
                is_active: u32::from(active == Some(account.account_id())),
                account_id: account_id_to_abi(account.account_id()),
                created_at_millis: account.created_at_millis(),
                ss58_address_len: account.ss58_address().len() as u64,
                name_len: account.name().len() as u64,
                ..CitizenSdkWalletAccountInfo::default()
            },
        );
        Ok(())
    })
}

#[no_mangle]
/// Copies a 64-byte sr25519 signature; no signing secret is returned.
///
/// # Safety
/// `out_signature_64` must be writable for exactly 64 bytes.
pub unsafe extern "C" fn citizensdk_result_get_signature(
    result: CitizenSdkResultHandle,
    out_signature_64: *mut u8,
) -> i32 {
    ffi_status(|| {
        require_output(out_signature_64, "out_signature_64")?;
        let owned = ownership::get(result)?;
        let ResultPayload::Signature(signature) = owned.payload else {
            return Err(wrong_result("sr25519 signature"));
        };
        ptr::copy_nonoverlapping(signature.as_bytes().as_ptr(), out_signature_64, 64);
        Ok(())
    })
}

#[no_mangle]
/// Copies the independently-owned prepared handle from its completion result.
///
/// # Safety
/// `out_info` must contain a supported ABI prefix and be writable.
pub unsafe extern "C" fn citizensdk_result_get_prepared_wallet(
    result: CitizenSdkResultHandle,
    out_info: *mut CitizenSdkPreparedWalletInfo,
) -> i32 {
    ffi_status(|| {
        validate_output_versioned(out_info, "prepared wallet info")?;
        let owned = ownership::get(result)?;
        let ResultPayload::PreparedWallet(prepared_wallet) = owned.payload else {
            return Err(wrong_result("prepared wallet"));
        };
        ptr::write(
            out_info,
            CitizenSdkPreparedWalletInfo {
                prepared_wallet,
                ..CitizenSdkPreparedWalletInfo::default()
            },
        );
        Ok(())
    })
}

#[no_mangle]
/// Copies a terminal high-level wallet transfer and optional pool reason.
///
/// # Safety
/// Every output pointer follows the documented CitizenSDK copy contract.
pub unsafe extern "C" fn citizensdk_result_get_wallet_transfer(
    result: CitizenSdkResultHandle,
    out_info: *mut CitizenSdkWalletTransferInfo,
    reason_buffer: *mut u8,
    reason_capacity: u64,
    out_reason_required: *mut u64,
) -> i32 {
    ffi_status(|| {
        validate_output_versioned(out_info, "wallet transfer info")?;
        let owned = ownership::get(result)?;
        let ResultPayload::WalletTransfer(transfer) = owned.payload else {
            return Err(wrong_result("wallet transfer"));
        };
        let (resolution, execution, reason) = transfer_resolution(transfer.resolution())?;
        copy_to_host(
            reason.as_bytes(),
            reason_buffer,
            reason_capacity,
            out_reason_required,
        )?;
        ptr::write(
            out_info,
            CitizenSdkWalletTransferInfo {
                transaction_hash: transfer.transaction_hash().into_bytes(),
                resolution,
                has_execution: u32::from(execution.is_some()),
                execution: execution
                    .as_ref()
                    .map(execution_to_abi)
                    .unwrap_or_else(|| CitizenSdkWalletTransferInfo::default().execution),
                pool_rejection_reason_len: reason.len() as u64,
                ..CitizenSdkWalletTransferInfo::default()
            },
        );
        Ok(())
    })
}

#[no_mangle]
/// Copies summary counts for history or a wallet-transfer result's history.
///
/// # Safety
/// `out_info` must contain a supported ABI prefix and be writable.
pub unsafe extern "C" fn citizensdk_result_get_history_info(
    result: CitizenSdkResultHandle,
    out_info: *mut CitizenSdkHistoryInfo,
) -> i32 {
    ffi_status(|| {
        validate_output_versioned(out_info, "history info")?;
        let owned = ownership::get(result)?;
        let history = history_state(&owned.payload)?;
        ptr::write(
            out_info,
            CitizenSdkHistoryInfo {
                revision: history.revision(),
                cursor_count: checked_count(history.cursors().len(), "history cursor")?,
                record_count: checked_count(history.records().len(), "history record")?,
                transfer_count: checked_count(history.transfers().len(), "history transfer")?,
                ..CitizenSdkHistoryInfo::default()
            },
        );
        Ok(())
    })
}

#[no_mangle]
/// Copies one finalized-history cursor.
///
/// # Safety
/// `out_info` must contain a supported ABI prefix and be writable.
pub unsafe extern "C" fn citizensdk_result_get_history_cursor(
    result: CitizenSdkResultHandle,
    index: u32,
    out_info: *mut CitizenSdkHistoryCursorInfo,
) -> i32 {
    ffi_status(|| {
        validate_output_versioned(out_info, "history cursor info")?;
        let owned = ownership::get(result)?;
        let cursor = history_state(&owned.payload)?
            .cursors()
            .get(index as usize)
            .copied()
            .ok_or_else(|| FfiError::invalid("history cursor index is out of range"))?;
        ptr::write(
            out_info,
            CitizenSdkHistoryCursorInfo {
                account_id: account_id_to_abi(cursor.account_id()),
                tracking_start_block: block_to_abi(cursor.tracking_start_block().into()),
                last_synced_block: block_to_abi(cursor.last_synced_block().into()),
                ..CitizenSdkHistoryCursorInfo::default()
            },
        );
        Ok(())
    })
}

#[no_mangle]
/// Copies one pending/finalized submission record and its variable text.
///
/// # Safety
/// Every output pointer follows the documented CitizenSDK copy contract.
#[allow(clippy::too_many_arguments)]
pub unsafe extern "C" fn citizensdk_result_get_history_record(
    result: CitizenSdkResultHandle,
    index: u32,
    out_info: *mut CitizenSdkHistoryRecordInfo,
    remark_buffer: *mut u8,
    remark_capacity: u64,
    out_remark_required: *mut u64,
    reason_buffer: *mut u8,
    reason_capacity: u64,
    out_reason_required: *mut u64,
) -> i32 {
    ffi_status(|| {
        validate_output_versioned(out_info, "history record info")?;
        let owned = ownership::get(result)?;
        let record = history_state(&owned.payload)?
            .records()
            .get(index as usize)
            .ok_or_else(|| FfiError::invalid("history record index is out of range"))?;
        let (status, block, execution, reason) = history_status(record)?;
        copy_pair(
            record.remark().as_bytes(),
            remark_buffer,
            remark_capacity,
            out_remark_required,
            reason.as_bytes(),
            reason_buffer,
            reason_capacity,
            out_reason_required,
        )?;
        ptr::write(
            out_info,
            CitizenSdkHistoryRecordInfo {
                account_id: account_id_to_abi(record.account_id()),
                transaction_hash: record.transaction_hash().into_bytes(),
                nonce: record.nonce(),
                destination_account_id: account_id_to_abi(record.destination_account_id()),
                amount_fen: u128_to_abi(record.amount_fen()),
                status,
                has_block: u32::from(block.is_some()),
                block: block
                    .map(block_to_abi)
                    .unwrap_or_else(CitizenSdkBlockRef::default),
                has_execution: u32::from(execution.is_some()),
                execution: execution
                    .as_ref()
                    .map(execution_to_abi)
                    .unwrap_or_else(|| CitizenSdkWalletTransferInfo::default().execution),
                created_at_millis: record.created_at_millis(),
                updated_at_millis: record.updated_at_millis(),
                remark_len: record.remark().len() as u64,
                pool_rejection_reason_len: reason.len() as u64,
                ..CitizenSdkHistoryRecordInfo::default()
            },
        );
        Ok(())
    })
}

#[no_mangle]
/// Copies one finalized transfer, preserving raw Runtime remark bytes.
///
/// # Safety
/// Every output pointer follows the documented CitizenSDK copy contract.
#[allow(clippy::too_many_arguments)]
pub unsafe extern "C" fn citizensdk_result_get_finalized_transfer(
    result: CitizenSdkResultHandle,
    index: u32,
    out_info: *mut CitizenSdkFinalizedTransferInfo,
    source_pallet_buffer: *mut u8,
    source_pallet_capacity: u64,
    out_source_pallet_required: *mut u64,
    remark_display_buffer: *mut u8,
    remark_display_capacity: u64,
    out_remark_display_required: *mut u64,
    remark_bytes_buffer: *mut u8,
    remark_bytes_capacity: u64,
    out_remark_bytes_required: *mut u64,
) -> i32 {
    ffi_status(|| {
        validate_output_versioned(out_info, "finalized transfer info")?;
        let owned = ownership::get(result)?;
        let transfer = history_state(&owned.payload)?
            .transfers()
            .get(index as usize)
            .ok_or_else(|| FfiError::invalid("finalized transfer index is out of range"))?;
        let display = transfer.remark().unwrap_or_default().as_bytes();
        let raw = transfer.remark_bytes().unwrap_or_default();
        copy_three(
            transfer.source_pallet().as_bytes(),
            source_pallet_buffer,
            source_pallet_capacity,
            out_source_pallet_required,
            display,
            remark_display_buffer,
            remark_display_capacity,
            out_remark_display_required,
            raw,
            remark_bytes_buffer,
            remark_bytes_capacity,
            out_remark_bytes_required,
        )?;
        ptr::write(out_info, finalized_transfer_to_abi(transfer));
        Ok(())
    })
}

unsafe fn wallet_profile_mutation<F>(
    handle: CitizenSdkHandle,
    account_id: *const CitizenSdkAccountId,
    out_request_id: *mut CitizenSdkRequestId,
    operation: F,
) -> i32
where
    F: for<'a> FnOnce(
            &'a citizen_sdk_engine::CitizenEngine,
            AccountId32,
        ) -> citizen_sdk_engine::EngineFuture<'a, WalletProfile>
        + Send
        + 'static,
{
    ffi_status(|| {
        let runtime = handles::get(handle)?;
        let account_id = account_id_from_pointer(account_id, "account_id")?;
        accept_and_write(runtime, out_request_id, move |runtime, _, _| {
            runtime.refresh_provider_capabilities()?;
            let profile = runtime.drive(operation(runtime.engine().as_ref(), account_id))??;
            Ok(ResultPayload::WalletProfile(Some(profile)))
        })
    })
}

#[cfg(feature = "chain")]
unsafe fn history_request<F>(
    handle: CitizenSdkHandle,
    account_ids: *const CitizenSdkAccountId,
    account_count: u32,
    out_request_id: *mut CitizenSdkRequestId,
    operation: F,
) -> i32
where
    F: for<'a> FnOnce(
            &'a citizen_sdk_engine::CitizenEngine,
            Vec<AccountId32>,
        ) -> citizen_sdk_engine::EngineFuture<'a, TransactionHistoryState>
        + Send
        + 'static,
{
    ffi_status(|| {
        let runtime = handles::get(handle)?;
        let accounts = copy_account_ids(account_ids, account_count)?;
        accept_and_write(runtime, out_request_id, move |runtime, _, _| {
            runtime.refresh_provider_capabilities()?;
            let history = runtime.drive(operation(runtime.engine().as_ref(), accounts))??;
            Ok(ResultPayload::TransactionHistory(history))
        })
    })
}

unsafe fn account_id_from_pointer(
    pointer: *const CitizenSdkAccountId,
    name: &str,
) -> FfiResult<AccountId32> {
    if pointer.is_null() {
        return Err(FfiError::invalid(format!("{name} is null")));
    }
    Ok(AccountId32::from_bytes(ptr::read(pointer).bytes))
}

const fn account_id_to_abi(account_id: AccountId32) -> CitizenSdkAccountId {
    CitizenSdkAccountId {
        bytes: *account_id.as_bytes(),
    }
}

fn account_balance_to_abi(balance: FinalizedAccountBalance) -> CitizenSdkAccountBalanceInfo {
    CitizenSdkAccountBalanceInfo {
        block: block_to_abi(balance.block().into()),
        account_id: account_id_to_abi(balance.account_id()),
        free_fen: u128_to_abi(balance.free_fen()),
        reserved_fen: u128_to_abi(balance.reserved_fen()),
        total_fen: u128_to_abi(balance.total_fen()),
        ..CitizenSdkAccountBalanceInfo::default()
    }
}

const fn u128_from_abi(value: CitizenSdkU128) -> u128 {
    (value.low as u128) | ((value.high as u128) << 64)
}

const fn u128_to_abi(value: u128) -> CitizenSdkU128 {
    CitizenSdkU128 {
        low: value as u64,
        high: (value >> 64) as u64,
    }
}

fn wallet_word_count(value: u32) -> FfiResult<WalletWordCount> {
    match value {
        value if value == CitizenSdkWalletWordCount::Words12 as u32 => Ok(WalletWordCount::Words12),
        value if value == CitizenSdkWalletWordCount::Words18 as u32 => Ok(WalletWordCount::Words18),
        value if value == CitizenSdkWalletWordCount::Words24 as u32 => Ok(WalletWordCount::Words24),
        _ => Err(FfiError::invalid("wallet word count must be 12, 18 or 24")),
    }
}

unsafe fn secret_buffer(
    view: CitizenSdkBytesView,
    name: &str,
    maximum: usize,
) -> FfiResult<SecretBuffer> {
    SecretBuffer::try_new(copy_view(view, name, maximum)?).map_err(Into::into)
}

unsafe fn secret_utf8(
    view: CitizenSdkBytesView,
    name: &str,
    maximum: usize,
) -> FfiResult<Zeroizing<String>> {
    let bytes = Zeroizing::new(copy_view(view, name, maximum)?);
    let text = std::str::from_utf8(bytes.as_slice())
        .map_err(|_| FfiError::invalid(format!("{name} is not UTF-8")))?;
    Ok(Zeroizing::new(text.to_owned()))
}

unsafe fn utf8(view: CitizenSdkBytesView, name: &str, maximum: usize) -> FfiResult<String> {
    String::from_utf8(copy_view(view, name, maximum)?)
        .map_err(|_| FfiError::invalid(format!("{name} is not UTF-8")))
}

unsafe fn copy_indices(pointer: *const u32, count: u32) -> FfiResult<Vec<u32>> {
    let count =
        usize::try_from(count).map_err(|_| FfiError::invalid("index count is too large"))?;
    if count == 0 || count > MAX_ACCOUNT_BATCH || pointer.is_null() {
        return Err(FfiError::invalid(
            "wallet index list must contain between 1 and 1990 items",
        ));
    }
    Ok(std::slice::from_raw_parts(pointer, count).to_vec())
}

unsafe fn copy_account_ids(
    pointer: *const CitizenSdkAccountId,
    count: u32,
) -> FfiResult<Vec<AccountId32>> {
    let count =
        usize::try_from(count).map_err(|_| FfiError::invalid("account count is too large"))?;
    if count == 0 || count > MAX_ACCOUNT_BATCH || pointer.is_null() {
        return Err(FfiError::invalid(
            "account list must contain between 1 and 1990 items",
        ));
    }
    Ok(std::slice::from_raw_parts(pointer, count)
        .iter()
        .map(|account| AccountId32::from_bytes(account.bytes))
        .collect())
}

#[cfg(feature = "chain")]
fn fee_snapshot_to_abi(snapshot: BestFeeSnapshot) -> CitizenSdkFeeSnapshotInfo {
    CitizenSdkFeeSnapshotInfo {
        best_block: block_to_abi(snapshot.block()),
        fee_rate_parts: snapshot.policy().fee_rate_parts(),
        minimum_fee_fen: u128_to_abi(snapshot.policy().minimum_fee_fen()),
        existential_deposit_fen: u128_to_abi(snapshot.existential_deposit_fen()),
        ..CitizenSdkFeeSnapshotInfo::default()
    }
}

fn wallet_profile_to_abi(
    profile: Option<&WalletProfile>,
) -> FfiResult<CitizenSdkWalletProfileInfo> {
    let Some(profile) = profile else {
        return Ok(CitizenSdkWalletProfileInfo::default());
    };
    Ok(CitizenSdkWalletProfileInfo {
        present: 1,
        origin: match profile.origin() {
            WalletOrigin::Created => CitizenSdkWalletOrigin::Created,
            WalletOrigin::Imported => CitizenSdkWalletOrigin::Imported,
        } as u32,
        wallet_index: profile.wallet_index(),
        account_count: checked_count(profile.accounts().len(), "wallet account")?,
        created_at_millis: profile.created_at_millis(),
        master_account_id: account_id_to_abi(profile.master_account_id()),
        active_account_id: account_id_to_abi(profile.active_account_id()),
        ..CitizenSdkWalletProfileInfo::default()
    })
}

fn wallet_accounts(payload: &ResultPayload) -> FfiResult<(&[WalletAccount], Option<AccountId32>)> {
    match payload {
        ResultPayload::WalletProfile(Some(profile)) => {
            Ok((profile.accounts(), Some(profile.active_account_id())))
        }
        ResultPayload::WalletProfile(None) => Ok((&[], None)),
        ResultPayload::WalletAccounts(accounts) => Ok((accounts, None)),
        _ => Err(wrong_result("wallet profile or account list")),
    }
}

fn transfer_resolution(
    resolution: &WalletTransferResolution,
) -> FfiResult<(u32, Option<ExecutionConclusion>, &str)> {
    match resolution {
        WalletTransferResolution::Finalized(conclusion @ ExecutionConclusion::Success { .. }) => {
            Ok((
                CitizenSdkTransferResolution::FinalizedSuccess as u32,
                Some(conclusion.clone()),
                "",
            ))
        }
        WalletTransferResolution::Finalized(conclusion @ ExecutionConclusion::Failed { .. }) => {
            Ok((
                CitizenSdkTransferResolution::FinalizedFailed as u32,
                Some(conclusion.clone()),
                "",
            ))
        }
        WalletTransferResolution::Finalized(ExecutionConclusion::Unverified { .. }) => {
            Err(FfiError::new(
                CitizenSdkErrorCode::Integrity,
                "wallet transfer cannot expose an unverified finalized resolution",
            ))
        }
        WalletTransferResolution::PoolRejected { reason } => Ok((
            CitizenSdkTransferResolution::PoolRejected as u32,
            None,
            reason,
        )),
    }
}

fn history_state(payload: &ResultPayload) -> FfiResult<&TransactionHistoryState> {
    match payload {
        ResultPayload::TransactionHistory(history) => Ok(history),
        ResultPayload::WalletTransfer(transfer) => Ok(transfer.history()),
        _ => Err(wrong_result("transaction history")),
    }
}

type HistoryStatusProjection<'a> = (
    u32,
    Option<citizen_sdk_contracts::VerifiedBlockRef>,
    Option<ExecutionConclusion>,
    &'a str,
);

fn history_status(record: &TransactionHistoryRecord) -> FfiResult<HistoryStatusProjection<'_>> {
    match record.status() {
        HistoryTransactionStatus::Pending => {
            Ok((CitizenSdkHistoryStatus::Pending as u32, None, None, ""))
        }
        HistoryTransactionStatus::InBlock { block } => Ok((
            CitizenSdkHistoryStatus::InBlock as u32,
            Some(*block),
            None,
            "",
        )),
        HistoryTransactionStatus::PoolRejected { reason } => Ok((
            CitizenSdkHistoryStatus::PoolRejected as u32,
            None,
            None,
            reason,
        )),
        HistoryTransactionStatus::Execution(
            conclusion @ ExecutionConclusion::Success { block, .. },
        ) => Ok((
            CitizenSdkHistoryStatus::FinalizedSuccess as u32,
            Some(*block),
            Some(conclusion.clone()),
            "",
        )),
        HistoryTransactionStatus::Execution(
            conclusion @ ExecutionConclusion::Failed { block, .. },
        ) => Ok((
            CitizenSdkHistoryStatus::FinalizedFailed as u32,
            Some(*block),
            Some(conclusion.clone()),
            "",
        )),
        HistoryTransactionStatus::Execution(ExecutionConclusion::Unverified { .. }) => {
            Err(FfiError::new(
                CitizenSdkErrorCode::Integrity,
                "persisted history contains an unverified execution",
            ))
        }
    }
}

fn finalized_transfer_to_abi(
    transfer: &FinalizedTransferRecord,
) -> CitizenSdkFinalizedTransferInfo {
    CitizenSdkFinalizedTransferInfo {
        tracked_account_id: account_id_to_abi(transfer.tracked_account_id()),
        from_account_id: account_id_to_abi(transfer.from_account_id()),
        to_account_id: account_id_to_abi(transfer.to_account_id()),
        amount_fen: u128_to_abi(transfer.amount_fen()),
        block: block_to_abi(transfer.block().into()),
        event_record_index: transfer.event_record_index(),
        has_extrinsic_index: u32::from(transfer.extrinsic_index().is_some()),
        extrinsic_index: transfer.extrinsic_index().unwrap_or_default(),
        direction: if transfer.is_incoming() {
            CitizenSdkTransferDirection::Incoming
        } else {
            CitizenSdkTransferDirection::Outgoing
        } as u32,
        source_pallet_len: transfer.source_pallet().len() as u64,
        remark_display_len: transfer.remark().map_or(0, str::len) as u64,
        remark_bytes_len: transfer.remark_bytes().map_or(0, <[u8]>::len) as u64,
        ..CitizenSdkFinalizedTransferInfo::default()
    }
}

fn checked_count(value: usize, name: &str) -> FfiResult<u32> {
    u32::try_from(value).map_err(|_| FfiError::internal(format!("{name} count exceeds u32")))
}

unsafe fn ensure_copy_destination(
    bytes: &[u8],
    buffer: *mut u8,
    capacity: u64,
    name: &str,
) -> FfiResult<()> {
    let capacity = usize::try_from(capacity)
        .map_err(|_| FfiError::invalid(format!("{name} capacity is too large")))?;
    if bytes.is_empty() || (buffer.is_null() && capacity == 0) {
        return Ok(());
    }
    if buffer.is_null() || capacity < bytes.len() {
        return Err(FfiError::invalid(format!(
            "{name} buffer is null or too small"
        )));
    }
    Ok(())
}

// This mirrors one public two-buffer copy ABI. Keeping all pointer/capacity/
// required-length fields visible makes the preflight-before-write rule
// reviewable at the boundary, just as the three-buffer helper below does.
#[allow(clippy::too_many_arguments)]
unsafe fn copy_pair(
    first: &[u8],
    first_buffer: *mut u8,
    first_capacity: u64,
    first_required: *mut u64,
    second: &[u8],
    second_buffer: *mut u8,
    second_capacity: u64,
    second_required: *mut u64,
) -> FfiResult<()> {
    require_output(first_required, "first_required")?;
    require_output(second_required, "second_required")?;
    ensure_copy_destination(first, first_buffer, first_capacity, "first")?;
    ensure_copy_destination(second, second_buffer, second_capacity, "second")?;
    ptr::write(first_required, first.len() as u64);
    ptr::write(second_required, second.len() as u64);
    if !first.is_empty() && !first_buffer.is_null() {
        ptr::copy_nonoverlapping(first.as_ptr(), first_buffer, first.len());
    }
    if !second.is_empty() && !second_buffer.is_null() {
        ptr::copy_nonoverlapping(second.as_ptr(), second_buffer, second.len());
    }
    Ok(())
}

#[allow(clippy::too_many_arguments)]
unsafe fn copy_three(
    first: &[u8],
    first_buffer: *mut u8,
    first_capacity: u64,
    first_required: *mut u64,
    second: &[u8],
    second_buffer: *mut u8,
    second_capacity: u64,
    second_required: *mut u64,
    third: &[u8],
    third_buffer: *mut u8,
    third_capacity: u64,
    third_required: *mut u64,
) -> FfiResult<()> {
    require_output(first_required, "first_required")?;
    require_output(second_required, "second_required")?;
    require_output(third_required, "third_required")?;
    ensure_copy_destination(first, first_buffer, first_capacity, "first")?;
    ensure_copy_destination(second, second_buffer, second_capacity, "second")?;
    ensure_copy_destination(third, third_buffer, third_capacity, "third")?;
    ptr::write(first_required, first.len() as u64);
    ptr::write(second_required, second.len() as u64);
    ptr::write(third_required, third.len() as u64);
    if !first.is_empty() && !first_buffer.is_null() {
        ptr::copy_nonoverlapping(first.as_ptr(), first_buffer, first.len());
    }
    if !second.is_empty() && !second_buffer.is_null() {
        ptr::copy_nonoverlapping(second.as_ptr(), second_buffer, second.len());
    }
    if !third.is_empty() && !third_buffer.is_null() {
        ptr::copy_nonoverlapping(third.as_ptr(), third_buffer, third.len());
    }
    Ok(())
}

#[cfg(all(
    test,
    feature = "chain",
    feature = "wallet",
    feature = "transactions",
    feature = "history"
))]
#[path = "wallet_abi_tests.rs"]
mod tests;

#[cfg(all(test, not(feature = "chain")))]
mod no_chain_tests {
    use super::*;

    #[test]
    fn chain_symbols_reject_without_dereferencing_host_pointers() {
        // 没有链模块时，无效指针不会被读取；公开符号仍返回统一 Unsupported。
        let unsupported = CitizenSdkErrorCode::Unsupported.as_i32();
        unsafe {
            assert_eq!(citizensdk_get_genesis_hash(0, ptr::null_mut()), unsupported);
            assert_eq!(
                citizensdk_get_finalized_account_balances(
                    0,
                    ptr::null(),
                    u32::MAX,
                    ptr::null_mut()
                ),
                unsupported
            );
            assert_eq!(
                citizensdk_get_finalized_account_balance(0, ptr::null(), ptr::null_mut()),
                unsupported
            );
            assert_eq!(
                citizensdk_get_account_nonce(0, ptr::null(), ptr::null_mut()),
                unsupported
            );
            assert_eq!(
                citizensdk_get_best_fee_snapshot(0, ptr::null_mut()),
                unsupported
            );
            assert_eq!(
                citizensdk_initialize_finalized_history(0, ptr::null(), 0, ptr::null_mut()),
                unsupported
            );
            assert_eq!(
                citizensdk_sync_finalized_history_batch(0, ptr::null(), 0, ptr::null_mut()),
                unsupported
            );
            assert_eq!(
                citizensdk_result_get_fee_snapshot(0, ptr::null_mut()),
                unsupported
            );
        }
    }
}
