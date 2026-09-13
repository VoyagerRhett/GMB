import 'dart:convert';
import 'dart:typed_data';

import 'package:citizenapp/my/membership/subscription_chain.dart';
import 'package:flutter_test/flutter_test.dart';

String _hex(Uint8List bytes) =>
    bytes.map((byte) => byte.toRadixString(16).padLeft(2, '0')).join();

Uint8List _bytes(String hex) => Uint8List.fromList([
      for (var index = 0; index < hex.length; index += 2)
        int.parse(hex.substring(index, index + 2), radix: 16),
    ]);

void main() {
  const creatorCidNumber = 'CN220-CTZN2-900000001-2026';
  const creatorCidScale =
      '68434e3232302d43545a4e322d3930303030303030312d32303236';

  group('SquarePost 订阅 SCALE', () {
    test('平台订阅携带当前签名价', () {
      final call = SubscriptionChain.buildSubscribePlatformCall(
        SubscriptionChain.membershipLevelByte('spark'),
        BigInt.from(5999900),
      );
      expect(
        _hex(call),
        '22010000021c8d5b00000000000000000000000000',
      );
    });

    test('创作者订阅只携带 CID、tier_id、自然周期和当前签名价', () {
      final call = SubscriptionChain.buildSubscribeCreatorCall(
        creatorCidNumber,
        'supporter',
        'monthly',
        BigInt.from(50),
      );
      expect(
        _hex(call),
        '220101${creatorCidScale}0124737570706f7274657200'
        '32000000000000000000000000000000',
      );
    });

    test('取消只携带收款主体', () {
      expect(_hex(SubscriptionChain.buildCancelPlatformCall()), '220200');
    });

    test('创作者套餐覆盖式编码', () {
      final call = SubscriptionChain.buildSetCreatorPlansCall([
        CreatorTierInput(
          tierId: 'supporter',
          tierName: '支持者',
          pricesFen: [
            CreatorPeriodPriceInput(
              billingPeriod: 'monthly',
              priceFen: BigInt.from(50),
            ),
          ],
        ),
      ]);
      expect(
        _hex(call),
        '22030424737570706f7274657224e694afe68c81e880850400'
        '32000000000000000000000000000000',
      );
    });

    test('只修改档位名称使用 call_index 6 且不携带价格', () {
      expect(
        _hex(SubscriptionChain.buildUpdateCreatorTierNameCall(
          'supporter',
          '核心支持者',
        )),
        '220624737570706f727465723ce6a0b8e5bf83e694afe68c81e88085',
      );
    });

    test('20 个四字节 Unicode 标量使用标准两字节 Compact 长度', () {
      final tierName = String.fromCharCodes(List.filled(20, 0x1f642));
      final call =
          SubscriptionChain.buildUpdateCreatorTierNameCall('t', tierName);
      expect(call[4], 0x41);
      expect(call[5], 0x01);
      expect(call.length, 86);
      expect(
        () => SubscriptionChain.buildUpdateCreatorTierNameCall(
          't',
          '$tierName🙂',
        ),
        throwsArgumentError,
      );
    });

    test('平台与创作者换档使用同一 call_index 并携带目标签名价', () {
      expect(
        _hex(SubscriptionChain.buildChangePlatformPlanCall(1, BigInt.from(50))),
        '220400000132000000000000000000000000000000',
      );
      expect(
        _hex(SubscriptionChain.buildChangeCreatorPlanCall(
          creatorCidNumber,
          'supporter',
          'yearly',
          BigInt.from(500),
        )),
        '220401${creatorCidScale}0124737570706f7274657202'
        'f4010000000000000000000000000000',
      );
    });

    test('非法周期、空 tier_id 和非正价格被拒绝', () {
      expect(() => SubscriptionChain.billingPeriodByte('daily'),
          throwsArgumentError);
      expect(
        () => SubscriptionChain.buildSubscribeCreatorCall(
          creatorCidNumber,
          '',
          'monthly',
          BigInt.one,
        ),
        throwsArgumentError,
      );
      expect(
        () => SubscriptionChain.buildSubscribePlatformCall(0, BigInt.zero),
        throwsArgumentError,
      );
    });
  });

  group('SquarePost finalized storage 解码', () {
    test('严格解码平台订阅真态与时间戳', () {
      // 与 runtime 金标 state_platform 逐字节一致（无延迟生效套餐字段，
      // 末尾含 authorized_price_fen + suspend_reason）。
      const stateHex =
          '00020068e5cf8b0100000068e5cf8b0100001c8d5b0000000000000000000000000000fc1a478c010000001c8d5b0000000000000000000000000000';
      final state = SubscriptionChain.decodeSubscriptionState(_bytes(stateHex));
      expect(state.plan.kind, 'platform');
      expect(state.plan.membershipLevel, 'spark');
      expect(state.startedAt, 1700000000000);
      expect(state.lastChargedPriceFen, BigInt.from(5999900));
      expect(state.paidUntil, 1702000000000);
      expect(state.status, 'active');
      expect(state.authorizedPriceFen, BigInt.from(5999900));
      expect(state.suspendReason, isNull);
      expect(state.isEffectiveAt(1701000000000), isTrue);
    });

    test('解码挂起态（创作者改价待再签名）与创作者暂停态，暂停期无权益', () {
      // 由 active 向量改：status 字节 00→03、suspend_reason 00→0100（Some(NeedReconsent)）。
      const suspendedHex =
          '00020068e5cf8b0100000068e5cf8b0100001c8d5b0000000000000000000000000000fc1a478c010000031c8d5b000000000000000000000000000100';
      final suspended =
          SubscriptionChain.decodeSubscriptionState(_bytes(suspendedHex));
      expect(suspended.status, 'suspended');
      expect(suspended.suspendReason, 'needReconsent');
      expect(suspended.isEffectiveAt(1701000000000), isFalse);

      const identityUnavailableHex =
          '00020068e5cf8b0100000068e5cf8b0100001c8d5b0000000000000000000000000000fc1a478c010000031c8d5b000000000000000000000000000102';
      expect(
        SubscriptionChain.decodeSubscriptionState(
          _bytes(identityUnavailableHex),
        ).suspendReason,
        'identityBindingUnavailable',
      );

      // status 字节 00→04（IssuerPaused），suspend_reason 仍 00（None）。
      const issuerPausedHex =
          '00020068e5cf8b0100000068e5cf8b0100001c8d5b0000000000000000000000000000fc1a478c010000041c8d5b0000000000000000000000000000';
      final issuerPaused =
          SubscriptionChain.decodeSubscriptionState(_bytes(issuerPausedHex));
      expect(issuerPaused.status, 'issuerPaused');
      expect(issuerPaused.suspendReason, isNull);
      expect(issuerPaused.isEffectiveAt(1701000000000), isFalse);
    });

    test('严格解码创作者链上档位', () {
      const price50 = '32000000000000000000000000000000';
      const price500 = 'f4010000000000000000000000000000';
      final tiers = SubscriptionChain.decodeCreatorPlans(
        _bytes('0424737570706f727465720800${price50}02$price500'),
      );
      expect(tiers, hasLength(1));
      expect(tiers.single.tierId, 'supporter');
      expect(tiers.single.tierName, isNull);
      expect(tiers.single.pricesFen, {
        'monthly': BigInt.from(50),
        'yearly': BigInt.from(500),
      });
    });

    test('严格解码链上档位名称及 80 字节边界', () {
      expect(
        SubscriptionChain.decodeCreatorTierName(_bytes('24e694afe68c81e88085')),
        '支持者',
      );
      final tierName = String.fromCharCodes(List.filled(20, 0x1f642));
      final utf8Bytes =
          Uint8List.fromList(const Utf8Encoder().convert(tierName));
      final storage = Uint8List.fromList([0x41, 0x01, ...utf8Bytes]);
      expect(SubscriptionChain.decodeCreatorTierName(storage), tierName);
      expect(
        () => SubscriptionChain.decodeCreatorTierName(_bytes('082061')),
        throwsFormatException,
      );
    });

    test('非法枚举、截断和尾随字节必须报错', () {
      expect(
        () => SubscriptionChain.decodeSubscriptionState(_bytes('0003')),
        throwsFormatException,
      );
      expect(
        () => SubscriptionChain.decodeCreatorPlans(_bytes('0000')),
        throwsFormatException,
      );
    });

    test('Subscriptions 与 CreatorPlans storage key 使用不同真源项', () {
      final subscriptionKey =
          SubscriptionChain.buildSubscriptionStorageKey(creatorCidNumber, null);
      final creatorPlansKey =
          SubscriptionChain.buildCreatorPlansStorageKey(creatorCidNumber);
      expect(subscriptionKey.length, 76);
      expect(creatorPlansKey.length, 75);
      expect(_hex(subscriptionKey), isNot(_hex(creatorPlansKey)));
    });
  });
}
