//! Typed account and wallet projection for the stable CitizenSDK ABI.
//!
//! Secret inputs are copied synchronously into Rust-owned zeroizing containers
//! before an asynchronous request is accepted. The only secret output is the
//! one-time recovery phrase owned by a prepared-wallet handle. The separate
//! private SDK bridge at the end of this file only lends an account mini-secret
//! synchronously to the SDK-owned native display; it is absent from public
//! headers, ordinary results and application callbacks.

use std::{
    collections::HashMap,
    panic::{catch_unwind, AssertUnwindSafe},
    ptr,
    sync::{
        atomic::{AtomicU64, Ordering},
        Arc, Mutex, MutexGuard, OnceLock,
    },
};

use citizen_sdk_contracts::{
    AccountId32, FinalizedAccountBalance, Modules, SecretBuffer, SigningIntent, SigningTransform,
    WalletAccount, WalletOrigin, WalletProfile, WalletSignMode,
};
#[cfg(feature = "chain")]
use citizen_sdk_engine::BestFeeSnapshot;
use citizen_sdk_engine::{EngineError, PreparedWalletCreation, WalletWordCount};
use zeroize::Zeroizing;

use crate::{
    abi::*,
    accept_and_write, block_to_abi, copy_to_host, copy_view,
    error::{FfiError, FfiResult},
    ffi_status, handles,
    ownership::{self, DefaultAccountChangePayload, ResultPayload, SigningOutcomePayload},
    read_versioned, require_output,
    runtime::NativeRuntime,
    validate_output_versioned, wrong_result, MAX_ABI_INPUT_BYTES,
};

const MAX_WALLET_SECRET_INPUT_BYTES: usize = 1024;
const MAX_WALLET_NAME_BYTES: usize = 1024;
const MAX_ACCOUNT_BATCH: usize = citizen_sdk_contracts::MAX_WALLET_ACCOUNT_INDEX as usize + 1;
const MAX_WALLET_CATALOG_ACCOUNTS: usize = MAX_ACCOUNT_BATCH * 2;

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
        let Some(authorizing) = self.authorizing else {
            return CitizenSdkErrorCode::Internal.as_i32();
        };
        // SAFETY: open 完整验证此 SDK 私有表，阶段租约保证 context 直到 auth 排空都有效。
        unsafe { authorizing(self.context, view_id, host_operation_id) }
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
        let settled = slot
            .callbacks
            .settled
            .ok_or_else(|| FfiError::internal("安全查看 settled 回调缺失"))?;
        // SAFETY: open 已验证函数存在；Core notifying 租约阻止反调 finish 提前释放 context。
        unsafe { settled(slot.callbacks.context, slot.view_id, code as i32) };
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
    let display = slot
        .callbacks
        .display
        .ok_or_else(|| FfiError::internal("安全查看 display 回调缺失"))?;
    let job = Arc::clone(slot);
    crate::requests::execute_private_view(move || {
        // 捕获整个阶段的 Rust panic，不打印秘密或 panic payload；授权 future 不做取消竞速。
        let outcome = catch_unwind(AssertUnwindSafe(|| {
            job.runtime
                .drive(job.core.run_work(|bytes| {
                    // SAFETY: Core 已复核账户/代际/公钥/取消状态，bytes 仅在本次同步调用内有效。
                    let code = unsafe {
                        display(
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
/// Loads the stable, secret-free hot/cold account catalog in its global order.
///
/// # Safety
/// `out_request_id` must be writable for one request identifier.
pub unsafe extern "C" fn citizensdk_get_wallet_state(
    handle: CitizenSdkHandle,
    out_request_id: *mut CitizenSdkRequestId,
) -> i32 {
    #[cfg(not(feature = "wallet"))]
    {
        let _ = (handle, out_request_id);
        ffi_status(|| Err(module_unsupported("wallet")))
    }
    #[cfg(feature = "wallet")]
    {
        ffi_status(|| {
            let runtime = handles::get(handle)?;
            accept_and_write(runtime, out_request_id, move |runtime, _, _| {
                runtime.refresh_provider_capabilities()?;
                let state = runtime.drive(runtime.engine().wallet_state())??;
                Ok(ResultPayload::WalletState(Box::new(state)))
            })
        })
    }
}

#[no_mangle]
/// Imports a public-only cold account from an exact AccountId32.
///
/// # Safety
/// Inputs are borrowed only for this call and `out_request_id` is writable.
pub unsafe extern "C" fn citizensdk_import_cold_account_id(
    handle: CitizenSdkHandle,
    account_id: *const CitizenSdkAccountId,
    name: CitizenSdkBytesView,
    out_request_id: *mut CitizenSdkRequestId,
) -> i32 {
    #[cfg(not(feature = "wallet"))]
    {
        let _ = (handle, account_id, name, out_request_id);
        ffi_status(|| Err(module_unsupported("wallet")))
    }
    #[cfg(feature = "wallet")]
    {
        ffi_status(|| {
            let runtime = handles::get(handle)?;
            let account_id = account_id_from_pointer(account_id, "account_id")?;
            let name = utf8(name, "cold account name", MAX_WALLET_NAME_BYTES)?;
            accept_and_write(runtime, out_request_id, move |runtime, _, _| {
                runtime.refresh_provider_capabilities()?;
                runtime.drive(
                    runtime
                        .engine()
                        .import_cold_wallet_account(account_id, name),
                )??;
                let state = runtime.drive(runtime.engine().wallet_state())??;
                Ok(ResultPayload::WalletState(Box::new(state)))
            })
        })
    }
}

#[no_mangle]
/// Imports a public-only cold account from one canonical CitizenChain SS58 address.
///
/// # Safety
/// Inputs are borrowed only for this call and `out_request_id` is writable.
pub unsafe extern "C" fn citizensdk_import_cold_account_ss58(
    handle: CitizenSdkHandle,
    ss58_address: CitizenSdkBytesView,
    name: CitizenSdkBytesView,
    out_request_id: *mut CitizenSdkRequestId,
) -> i32 {
    #[cfg(not(feature = "wallet"))]
    {
        let _ = (handle, ss58_address, name, out_request_id);
        ffi_status(|| Err(module_unsupported("wallet")))
    }
    #[cfg(feature = "wallet")]
    {
        ffi_status(|| {
            let runtime = handles::get(handle)?;
            let ss58_address = utf8(ss58_address, "cold account SS58", 64)?;
            let name = utf8(name, "cold account name", MAX_WALLET_NAME_BYTES)?;
            accept_and_write(runtime, out_request_id, move |runtime, _, _| {
                runtime.refresh_provider_capabilities()?;
                runtime.drive(runtime.engine().import_cold_wallet_ss58(ss58_address, name))??;
                let state = runtime.drive(runtime.engine().wallet_state())??;
                Ok(ResultPayload::WalletState(Box::new(state)))
            })
        })
    }
}

#[no_mangle]
/// Reorders the complete account catalog without changing its first/default item.
///
/// # Safety
/// `account_ids` contains `account_count` readable entries and the output is writable.
pub unsafe extern "C" fn citizensdk_reorder_wallet_accounts_without_default_change(
    handle: CitizenSdkHandle,
    expected_revision: u64,
    account_ids: *const CitizenSdkAccountId,
    account_count: u32,
    out_request_id: *mut CitizenSdkRequestId,
) -> i32 {
    #[cfg(not(feature = "wallet"))]
    {
        let _ = (
            handle,
            expected_revision,
            account_ids,
            account_count,
            out_request_id,
        );
        ffi_status(|| Err(module_unsupported("wallet")))
    }
    #[cfg(feature = "wallet")]
    {
        ffi_status(|| {
            let runtime = handles::get(handle)?;
            let account_ids = copy_wallet_catalog_account_ids(account_ids, account_count)?;
            accept_and_write(runtime, out_request_id, move |runtime, _, _| {
                runtime.refresh_provider_capabilities()?;
                let state = runtime.drive(
                    runtime
                        .engine()
                        .reorder_wallet_accounts_without_default_change(
                            expected_revision,
                            account_ids,
                        ),
                )??;
                Ok(ResultPayload::WalletState(Box::new(state)))
            })
        })
    }
}

#[no_mangle]
/// Renames either a hot or cold account through one public operation.
///
/// # Safety
/// Inputs are borrowed only for this call and `out_request_id` is writable.
pub unsafe extern "C" fn citizensdk_rename_account(
    handle: CitizenSdkHandle,
    account_id: *const CitizenSdkAccountId,
    name: CitizenSdkBytesView,
    out_request_id: *mut CitizenSdkRequestId,
) -> i32 {
    #[cfg(not(feature = "wallet"))]
    {
        let _ = (handle, account_id, name, out_request_id);
        ffi_status(|| Err(module_unsupported("wallet")))
    }
    #[cfg(feature = "wallet")]
    {
        ffi_status(|| {
            let runtime = handles::get(handle)?;
            let account_id = account_id_from_pointer(account_id, "account_id")?;
            let name = utf8(name, "wallet account name", MAX_WALLET_NAME_BYTES)?;
            accept_and_write(runtime, out_request_id, move |runtime, _, _| {
                runtime.refresh_provider_capabilities()?;
                let state = runtime
                    .drive(runtime.engine().rename_wallet_account_any(account_id, name))??;
                Ok(ResultPayload::WalletState(Box::new(state)))
            })
        })
    }
}

#[no_mangle]
/// Deletes either a hot or cold account while preserving each mode's safety rules.
///
/// # Safety
/// `account_id` and `out_request_id` must be readable/writable respectively.
pub unsafe extern "C" fn citizensdk_delete_account(
    handle: CitizenSdkHandle,
    account_id: *const CitizenSdkAccountId,
    out_request_id: *mut CitizenSdkRequestId,
) -> i32 {
    #[cfg(not(feature = "wallet"))]
    {
        let _ = (handle, account_id, out_request_id);
        ffi_status(|| Err(module_unsupported("wallet")))
    }
    #[cfg(feature = "wallet")]
    {
        ffi_status(|| {
            let runtime = handles::get(handle)?;
            let account_id = account_id_from_pointer(account_id, "account_id")?;
            accept_and_write(runtime, out_request_id, move |runtime, _, _| {
                runtime.refresh_provider_capabilities()?;
                let state =
                    runtime.drive(runtime.engine().delete_wallet_account_any(account_id))??;
                Ok(ResultPayload::WalletState(Box::new(state)))
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

#[no_mangle]
/// Derives one 32-byte application key from an SDK-owned hot account.
///
/// `salt` and `info` are opaque application domains. The result remains in a zeroizing owned
/// result until the caller copies it once and releases the result handle.
///
/// # Safety
/// Input views and `out_request_id` must satisfy their ordinary ABI contracts.
pub unsafe extern "C" fn citizensdk_derive_application_key(
    handle: CitizenSdkHandle,
    account_id: *const CitizenSdkAccountId,
    salt: CitizenSdkBytesView,
    info: CitizenSdkBytesView,
    out_request_id: *mut CitizenSdkRequestId,
) -> i32 {
    #[cfg(not(all(feature = "wallet", feature = "signing")))]
    {
        let _ = (handle, account_id, salt, info, out_request_id);
        ffi_status(|| {
            Err(FfiError::new(
                CitizenSdkErrorCode::Unsupported,
                "当前构建不包含所需模块",
            ))
        })
    }
    #[cfg(all(feature = "wallet", feature = "signing"))]
    {
        ffi_status(|| {
            let runtime = handles::get(handle)?;
            let account_id = account_id_from_pointer(account_id, "account_id")?;
            let salt: [u8; 32] = copy_view(salt, "application key salt", 32)?
                .try_into()
                .map_err(|_| FfiError::invalid("application key salt must be 32 bytes"))?;
            let info = copy_view(info, "application key info", 256)?;
            if info.is_empty() {
                return Err(FfiError::invalid(
                    "application key info must contain 1..256 bytes",
                ));
            }
            accept_and_write(runtime, out_request_id, move |runtime, _, _| {
                runtime.refresh_provider_capabilities()?;
                let key = runtime.drive(
                    runtime
                        .engine()
                        .derive_application_key(account_id, salt, info),
                )??;
                Ok(ResultPayload::ApplicationKey(Arc::new(key)))
            })
        })
    }
}

fn signing_transform(kind: u32, domain: Vec<u8>) -> FfiResult<SigningTransform> {
    match kind {
        value if value == CitizenSdkSigningTransform::Raw as u32 => {
            if !domain.is_empty() {
                return Err(FfiError::invalid("raw transform 不接受 domain"));
            }
            Ok(SigningTransform::Raw)
        }
        value if value == CitizenSdkSigningTransform::SubstrateSigningPayload as u32 => {
            if !domain.is_empty() {
                return Err(FfiError::invalid(
                    "substrate signing payload transform 不接受 domain",
                ));
            }
            Ok(SigningTransform::SubstrateSigningPayload)
        }
        value if value == CitizenSdkSigningTransform::Blake2Domain as u32 => {
            let transform = SigningTransform::Blake2Domain(domain);
            transform.validate().map_err(FfiError::from)?;
            Ok(transform)
        }
        _ => Err(FfiError::invalid("未知 signing transform")),
    }
}

fn external_transport(value: u32) -> FfiResult<CitizenSdkExternalSignerTransport> {
    match value {
        0 => Ok(CitizenSdkExternalSignerTransport::None),
        1 => Ok(CitizenSdkExternalSignerTransport::QrV1),
        _ => Err(FfiError::invalid("未知 external signer transport")),
    }
}

#[no_mangle]
/// Starts one product-independent signing intent and routes it from stored WalletState.
///
/// # Safety
/// All input views are borrowed only for this call; `out_request_id` must be writable.
#[allow(clippy::too_many_arguments)]
pub unsafe extern "C" fn citizensdk_begin_signing(
    handle: CitizenSdkHandle,
    account_id: *const CitizenSdkAccountId,
    payload: CitizenSdkBytesView,
    transform: u32,
    domain: CitizenSdkBytesView,
    external_signer_transport: u32,
    opaque_action: u16,
    ttl_seconds: u64,
    out_request_id: *mut CitizenSdkRequestId,
) -> i32 {
    #[cfg(not(all(feature = "wallet", feature = "signing")))]
    {
        let _ = (
            handle,
            account_id,
            payload,
            transform,
            domain,
            external_signer_transport,
            opaque_action,
            ttl_seconds,
            out_request_id,
        );
        ffi_status(|| Err(module_unsupported("wallet signing")))
    }
    #[cfg(all(feature = "wallet", feature = "signing"))]
    {
        ffi_status(|| {
            let runtime = handles::get(handle)?;
            let account_id = account_id_from_pointer(account_id, "account_id")?;
            let payload = copy_view(payload, "opaque signing payload", MAX_ABI_INPUT_BYTES)?;
            let domain = copy_view(
                domain,
                "signing domain",
                citizen_sdk_contracts::MAX_SIGNING_DOMAIN_BYTES,
            )?;
            let transform = signing_transform(transform, domain)?;
            let transport = external_transport(external_signer_transport)?;
            if ttl_seconds == 0
                || ttl_seconds > citizen_sdk_contracts::MAX_EXTERNAL_SIGNING_TTL_SECONDS
            {
                return Err(FfiError::invalid("signing ttl 必须位于 1..300 秒"));
            }
            let intent = SigningIntent::try_new(account_id, payload, transform)?;
            accept_and_write(runtime, out_request_id, move |runtime, _, _| {
                runtime.refresh_provider_capabilities()?;
                let mode = runtime
                    .drive(runtime.engine().wallet_account_sign_mode(account_id))??
                    .ok_or_else(|| {
                        FfiError::new(CitizenSdkErrorCode::NotFound, "签名账户不存在")
                    })?;
                match mode {
                    WalletSignMode::Hot => {
                        let completion =
                            runtime.drive(runtime.engine().sign_wallet_intent(intent))??;
                        Ok(ResultPayload::SigningOutcome(
                            SigningOutcomePayload::Completed(completion),
                        ))
                    }
                    WalletSignMode::Cold => {
                        if transport != CitizenSdkExternalSignerTransport::QrV1 {
                            return Err(FfiError::new(
                                CitizenSdkErrorCode::Unsupported,
                                "冷账户需要明确选择可用 external signer transport",
                            ));
                        }
                        #[cfg(not(feature = "qr"))]
                        {
                            let _ = (opaque_action, ttl_seconds, intent);
                            Err(module_unsupported("qr external signer transport"))
                        }
                        #[cfg(feature = "qr")]
                        {
                            if !runtime.has_modules(Modules::QR) {
                                return Err(FfiError::new(
                                    CitizenSdkErrorCode::Unsupported,
                                    "实例没有 QR external signer transport",
                                ));
                            }
                            let pending = crate::qr_abi::create_external_qr_session(
                                handle,
                                opaque_action,
                                &intent,
                                ttl_seconds,
                            )?;
                            Ok(ResultPayload::SigningOutcome(
                                SigningOutcomePayload::ExternalPending(pending),
                            ))
                        }
                    }
                }
            })
        })
    }
}

#[no_mangle]
/// Accepts and verifies one response for the exact instance-local external signing session.
///
/// # Safety
/// Text views are borrowed only for this call; `out_request_id` must be writable.
pub unsafe extern "C" fn citizensdk_consume_external_signature(
    handle: CitizenSdkHandle,
    session_id: CitizenSdkBytesView,
    response: CitizenSdkBytesView,
    out_request_id: *mut CitizenSdkRequestId,
) -> i32 {
    #[cfg(not(feature = "qr"))]
    {
        let _ = (handle, session_id, response, out_request_id);
        ffi_status(|| Err(module_unsupported("qr external signer transport")))
    }
    #[cfg(feature = "qr")]
    {
        ffi_status(|| {
            let runtime = handles::get(handle)?;
            if !runtime.has_modules(Modules::QR) {
                return Err(FfiError::new(
                    CitizenSdkErrorCode::Unsupported,
                    "实例没有 QR external signer transport",
                ));
            }
            let session_id = utf8(session_id, "signing session_id", 128)?;
            let response = utf8(
                response,
                "external signing response",
                citizen_sdk_qr::MAX_QR_TEXT_BYTES,
            )?;
            accept_and_write(runtime, out_request_id, move |_, _, _| {
                let completion =
                    crate::qr_abi::consume_external_qr_session(handle, &session_id, &response)?;
                Ok(ResultPayload::SigningOutcome(
                    SigningOutcomePayload::Completed(completion),
                ))
            })
        })
    }
}

#[no_mangle]
/// Cancels an unconsumed unified signing or default-account external session.
///
/// # Safety
/// `session_id` is borrowed and `out_cancelled` must be writable for one byte.
pub unsafe extern "C" fn citizensdk_cancel_signing_session(
    handle: CitizenSdkHandle,
    session_id: CitizenSdkBytesView,
    out_cancelled: *mut u8,
) -> i32 {
    #[cfg(not(feature = "qr"))]
    {
        let _ = (handle, session_id, out_cancelled);
        ffi_status(|| Err(module_unsupported("qr external signer transport")))
    }
    #[cfg(feature = "qr")]
    {
        ffi_status(|| {
            let runtime = handles::get(handle)?;
            if !runtime.has_modules(Modules::QR) {
                return Err(FfiError::new(
                    CitizenSdkErrorCode::Unsupported,
                    "实例没有 QR external signer transport",
                ));
            }
            require_output(out_cancelled, "out_cancelled")?;
            let session_id = utf8(session_id, "signing session_id", 128)?;
            let cancelled = crate::qr_abi::cancel_unified_signing_session(handle, &session_id)?;
            ptr::write(out_cancelled, u8::from(cancelled));
            Ok(())
        })
    }
}

#[no_mangle]
/// Starts the SDK-owned default-account mutation. The original default account authorizes the
/// full order through the same hot/external signing core; callers cannot choose its signer/action.
///
/// # Safety
/// The account array is borrowed only for this call and the request output must be writable.
pub unsafe extern "C" fn citizensdk_begin_default_account_change(
    handle: CitizenSdkHandle,
    expected_revision: u64,
    account_ids: *const CitizenSdkAccountId,
    account_count: u32,
    ttl_seconds: u64,
    out_request_id: *mut CitizenSdkRequestId,
) -> i32 {
    #[cfg(not(all(feature = "wallet", feature = "signing")))]
    {
        let _ = (
            handle,
            expected_revision,
            account_ids,
            account_count,
            ttl_seconds,
            out_request_id,
        );
        ffi_status(|| Err(module_unsupported("wallet signing")))
    }
    #[cfg(all(feature = "wallet", feature = "signing"))]
    {
        ffi_status(|| {
            let runtime = handles::get(handle)?;
            let account_ids = copy_wallet_catalog_account_ids(account_ids, account_count)?;
            accept_and_write(runtime, out_request_id, move |runtime, _, _| {
                runtime.refresh_provider_capabilities()?;
                let authorization =
                    runtime.drive(runtime.engine().prepare_default_wallet_account_change(
                        expected_revision,
                        account_ids,
                        ttl_seconds,
                    ))??;
                let current = authorization.current_default_account_id();
                let payload_hash = authorization.signing_intent()?.payload_hash()?;
                let mode = runtime
                    .drive(runtime.engine().wallet_account_sign_mode(current))??
                    .ok_or_else(|| {
                        FfiError::new(
                            CitizenSdkErrorCode::Conflict,
                            "原默认账户在授权路由前已经消失",
                        )
                    })?;
                match mode {
                    WalletSignMode::Hot => {
                        let state = runtime.drive(
                            runtime
                                .engine()
                                .authorize_hot_default_wallet_account_change(authorization),
                        )??;
                        Ok(ResultPayload::DefaultAccountChange(
                            DefaultAccountChangePayload::Completed {
                                current_default_account_id: current,
                                payload_hash,
                                committed_revision: state.revision(),
                            },
                        ))
                    }
                    WalletSignMode::Cold => {
                        #[cfg(not(feature = "qr"))]
                        {
                            let _ = authorization;
                            Err(module_unsupported("qr external signer transport"))
                        }
                        #[cfg(feature = "qr")]
                        {
                            if !runtime.has_modules(Modules::QR) {
                                return Err(FfiError::new(
                                    CitizenSdkErrorCode::Unsupported,
                                    "冷默认账户需要 QR external signer transport",
                                ));
                            }
                            let pending = crate::qr_abi::create_default_account_qr_session(
                                handle,
                                authorization,
                            )?;
                            Ok(ResultPayload::DefaultAccountChange(
                                DefaultAccountChangePayload::ExternalPending(pending),
                            ))
                        }
                    }
                }
            })
        })
    }
}

#[no_mangle]
/// Verifies a cold default-account response and performs the exact revision/account-set CAS.
///
/// # Safety
/// Text views are borrowed only for this call; `out_request_id` must be writable.
pub unsafe extern "C" fn citizensdk_consume_default_account_change(
    handle: CitizenSdkHandle,
    session_id: CitizenSdkBytesView,
    response: CitizenSdkBytesView,
    out_request_id: *mut CitizenSdkRequestId,
) -> i32 {
    #[cfg(not(all(feature = "wallet", feature = "signing", feature = "qr")))]
    {
        let _ = (handle, session_id, response, out_request_id);
        ffi_status(|| Err(module_unsupported("wallet QR signing")))
    }
    #[cfg(all(feature = "wallet", feature = "signing", feature = "qr"))]
    {
        ffi_status(|| {
            let runtime = handles::get(handle)?;
            if !runtime.has_modules(Modules::QR) {
                return Err(FfiError::new(
                    CitizenSdkErrorCode::Unsupported,
                    "实例没有 QR external signer transport",
                ));
            }
            let session_id = utf8(session_id, "default change session_id", 128)?;
            let response = utf8(
                response,
                "default change response",
                citizen_sdk_qr::MAX_QR_TEXT_BYTES,
            )?;
            accept_and_write(runtime, out_request_id, move |runtime, _, _| {
                let (authorization, signature) = crate::qr_abi::consume_default_account_qr_session(
                    handle,
                    &session_id,
                    &response,
                )?;
                let current = authorization.current_default_account_id();
                let payload_hash = authorization.signing_intent()?.payload_hash()?;
                let state = runtime.drive(
                    runtime
                        .engine()
                        .commit_default_wallet_account_change(&authorization, signature),
                )??;
                Ok(ResultPayload::DefaultAccountChange(
                    DefaultAccountChangePayload::Completed {
                        current_default_account_id: current,
                        payload_hash,
                        committed_revision: state.revision(),
                    },
                ))
            })
        })
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
        let profile = match &owned.payload {
            ResultPayload::WalletProfile(profile) => profile.as_ref(),
            ResultPayload::WalletState(state) => state.profile(),
            _ => return Err(wrong_result("wallet profile or wallet state")),
        };
        ptr::write(out_info, wallet_profile_to_abi(profile)?);
        Ok(())
    })
}

#[no_mangle]
/// Copies the fixed portion of one unified wallet-state result.
///
/// # Safety
/// `out_info` must contain a supported ABI prefix and be writable.
pub unsafe extern "C" fn citizensdk_result_get_wallet_state(
    result: CitizenSdkResultHandle,
    out_info: *mut CitizenSdkWalletStateInfo,
) -> i32 {
    ffi_status(|| {
        validate_output_versioned(out_info, "wallet state info")?;
        let owned = ownership::get(result)?;
        let ResultPayload::WalletState(state) = &owned.payload else {
            return Err(wrong_result("wallet state"));
        };
        ptr::write(
            out_info,
            CitizenSdkWalletStateInfo {
                revision: state.revision(),
                account_count: checked_count(
                    state.ordered_account_ids().len(),
                    "wallet state account",
                )?,
                has_default_account: u32::from(state.default_account_id().is_some()),
                default_account_id: state
                    .default_account_id()
                    .map(account_id_to_abi)
                    .unwrap_or_default(),
                ..CitizenSdkWalletStateInfo::default()
            },
        );
        Ok(())
    })
}

#[no_mangle]
/// Copies one generic signing outcome with all variable outputs preflighted before any write.
///
/// # Safety
/// `out_info` is versioned/writable and all buffer/required pairs follow the public copy contract.
#[allow(clippy::too_many_arguments)]
pub unsafe extern "C" fn citizensdk_result_get_signing_outcome(
    result: CitizenSdkResultHandle,
    out_info: *mut CitizenSdkSigningOutcomeInfo,
    signature_buffer: *mut u8,
    signature_capacity: u64,
    out_signature_required: *mut u64,
    session_id_buffer: *mut u8,
    session_id_capacity: u64,
    out_session_id_required: *mut u64,
    transport_request_buffer: *mut u8,
    transport_request_capacity: u64,
    out_transport_request_required: *mut u64,
) -> i32 {
    ffi_status(|| {
        validate_output_versioned(out_info, "signing outcome info")?;
        let owned = ownership::get(result)?;
        let ResultPayload::SigningOutcome(outcome) = &owned.payload else {
            return Err(wrong_result("signing outcome"));
        };
        let (info, signature, session_id, transport_request) = match outcome {
            SigningOutcomePayload::Completed(completion) => (
                CitizenSdkSigningOutcomeInfo {
                    status: CitizenSdkSigningOutcomeStatus::Completed as u32,
                    transport: CitizenSdkExternalSignerTransport::None as u32,
                    account_id: account_id_to_abi(completion.account_id()),
                    payload_hash: completion.payload_hash().into_bytes(),
                    signature_len: 64,
                    ..CitizenSdkSigningOutcomeInfo::default()
                },
                completion.signature_bytes().as_slice(),
                &[][..],
                &[][..],
            ),
            SigningOutcomePayload::ExternalPending(pending) => (
                CitizenSdkSigningOutcomeInfo {
                    status: CitizenSdkSigningOutcomeStatus::ExternalPending as u32,
                    transport: CitizenSdkExternalSignerTransport::QrV1 as u32,
                    account_id: account_id_to_abi(pending.account_id),
                    payload_hash: pending.payload_hash.into_bytes(),
                    expires_at: pending.expires_at,
                    session_id_len: pending.session_id.len() as u64,
                    transport_request_len: pending.transport_request.len() as u64,
                    ..CitizenSdkSigningOutcomeInfo::default()
                },
                &[][..],
                pending.session_id.as_bytes(),
                pending.transport_request.as_bytes(),
            ),
        };
        copy_three(
            signature,
            signature_buffer,
            signature_capacity,
            out_signature_required,
            session_id,
            session_id_buffer,
            session_id_capacity,
            out_session_id_required,
            transport_request,
            transport_request_buffer,
            transport_request_capacity,
            out_transport_request_required,
        )?;
        ptr::write(out_info, info);
        Ok(())
    })
}

#[no_mangle]
/// Copies an SDK default-account mutation result. Completed results expose the committed revision;
/// pending results expose only the bound external session and request.
///
/// # Safety
/// `out_info` is versioned/writable and both variable buffer pairs follow the copy contract.
#[allow(clippy::too_many_arguments)]
pub unsafe extern "C" fn citizensdk_result_get_default_account_change(
    result: CitizenSdkResultHandle,
    out_info: *mut CitizenSdkDefaultAccountChangeInfo,
    session_id_buffer: *mut u8,
    session_id_capacity: u64,
    out_session_id_required: *mut u64,
    transport_request_buffer: *mut u8,
    transport_request_capacity: u64,
    out_transport_request_required: *mut u64,
) -> i32 {
    ffi_status(|| {
        validate_output_versioned(out_info, "default account change info")?;
        let owned = ownership::get(result)?;
        let ResultPayload::DefaultAccountChange(outcome) = &owned.payload else {
            return Err(wrong_result("default account change"));
        };
        let (info, session_id, transport_request) = match outcome {
            DefaultAccountChangePayload::Completed {
                current_default_account_id,
                payload_hash,
                committed_revision,
            } => (
                CitizenSdkDefaultAccountChangeInfo {
                    status: CitizenSdkSigningOutcomeStatus::Completed as u32,
                    transport: CitizenSdkExternalSignerTransport::None as u32,
                    current_default_account_id: account_id_to_abi(*current_default_account_id),
                    payload_hash: payload_hash.into_bytes(),
                    committed_revision: *committed_revision,
                    ..CitizenSdkDefaultAccountChangeInfo::default()
                },
                &[][..],
                &[][..],
            ),
            DefaultAccountChangePayload::ExternalPending(pending) => (
                CitizenSdkDefaultAccountChangeInfo {
                    status: CitizenSdkSigningOutcomeStatus::ExternalPending as u32,
                    transport: CitizenSdkExternalSignerTransport::QrV1 as u32,
                    current_default_account_id: account_id_to_abi(pending.account_id),
                    payload_hash: pending.payload_hash.into_bytes(),
                    expires_at: pending.expires_at,
                    session_id_len: pending.session_id.len() as u64,
                    transport_request_len: pending.transport_request.len() as u64,
                    ..CitizenSdkDefaultAccountChangeInfo::default()
                },
                pending.session_id.as_bytes(),
                pending.transport_request.as_bytes(),
            ),
        };
        copy_pair(
            session_id,
            session_id_buffer,
            session_id_capacity,
            out_session_id_required,
            transport_request,
            transport_request_buffer,
            transport_request_capacity,
            out_transport_request_required,
        )?;
        ptr::write(out_info, info);
        Ok(())
    })
}

#[no_mangle]
/// Copies one globally ordered hot/cold account and size-queries/copies its labels.
///
/// # Safety
/// Every output pointer follows the documented CitizenSDK copy contract.
#[allow(clippy::too_many_arguments)]
pub unsafe extern "C" fn citizensdk_result_get_wallet_state_account(
    result: CitizenSdkResultHandle,
    index: u32,
    out_info: *mut CitizenSdkWalletStateAccountInfo,
    ss58_buffer: *mut u8,
    ss58_capacity: u64,
    out_ss58_required: *mut u64,
    name_buffer: *mut u8,
    name_capacity: u64,
    out_name_required: *mut u64,
) -> i32 {
    ffi_status(|| {
        validate_output_versioned(out_info, "wallet state account info")?;
        let owned = ownership::get(result)?;
        let ResultPayload::WalletState(state) = &owned.payload else {
            return Err(wrong_result("wallet state"));
        };
        let account_id = state
            .ordered_account_ids()
            .get(index as usize)
            .copied()
            .ok_or_else(|| FfiError::invalid("wallet state account index is out of range"))?;

        let (sign_mode, wallet_index, account_index, created_at_millis, ss58, name) =
            if let Some(account) = state
                .profile()
                .and_then(|profile| profile.account_by_id(account_id))
            {
                (
                    WalletSignMode::Hot,
                    citizen_sdk_contracts::CITIZEN_WALLET_INDEX,
                    Some(account.index()),
                    account.created_at_millis(),
                    account.ss58_address(),
                    account.name(),
                )
            } else if let Some(account) = state.cold_account_by_id(account_id) {
                (
                    WalletSignMode::Cold,
                    account.wallet_index(),
                    None,
                    account.created_at_millis(),
                    account.ss58_address(),
                    account.name(),
                )
            } else {
                return Err(FfiError::new(
                    CitizenSdkErrorCode::Integrity,
                    "wallet order references an unknown account",
                ));
            };

        copy_pair(
            ss58.as_bytes(),
            ss58_buffer,
            ss58_capacity,
            out_ss58_required,
            name.as_bytes(),
            name_buffer,
            name_capacity,
            out_name_required,
        )?;
        ptr::write(
            out_info,
            CitizenSdkWalletStateAccountInfo {
                sign_mode: match sign_mode {
                    WalletSignMode::Hot => CitizenSdkWalletSignMode::Hot,
                    WalletSignMode::Cold => CitizenSdkWalletSignMode::Cold,
                } as u32,
                wallet_index,
                has_account_index: u32::from(account_index.is_some()),
                account_index: account_index.unwrap_or_default(),
                is_default: u32::from(index == 0),
                account_id: account_id_to_abi(account_id),
                created_at_millis,
                ss58_address_len: ss58.len() as u64,
                name_len: name.len() as u64,
                ..CitizenSdkWalletStateAccountInfo::default()
            },
        );
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
/// Copies a 32-byte application key from its zeroizing owned result.
///
/// # Safety
/// `out_key_32` must be writable for exactly 32 bytes. The caller owns and must clear its copy.
pub unsafe extern "C" fn citizensdk_result_get_application_key(
    result: CitizenSdkResultHandle,
    out_key_32: *mut u8,
) -> i32 {
    ffi_status(|| {
        require_output(out_key_32, "out_key_32")?;
        let owned = ownership::get(result)?;
        let ResultPayload::ApplicationKey(key) = owned.payload else {
            return Err(wrong_result("application key"));
        };
        key.with_secret(|bytes| {
            if bytes.len() != 32 {
                return Err(FfiError::internal(
                    "application key result length is not 32 bytes",
                ));
            }
            ptr::copy_nonoverlapping(bytes.as_ptr(), out_key_32, 32);
            Ok(())
        })
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

unsafe fn copy_wallet_catalog_account_ids(
    pointer: *const CitizenSdkAccountId,
    count: u32,
) -> FfiResult<Vec<AccountId32>> {
    let count =
        usize::try_from(count).map_err(|_| FfiError::invalid("account count is too large"))?;
    if count == 0 || count > MAX_WALLET_CATALOG_ACCOUNTS || pointer.is_null() {
        return Err(FfiError::invalid(
            "wallet catalog must contain between 1 and 3980 accounts",
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
                citizensdk_get_transaction_history(0, ptr::null(), 100, ptr::null_mut()),
                unsupported
            );
            assert_eq!(
                citizensdk_sync_transaction_history(0, ptr::null_mut()),
                unsupported
            );
            assert_eq!(
                citizensdk_result_get_fee_snapshot(0, ptr::null_mut()),
                unsupported
            );
        }
    }
}
