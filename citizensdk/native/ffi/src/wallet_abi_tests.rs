// 仅在测试中要求定时器及预期错误成立；生产 ABI 不以 panic 处理业务错误。
#![allow(clippy::expect_used)]

use super::{
    claim_prepared_wallet, copy_pair, lock_prepared_wallets, next_prepared_wallet_handle,
    require_prepared_owner, secret_utf8, u128_from_abi, u128_to_abi, wallet_profile_to_abi,
    wallet_transfer_or_cancellation, wallet_transfer_watch_event, wallet_word_count,
    PreparedWalletSlot,
};
use crate::abi::{
    CitizenSdkBytesView, CitizenSdkErrorCode, CitizenSdkU128, CitizenSdkWalletWordCount,
};
use citizen_sdk_contracts::{ExecutionConclusion, ExtrinsicWatchEvent, Hash32, VerifiedBlockRef};
use citizen_sdk_engine::{
    EngineError, WalletTransferCancellation, WalletTransferWatchResult, WalletTransferWatchStage,
};
use futures_util::FutureExt;
use std::{
    future::Future,
    pin::Pin,
    sync::{
        atomic::{AtomicBool, Ordering},
        Arc,
    },
    task::{Context, Poll},
};

struct PendingWalletTransfer {
    dropped: Arc<AtomicBool>,
    release: futures_channel::oneshot::Receiver<()>,
    completed: Arc<AtomicBool>,
}

impl Future for PendingWalletTransfer {
    type Output = Result<WalletTransferWatchResult, EngineError>;

    fn poll(mut self: Pin<&mut Self>, context: &mut Context<'_>) -> Poll<Self::Output> {
        match Pin::new(&mut self.release).poll(context) {
            Poll::Pending => Poll::Pending,
            Poll::Ready(_) => {
                self.completed.store(true, Ordering::SeqCst);
                Poll::Ready(Err(EngineError::StatePoisoned))
            }
        }
    }
}

impl Drop for PendingWalletTransfer {
    fn drop(&mut self) {
        self.dropped.store(true, Ordering::SeqCst);
    }
}

fn chain_query_runtime() -> Arc<crate::runtime::NativeRuntime> {
    let assets = crate::assets::verify_assets(
        include_bytes!("../../../assets/citizenchain/manifest.json"),
        include_bytes!("../../../assets/citizenchain/chainspec.json"),
        include_bytes!("../../../assets/citizenchain/light_sync_state.json"),
    )
    .expect("chain assets");
    let runtime = unsafe {
        crate::runtime::NativeRuntime::new_with_modules(
            crate::handles::reserve_handle().expect("handle"),
            Some(assets.combined_chain_spec),
            "CitizenSDK-query-test".to_owned(),
            "1.0.0".to_owned(),
            None,
            citizen_sdk_contracts::Modules::try_new(citizen_sdk_contracts::Modules::CHAIN)
                .expect("chain module"),
        )
    }
    .expect("chain-only runtime");
    crate::handles::insert(Arc::clone(&runtime)).expect("instance registry");
    runtime
}

unsafe extern "C" fn chain_query_event(
    context: *mut std::ffi::c_void,
    event: *const crate::abi::CitizenSdkEvent,
) {
    // 测试持有 channel 到 dispatcher 关闭；只复制公开完成事件，不借用事件指针。
    let sender =
        unsafe { &*context.cast::<std::sync::mpsc::Sender<crate::abi::CitizenSdkEvent>>() };
    let event = unsafe { *event };
    if event.event_type == crate::abi::CitizenSdkEventType::RequestCompleted as u32 {
        let _ = sender.send(event);
    }
}

#[test]
fn chain_query_inputs_and_static_genesis_are_validated_without_starting_provider() {
    use crate::abi::CitizenSdkAccountId;
    let runtime = chain_query_runtime();
    let handle = runtime.handle();
    let mut genesis = [0xa5; 33];
    let mut request = 999;
    let account = CitizenSdkAccountId { bytes: [0x55; 32] };
    unsafe {
        assert_eq!(
            super::citizensdk_get_genesis_hash(handle, genesis.as_mut_ptr()),
            0
        );
        assert_eq!(
            &genesis[..32],
            citizen_sdk_contracts::ChainIdentity::citizenchain()
                .genesis_hash()
                .as_bytes()
        );
        assert_eq!(genesis[32], 0xa5);
        assert_eq!(
            super::citizensdk_get_genesis_hash(handle, std::ptr::null_mut()),
            CitizenSdkErrorCode::InvalidArgument.as_i32()
        );
        assert_eq!(
            super::citizensdk_get_genesis_hash(0, genesis.as_mut_ptr()),
            CitizenSdkErrorCode::InvalidHandle.as_i32()
        );
        for count in [1991, u32::MAX] {
            assert_eq!(
                super::citizensdk_get_finalized_account_balances(
                    handle,
                    &account,
                    count,
                    &mut request
                ),
                CitizenSdkErrorCode::InvalidArgument.as_i32()
            );
            assert_eq!(request, 999);
        }
        assert_eq!(
            super::citizensdk_get_finalized_account_balances(
                handle,
                std::ptr::null(),
                1,
                &mut request
            ),
            CitizenSdkErrorCode::InvalidArgument.as_i32()
        );
        assert_eq!(
            super::citizensdk_get_finalized_account_balances(
                handle,
                std::ptr::null(),
                0,
                std::ptr::null_mut()
            ),
            CitizenSdkErrorCode::InvalidArgument.as_i32()
        );
        assert_eq!(
            super::citizensdk_get_finalized_account_balances(0, std::ptr::null(), 0, &mut request),
            CitizenSdkErrorCode::InvalidHandle.as_i32()
        );
        assert_eq!(crate::citizensdk_destroy(handle), 0);
        assert_eq!(
            super::citizensdk_get_genesis_hash(handle, genesis.as_mut_ptr()),
            CitizenSdkErrorCode::InvalidHandle.as_i32()
        );
        assert_eq!(
            super::citizensdk_get_finalized_account_balances(
                handle,
                std::ptr::null(),
                0,
                &mut request
            ),
            CitizenSdkErrorCode::InvalidHandle.as_i32()
        );
    }
}

#[test]
fn empty_batch_is_accepted_but_cannot_bypass_engine_running_gate() {
    let runtime = chain_query_runtime();
    let (sender, receiver) = std::sync::mpsc::channel::<crate::abi::CitizenSdkEvent>();
    let mut sender = Box::new(sender);
    runtime
        .set_event_callback(
            Some(chain_query_event),
            (&mut *sender as *mut std::sync::mpsc::Sender<crate::abi::CitizenSdkEvent>).cast(),
        )
        .expect("callback");
    let mut request = 0;
    unsafe {
        assert_eq!(
            super::citizensdk_get_finalized_account_balances(
                runtime.handle(),
                std::ptr::null(),
                0,
                &mut request
            ),
            0
        );
    }
    let event = receiver
        .recv_timeout(std::time::Duration::from_secs(2))
        .expect("query completion");
    assert_eq!(event.request_id, request);
    let result = crate::ownership::get(event.result).expect("query result");
    assert_eq!(result.code, CitizenSdkErrorCode::NotReady);
    assert!(matches!(
        result.payload,
        crate::ownership::ResultPayload::Empty
    ));
    unsafe {
        assert_eq!(
            crate::citizensdk_destroy(runtime.handle()),
            CitizenSdkErrorCode::Busy.as_i32()
        );
        assert_eq!(crate::citizensdk_result_release(event.result), 0);
        assert_eq!(crate::citizensdk_destroy(runtime.handle()), 0);
    }
}

#[test]
fn finite_batch_admission_rejects_cancel_and_close_until_request_and_result_drain() {
    let runtime = chain_query_runtime();
    let (sender, receiver) = std::sync::mpsc::channel::<crate::abi::CitizenSdkEvent>();
    let mut sender = Box::new(sender);
    runtime
        .set_event_callback(
            Some(chain_query_event),
            (&mut *sender as *mut std::sync::mpsc::Sender<crate::abi::CitizenSdkEvent>).cast(),
        )
        .expect("callback");
    let (entered_tx, entered_rx) = std::sync::mpsc::channel();
    let (release_tx, release_rx) = std::sync::mpsc::channel();
    let mut request = 0;
    // 与公开批量入口共用唯一 finite admission；barrier 让取消/销毁断言不依赖竞速。
    unsafe {
        super::accept_and_write(
            Arc::clone(&runtime),
            &mut request,
            move |_, _, cancellation| {
                assert!(cancellation.is_none());
                entered_tx.send(()).expect("entered");
                release_rx
                    .recv_timeout(std::time::Duration::from_secs(2))
                    .expect("release");
                Ok(crate::ownership::ResultPayload::AccountBalances(Vec::new()))
            },
        )
        .expect("finite acceptance");
    }
    entered_rx
        .recv_timeout(std::time::Duration::from_secs(2))
        .expect("pending batch");
    unsafe {
        assert_eq!(
            crate::citizensdk_cancel_request(runtime.handle(), request),
            CitizenSdkErrorCode::Unsupported.as_i32()
        );
        assert_eq!(
            crate::citizensdk_destroy(runtime.handle()),
            CitizenSdkErrorCode::Busy.as_i32()
        );
    }
    release_tx.send(()).expect("release pending batch");
    let event = receiver
        .recv_timeout(std::time::Duration::from_secs(2))
        .expect("batch completion");
    assert_eq!(event.request_id, request);
    let mut count = u32::MAX;
    unsafe {
        assert_eq!(
            super::citizensdk_result_get_account_balance_count(event.result, &mut count),
            0
        );
        assert_eq!(count, 0);
        assert_eq!(
            crate::citizensdk_destroy(runtime.handle()),
            CitizenSdkErrorCode::Busy.as_i32()
        );
        assert_eq!(crate::citizensdk_result_release(event.result), 0);
        assert_eq!(crate::citizensdk_destroy(runtime.handle()), 0);
    }
    assert!(
        receiver.try_recv().is_err(),
        "finite batch completes exactly once"
    );
}

#[test]
fn batch_result_projection_preserves_order_u128_and_checks_type_size_bounds_and_release() {
    use crate::{
        abi::CitizenSdkAccountBalanceInfo,
        ownership::{self, OwnedResult, ResultPayload},
    };
    use citizen_sdk_contracts::{
        AccountId32, ChainIdentity, FinalizedAccountBalance, FinalizedBlockRef,
    };
    let block = FinalizedBlockRef::from_parts(Hash32::from_bytes([0xaa; 32]), 77);
    let first = FinalizedAccountBalance::try_new(
        &ChainIdentity::citizenchain(),
        block,
        AccountId32::from_bytes([0x55; 32]),
        u128::MAX,
        0,
    )
    .expect("first balance");
    let second = FinalizedAccountBalance::try_new(
        &ChainIdentity::citizenchain(),
        block,
        AccountId32::from_bytes([0x44; 32]),
        7,
        9,
    )
    .expect("second balance");
    let result = ownership::insert(OwnedResult::success(
        0,
        ResultPayload::AccountBalances(vec![first, second, first]),
    ))
    .expect("batch result");
    let wrong = ownership::insert(OwnedResult::success(
        0,
        ResultPayload::AccountBalance(first),
    ))
    .expect("single result");
    let mut count = 999;
    let mut info = CitizenSdkAccountBalanceInfo::default();
    unsafe {
        assert_eq!(
            super::citizensdk_result_get_account_balance_count(result, &mut count),
            0
        );
        assert_eq!(count, 3);
        assert_eq!(
            super::citizensdk_result_get_account_balance_count(result, std::ptr::null_mut()),
            CitizenSdkErrorCode::InvalidArgument.as_i32()
        );
        for (index, balance) in [first, second, first].into_iter().enumerate() {
            assert_eq!(
                super::citizensdk_result_get_account_balance_at(result, index as u32, &mut info),
                0
            );
            assert_eq!(info, super::account_balance_to_abi(balance));
        }
        let unchanged = info;
        for index in [3, u32::MAX] {
            assert_eq!(
                super::citizensdk_result_get_account_balance_at(result, index, &mut info),
                CitizenSdkErrorCode::InvalidArgument.as_i32()
            );
            assert_eq!(info, unchanged);
        }
        assert_eq!(
            super::citizensdk_result_get_account_balance_at(result, 0, std::ptr::null_mut()),
            CitizenSdkErrorCode::InvalidArgument.as_i32()
        );
        info.struct_size -= 1;
        let too_short = info;
        assert_eq!(
            super::citizensdk_result_get_account_balance_at(result, 0, &mut info),
            CitizenSdkErrorCode::InvalidArgument.as_i32()
        );
        assert_eq!(info, too_short);
        info = unchanged;
        info.abi_version += 1;
        assert_eq!(
            super::citizensdk_result_get_account_balance_at(result, 0, &mut info),
            CitizenSdkErrorCode::Unsupported.as_i32()
        );
        info = unchanged;
        count = 999;
        assert_ne!(
            super::citizensdk_result_get_account_balance_count(wrong, &mut count),
            0
        );
        assert_eq!(count, 999);
        assert_ne!(
            super::citizensdk_result_get_account_balance_at(wrong, 0, &mut info),
            0
        );
        assert_eq!(info, unchanged);
        assert_ne!(
            super::citizensdk_result_get_account_balance(result, &mut info),
            0
        );
    }
    ownership::release(wrong).expect("release single");
    ownership::release(result).expect("release batch");
    unsafe {
        assert_eq!(
            super::citizensdk_result_get_account_balance_at(result, 0, &mut info),
            CitizenSdkErrorCode::InvalidHandle.as_i32()
        );
        assert_eq!(
            super::citizensdk_result_get_account_balance_count(0, &mut count),
            CitizenSdkErrorCode::InvalidHandle.as_i32()
        );
    }
}

#[test]
fn portable_u128_round_trips_boundary_values() {
    for value in [0, 1, u64::MAX as u128, 1_u128 << 64, u128::MAX] {
        assert_eq!(u128_from_abi(u128_to_abi(value)), value);
    }
    assert_eq!(
        u128_from_abi(CitizenSdkU128 {
            low: 0x0123_4567_89ab_cdef,
            high: 0xfedc_ba98_7654_3210,
        }),
        0xfedc_ba98_7654_3210_0123_4567_89ab_cdef,
    );
}

#[test]
fn wallet_word_count_accepts_only_the_three_supported_values() {
    assert!(wallet_word_count(CitizenSdkWalletWordCount::Words12 as u32).is_ok());
    assert!(wallet_word_count(CitizenSdkWalletWordCount::Words18 as u32).is_ok());
    assert!(wallet_word_count(CitizenSdkWalletWordCount::Words24 as u32).is_ok());
    for invalid in [0, 11, 13, 15, 21, 23, 25, u32::MAX] {
        assert!(wallet_word_count(invalid).is_err());
    }
}

#[test]
fn synchronous_wallet_input_never_needs_a_runtime_or_returns_secrets() {
    fn view(bytes: &[u8]) -> CitizenSdkBytesView {
        CitizenSdkBytesView {
            data: bytes.as_ptr(),
            len: bytes.len() as u64,
        }
    }
    // SAFETY: every input/output buffer remains valid for the entire synchronous call.
    unsafe {
        assert_eq!(super::citizensdk_validate_wallet_password(view(b"")), 0);
        assert_eq!(
            super::citizensdk_validate_wallet_password(view(b"abcdef")),
            0
        );
        for rejected in [b"short".as_slice(), b"abcdef ", &[0xff]] {
            assert_eq!(
                super::citizensdk_validate_wallet_password(view(rejected)),
                CitizenSdkErrorCode::InvalidArgument.as_i32()
            );
        }
        let mut required = u64::MAX;
        assert_eq!(
            super::citizensdk_wallet_word_suggestions(
                view(b"aban"),
                std::ptr::null_mut(),
                0,
                &mut required
            ),
            0
        );
        assert_eq!(required, 7);
        let mut output = [0xa5; 16];
        assert_eq!(
            super::citizensdk_wallet_word_suggestions(
                view(b"aban"),
                output.as_mut_ptr(),
                6,
                &mut required
            ),
            CitizenSdkErrorCode::InvalidArgument.as_i32()
        );
        assert_eq!(output, [0xa5; 16]);
        assert_eq!(required, 7);
        assert_eq!(
            super::citizensdk_wallet_word_suggestions(
                view(b"aban"),
                output.as_mut_ptr(),
                16,
                &mut required
            ),
            0
        );
        assert_eq!(&output[..7], b"abandon");
        assert_eq!(output[7], 0xa5);
        assert_ne!(
            super::citizensdk_wallet_word_suggestions(
                view(b"A"),
                output.as_mut_ptr(),
                16,
                &mut required
            ),
            0
        );
        assert_eq!(required, 0);
        assert_ne!(
            super::citizensdk_wallet_word_suggestions(
                view(b"a"),
                output.as_mut_ptr(),
                16,
                std::ptr::null_mut()
            ),
            0
        );
        assert_ne!(super::citizensdk_validate_wallet_mnemonic(view(b""), 18), 0);
        assert_ne!(super::citizensdk_validate_wallet_mnemonic(view(b""), 15), 0);
    }
}

#[test]
fn invalid_secret_utf8_is_rejected_before_async_acceptance() {
    let bytes = [0xff, 0xfe];
    let view = CitizenSdkBytesView {
        data: bytes.as_ptr(),
        len: bytes.len() as u64,
    };
    // SAFETY: the fixed test array remains readable through the synchronous copy.
    assert!(unsafe { secret_utf8(view, "test secret", bytes.len()) }.is_err());
}

#[test]
fn multi_buffer_copy_validates_every_destination_before_writing_any() {
    let first = b"first";
    let second = b"second";
    let mut first_output = [0xaa; 5];
    let mut second_output = [0xbb; 2];
    let mut first_required = u64::MAX;
    let mut second_required = u64::MAX;
    // SAFETY: all test pointers are valid for their declared capacities. The
    // second capacity is deliberately too small and must fail atomically.
    let result = unsafe {
        copy_pair(
            first,
            first_output.as_mut_ptr(),
            first_output.len() as u64,
            &mut first_required,
            second,
            second_output.as_mut_ptr(),
            second_output.len() as u64,
            &mut second_required,
        )
    };
    assert!(result.is_err());
    assert_eq!(first_output, [0xaa; 5]);
    assert_eq!(second_output, [0xbb; 2]);
    assert_eq!(first_required, u64::MAX);
    assert_eq!(second_required, u64::MAX);
}

#[test]
fn absent_wallet_profile_is_a_successful_zeroed_projection() {
    let info = wallet_profile_to_abi(None)
        .unwrap_or_else(|error| panic!("absent profile projection failed: {error:?}"));
    assert_eq!(info.present, 0);
    assert_eq!(info.origin, 0);
    assert_eq!(info.account_count, 0);
    assert_eq!(info.master_account_id.bytes, [0; 32]);
    assert_eq!(info.active_account_id.bytes, [0; 32]);
}

#[test]
fn prepared_wallet_handles_are_nonzero_monotonic_and_never_reused() {
    let first = next_prepared_wallet_handle()
        .unwrap_or_else(|error| panic!("first prepared handle failed: {error:?}"));
    let second = next_prepared_wallet_handle()
        .unwrap_or_else(|error| panic!("second prepared handle failed: {error:?}"));
    assert_ne!(first, 0);
    assert_eq!(second, first + 1);
}

#[test]
fn prepared_wallet_owner_is_checked_even_while_the_handle_is_claimed() {
    let handle = next_prepared_wallet_handle()
        .unwrap_or_else(|error| panic!("prepared handle failed: {error:?}"));
    lock_prepared_wallets()
        .unwrap_or_else(|error| panic!("prepared registry failed: {error:?}"))
        .insert(handle, PreparedWalletSlot::Claimed { owner: 7001 });

    let error = claim_prepared_wallet(handle, 7002)
        .err()
        .unwrap_or_else(|| panic!("cross-instance claim must fail"));
    assert_eq!(error.code, CitizenSdkErrorCode::InvalidHandle);
    assert_eq!(
        require_prepared_owner(7001, 7002)
            .err()
            .unwrap_or_else(|| panic!("cross-instance owner check must fail"))
            .code,
        CitizenSdkErrorCode::InvalidHandle,
    );

    lock_prepared_wallets()
        .unwrap_or_else(|error| panic!("prepared registry cleanup failed: {error:?}"))
        .remove(&handle);
}

#[test]
fn wallet_transfer_cancellation_drains_before_returning_or_releasing_the_future() {
    let runtime = tokio::runtime::Builder::new_current_thread()
        .enable_time()
        .build()
        .expect("timer runtime");
    let _entered = runtime.enter();
    let dropped = Arc::new(AtomicBool::new(false));
    let completed = Arc::new(AtomicBool::new(false));
    let (release, receiver) = futures_channel::oneshot::channel();
    let transfer = PendingWalletTransfer {
        dropped: Arc::clone(&dropped),
        completed: Arc::clone(&completed),
        release: receiver,
    };
    let token = WalletTransferCancellation::default();
    let (cancel, cancellation) = futures_channel::oneshot::channel();
    let mut operation = Box::pin(wallet_transfer_or_cancellation(
        transfer,
        cancellation,
        token.clone(),
    ));
    assert!(operation.as_mut().now_or_never().is_none());
    cancel
        .send(())
        .unwrap_or_else(|_| panic!("cancellation receiver disappeared before selection"));
    assert!(operation.as_mut().now_or_never().is_none());
    assert!(token.is_cancelled());
    assert!(!completed.load(Ordering::SeqCst));
    assert!(
        !dropped.load(Ordering::SeqCst),
        "host CAS 未返回前不能释放 Engine lease"
    );
    release
        .send(())
        .unwrap_or_else(|_| panic!("CAS receiver was dropped by cancellation"));
    let error = futures_executor::block_on(operation)
        .err()
        .unwrap_or_else(|| panic!("cancellation must not return a wallet transfer result"));
    assert_eq!(error.code, CitizenSdkErrorCode::Cancelled);
    assert!(error.message.contains("durable pending/in-block history"));
    assert!(dropped.load(Ordering::SeqCst));
    assert!(completed.load(Ordering::SeqCst));
}

#[test]
fn cancellation_before_first_poll_reaches_engine_before_side_effects() {
    let token = WalletTransferCancellation::default();
    let transfer_token = token.clone();
    let transfer = async move {
        assert!(
            transfer_token.is_cancelled(),
            "首 poll 前先通知 Engine，不能启动广播前写入"
        );
        Err(EngineError::StatePoisoned)
    };
    let (send, receiver) = futures_channel::oneshot::channel();
    assert!(send.send(()).is_ok());
    let result =
        futures_executor::block_on(wallet_transfer_or_cancellation(transfer, receiver, token));
    assert_eq!(
        result
            .err()
            .unwrap_or_else(|| panic!("预取消必须失败"))
            .code,
        CitizenSdkErrorCode::Cancelled
    );
}

#[test]
fn timeout_drains_an_entered_store_and_preserves_pending_without_cancelling_other_requests() {
    let dropped = Arc::new(AtomicBool::new(false));
    let completed = Arc::new(AtomicBool::new(false));
    let (release, receiver) = futures_channel::oneshot::channel();
    let transfer = PendingWalletTransfer {
        dropped: dropped.clone(),
        completed: completed.clone(),
        release: receiver,
    };
    let token = WalletTransferCancellation::default();
    let other = WalletTransferCancellation::default();
    let (_cancel, cancellation) = futures_channel::oneshot::channel();
    let (expire, deadline) = futures_channel::oneshot::channel();
    let mut operation = Box::pin(super::wallet_transfer_or_cancellation_and_budget(
        transfer,
        cancellation,
        token.clone(),
        async {
            let _ = deadline.await;
        },
    ));
    assert!(operation.as_mut().now_or_never().is_none());
    assert!(expire.send(()).is_ok());
    assert!(operation.as_mut().now_or_never().is_none());
    assert!(token.is_cancelled());
    assert!(!other.is_cancelled());
    assert!(!dropped.load(Ordering::SeqCst));
    assert!(!completed.load(Ordering::SeqCst));
    assert!(release.send(()).is_ok());
    let error = futures_executor::block_on(operation)
        .expect_err("expired budget must not imply execution success");
    assert_eq!(error.code, CitizenSdkErrorCode::Timeout);
    assert!(error.message.contains("unverified"));
    assert!(error.message.contains("retained"));
    assert!(dropped.load(Ordering::SeqCst));
    assert!(completed.load(Ordering::SeqCst));
}

#[test]
fn cancellation_of_idle_watch_is_cooperative_and_does_not_wait_for_a_block() {
    let runtime = tokio::runtime::Builder::new_current_thread()
        .enable_time()
        .build()
        .expect("timer runtime");
    let _entered = runtime.enter();
    let token = WalletTransferCancellation::default();
    let transfer_token = token.clone();
    let transfer = std::future::poll_fn(move |_| {
        if transfer_token.is_cancelled() {
            Poll::Ready(Err(EngineError::StatePoisoned))
        } else {
            Poll::Pending
        }
    });
    let (send, receiver) = futures_channel::oneshot::channel();
    let mut operation = Box::pin(wallet_transfer_or_cancellation(transfer, receiver, token));
    assert!(operation.as_mut().now_or_never().is_none());
    assert!(send.send(()).is_ok());
    assert_eq!(
        futures_executor::block_on(operation)
            .err()
            .unwrap_or_else(|| panic!("观察取消必须失败"))
            .code,
        CitizenSdkErrorCode::Cancelled
    );
}

#[test]
fn uncancelled_transfer_preserves_the_engine_result_without_setting_the_token() {
    let token = WalletTransferCancellation::default();
    let (_send, receiver) = futures_channel::oneshot::channel();
    let result = futures_executor::block_on(wallet_transfer_or_cancellation(
        async { Err(EngineError::StatePoisoned) },
        receiver,
        token.clone(),
    ));
    assert_eq!(
        result
            .err()
            .unwrap_or_else(|| panic!("必须保留 Engine 失败"))
            .code,
        crate::error::FfiError::from(EngineError::StatePoisoned).code
    );
    assert!(!token.is_cancelled());
}

#[test]
fn wallet_transfer_is_dispatched_only_to_the_dedicated_watch_pool() {
    let source = include_str!("wallet_abi.rs");
    let function = source
        .split("pub unsafe extern \"C\" fn citizensdk_transfer_with_remark")
        .nth(1)
        .and_then(|tail| tail.split("#[no_mangle]").next())
        .unwrap_or_else(|| panic!("wallet transfer ABI function must remain present"));
    assert!(function.contains("accept_and_write_watch("));
    assert!(!function.contains("accept_and_write(runtime"));
    assert!(function.contains("wallet_transfer_or_cancellation("));
    assert!(function.contains("transfer_with_remark_and_watch("));
    assert!(!function.contains(".transfer_with_remark(source"));
}

#[test]
fn high_level_wallet_progress_uses_only_truthful_existing_watch_states() {
    let best = VerifiedBlockRef::best(Hash32::from_bytes([7; 32]), 42);
    let finalized = VerifiedBlockRef::finalized(Hash32::from_bytes([8; 32]), 43);

    assert_eq!(
        wallet_transfer_watch_event(&WalletTransferWatchStage::Pending),
        None
    );
    assert_eq!(
        wallet_transfer_watch_event(&WalletTransferWatchStage::Interrupted {
            reason: "network".to_owned(),
        }),
        None,
    );
    assert_eq!(
        wallet_transfer_watch_event(&WalletTransferWatchStage::Broadcast { peer_count: 3 }),
        Some(ExtrinsicWatchEvent::Broadcast { peer_count: 3 }),
    );
    assert_eq!(
        wallet_transfer_watch_event(&WalletTransferWatchStage::InBlock { block: best }),
        Some(ExtrinsicWatchEvent::InBlock { block: best }),
    );
    assert_eq!(
        wallet_transfer_watch_event(&WalletTransferWatchStage::Finalized {
            conclusion: ExecutionConclusion::Success {
                block: finalized,
                extrinsic_index: 5,
            },
        }),
        Some(ExtrinsicWatchEvent::Finalized {
            block: finalized
                .try_into()
                .unwrap_or_else(|error| panic!("finalized conversion failed: {error:?}")),
        }),
    );
    assert_eq!(
        wallet_transfer_watch_event(&WalletTransferWatchStage::PoolRejected {
            reason: "invalid".to_owned(),
            replacement_hash: None,
        }),
        Some(ExtrinsicWatchEvent::Invalid),
    );
    assert_eq!(
        wallet_transfer_watch_event(&WalletTransferWatchStage::PoolRejected {
            reason: "usurped".to_owned(),
            replacement_hash: Some(Hash32::from_bytes([9; 32])),
        }),
        Some(ExtrinsicWatchEvent::Usurped {
            replacement_hash: Hash32::from_bytes([9; 32]),
        }),
    );
}
