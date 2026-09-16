import 'package:tatachat_sdk/tatachat_sdk.dart';
import 'package:citizenapp/my/membership/subscription_service.dart';

/// 公民聊天模块的无状态会员适配；会员事实与附件额度唯一来自会员模块。
class CitizenChatMediaLimitPolicy implements ChatMediaLimitPolicy {
  const CitizenChatMediaLimitPolicy();

  int get _limit => SubscriptionService.currentChatFileMaxBytes;

  @override
  int limitForKind(ChatMessageKind kind) => switch (kind) {
    ChatMessageKind.image ||
    ChatMessageKind.video ||
    ChatMessageKind.file ||
    ChatMessageKind.audio => _limit,
    ChatMessageKind.text || ChatMessageKind.sticker => 0,
  };

  @override
  int limitForMime(String contentType) => _limit;

  @override
  bool exceedsForKind(ChatMessageKind kind, int byteSize) {
    if (kind == ChatMessageKind.text || kind == ChatMessageKind.sticker) {
      return false;
    }
    return byteSize > _limit;
  }
}
