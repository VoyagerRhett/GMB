import 'package:flutter_test/flutter_test.dart';
import 'package:citizenapp/chat/chat_product_policy.dart';
import 'package:citizenapp/my/membership/subscription_service.dart';
import 'package:tatachat_sdk/tatachat_sdk.dart';

const _cidNumber = 'CN220-CTZN2-100000001-2026';
const _otherCidNumber = 'CN220-CTZN2-100000002-2026';

void main() {
  const mib = 1024 * 1024;
  const policy = CitizenChatMediaLimitPolicy();

  setUp(
    () => SubscriptionService.setChatAuthorizationForTesting(
      _cidNumber,
      100 * mib,
    ),
  );
  tearDown(
    () => SubscriptionService.setChatAuthorizationForTesting(_cidNumber, null),
  );

  test('会员模块唯一保存 CID 绑定的聊天附件权益', () {
    expect(SubscriptionService.membershipResolvedFor(_cidNumber), isTrue);
    expect(
      SubscriptionService.chatAuthorizationResolvedFor(_cidNumber),
      isTrue,
    );
    expect(SubscriptionService.chatAuthorizedFor(_cidNumber), isTrue);
    expect(SubscriptionService.chatFileMaxBytesFor(_cidNumber), 100 * mib);
    expect(SubscriptionService.chatAuthorizedFor(_otherCidNumber), isFalse);
  });

  test('授权失败只关闭发送授权，不抹掉已确认会员展示事实', () {
    SubscriptionService.markChatAuthorizationUnavailable(_cidNumber);

    expect(SubscriptionService.membershipResolvedFor(_cidNumber), isTrue);
    expect(
      SubscriptionService.chatAuthorizationResolvedFor(_cidNumber),
      isFalse,
    );
    expect(SubscriptionService.chatAuthorizedFor(_cidNumber), isFalse);
    expect(SubscriptionService.chatFileMaxBytesFor(_cidNumber), 0);
  });

  test('聊天模块的媒体策略无状态读取会员模块当前上限', () {
    expect(policy.limitForKind(ChatMessageKind.image), 100 * mib);
    expect(policy.limitForKind(ChatMessageKind.video), 100 * mib);
    expect(policy.limitForKind(ChatMessageKind.file), 100 * mib);
    expect(policy.limitForKind(ChatMessageKind.audio), 100 * mib);
    expect(policy.limitForKind(ChatMessageKind.text), 0);
    expect(policy.limitForKind(ChatMessageKind.sticker), 0);
    expect(policy.limitForMime('image/png'), 100 * mib);
  });

  test('媒体精确边界由无状态策略执行，文字和贴纸不携带媒体字节', () {
    expect(policy.exceedsForKind(ChatMessageKind.image, 100 * mib), isFalse);
    expect(policy.exceedsForKind(ChatMessageKind.image, 100 * mib + 1), isTrue);
    expect(policy.exceedsForKind(ChatMessageKind.text, 1 << 40), isFalse);
    expect(policy.exceedsForKind(ChatMessageKind.sticker, 1 << 40), isFalse);
  });
}
