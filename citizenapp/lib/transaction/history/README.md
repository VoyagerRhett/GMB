# CitizenApp transaction history

CitizenApp 这里只保存交易 Tab 所需的业务展示字段；钱包、签名、交易执行、
轻节点、最终块与 execution history 的唯一真源均为 CitizenSDK。

- `wallet_transaction_history_service.dart`：消费同一个 CitizenSDK session 的
  类型化 history/finalized 事件，把 SDK 事实投影为 App 展示记录。
- `citizenchain_transaction_event_decoder.dart`：按目标块的 Runtime metadata
  解码转账业务事件，只负责 App 所需的收款方、金额、备注和收发方向。
- `local_tx_store.dart`：保存上述 App 业务字段；不启动节点、不管理链数据库、
  不扫描接入前区块，也不迁移或兼容旧 App 链记录。
- `presentation/`：保留原交易 Tab 的页面布局、状态文案和刷新行为。

本目录禁止出现 CitizenSDK 已提供的钱包、签名、交易执行、nonce、交易池监听、
Runtime RPC、轻节点或链数据库实现。
