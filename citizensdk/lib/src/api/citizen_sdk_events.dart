import '../models/citizen_capability.dart';
import '../models/citizen_chain_state.dart';

sealed class CitizenSdkEvent {
  const CitizenSdkEvent({required this.sequence});

  final int sequence;
}

/// 历史已变化；通过现有历史查询读取最新快照，不携带账户秘密或借用能力版本。
final class CitizenSdkHistoryChanged extends CitizenSdkEvent {
  const CitizenSdkHistoryChanged({required super.sequence});
}

/// 同一 SDK 轻节点已经验证的新 finalized block。
final class CitizenSdkFinalizedBlockChanged extends CitizenSdkEvent {
  const CitizenSdkFinalizedBlockChanged({
    required super.sequence,
    required this.finalized,
  });

  final CitizenBlockRef finalized;
}

final class CitizenSdkLifecycleChanged extends CitizenSdkEvent {
  const CitizenSdkLifecycleChanged({
    required super.sequence,
    required this.lifecycle,
  });

  final CitizenSdkLifecycle lifecycle;
}

final class CitizenSdkCapabilitiesChanged extends CitizenSdkEvent {
  const CitizenSdkCapabilitiesChanged({
    required super.sequence,
    required this.snapshot,
  });

  final CitizenCapabilitySnapshot snapshot;
}
