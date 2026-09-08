import 'package:citizenapp/qr/generated/qr_action_registry.g.dart';
export 'package:citizenapp/qr/generated/qr_bodies.g.dart' show QrKind;

/// QR_V1 统一二维码协议常量。
///
/// 唯一事实源：`citizenchain/crates/qr-protocol/registry.json`。
/// Golden fixtures:`citizenchain/crates/qr-protocol/tests/fixtures/*.json`
///
/// 本文件只有一个协议字符串和一个扫码流向枚举,禁止新增任何旧协议常量。
class QrProtocol {
  QrProtocol._();

  /// 唯一协议版本字符串。压缩为 5 字符以降低二维码密度。
  static const String qrV1 = 'QR_V1';
}

/// 统一扫码流向枚举。线上只序列化为数字 `k`。
///
/// ## body 单字母键全局注册表(一字母 = 一含义,跨所有码型唯一)
///
/// 信封层:`p` 协议 / `k` 码型 / `i` 临时码 id / `e` 过期毫秒 / `b` body。
///
/// | 键 | 含义 | 编码 | 出现于 |
/// |---|---|---|---|
/// | `a` | 业务动作码 | int | k=1 |
/// | `g` | 签名算法(1=sr25519) | int | k=1 |
/// | `u` | 签名者公钥 | base64url | k=1, k=2 |
/// | `d` | 审阅载荷 | base64url | k=1 |
/// | `s` | 签名 | base64url | k=2 |
/// | `o` | 换绑时当前账户 | base64url | k=2 |
/// | `r` | 换绑时当前账户签名 | base64url | k=2 |
/// | `c` | cid_number 身份主键 | 文本 | k=3 |
/// | `n` | account_id 账户标识 | `0x` 小写 64 hex | k=3, k=4, k=5 |
/// | `v` | 金额 | 文本 | k=4 |
/// | `t` | 币种 | 文本 | k=4 |
/// | `m` | 备注 | 文本 | k=4 |
/// | `l` | 收款方清算行 CID | 文本 | k=4 |
///
/// `u` 与 `n` 都是 32 字节公钥却用两个字母:编码不同(`u` base64url 压体积、
/// `n` `0x` 小写 hex 走 `isAccountIdText` 单源校验)。同一字母两种编码会让解析器
/// 按码型猜格式,是明确埋雷,故分开。
///
/// 新增字段必须先在本表登记,禁止就地取一个没登记过的字母。
/// QR_V1 业务动作码。`k` 只表达扫码流向,业务场景必须放在 `a`。
///
/// 当前 Dart 动作表由 `citizenchain/crates/qr-protocol/registry/actions.yaml`
/// 生成；本文件只保留调用方仍在使用的常量别名和协议辅助函数。
class QrActions {
  QrActions._();

  static const int login = 1;
  static const int citizenIdentity = 2;
  // 注册局代办占号/换绑域签名(offchain,值对齐 qr-protocol registry)。
  static const int citizenOccupy = 10;
  static const int citizenRebind = 11;
  static const int switchDefaultAccount = 12;
  static const int squareDeviceBind = 13;
  static const int accountDataKeyProvision = 14;
  static const int publish = 15;
  static const int onchinaAdmin = 3;
  static const int activateAdmin = 5;
  static const int decryptAdmin = 6;
  static const int runtimeUpgradeHash = 7;

  /// 广场账户动作（订阅/取消/…）链下签名，走 GMB 哈希域 op_tag 0x1D。
  /// 官网无私钥发起，CitizenApp「扫一扫」扫码用 accountId 主钥签名回传。
  static const int squareAccountAction = 9;

  static const int transferWithRemark = 0x0400;
  static const int personalCreate = 0x0700;
  static const int personalClose = 0x0701;
  static const int personalAdminsChange = 0x1d00;
  static const int resolutionIssuance = 0x0800;
  static const int finalizeProposal = 0x0903;
  static const int retryPassedProposal = 0x0904;
  static const int cancelPassedProposal = 0x0905;
  static const int proposeRuntimeUpgrade = 0x0c00;
  static const int developerDirectUpgrade = 0x0c02;
  static const int resolutionDestroy = 0x0d00;
  static const int grandpaKeyChange = 0x0f00;
  // 机构创建/关闭已收归 onchina 控制台 + 冷钱包,citizenapp 不再生成机构创建/关闭签名请求,
  // 因此不保留旧机构生命周期动作码。
  static const int multisigTransfer = 0x1100;
  static const int safetyFundTransfer = 0x1101;
  static const int sweepToMain = 0x1102;
  static const int bindClearingBank = 0x131e;
  static const int depositClearingBank = 0x131f;
  static const int withdrawClearingBank = 0x1320;
  static const int switchClearingBank = 0x1321;
  static const int registerClearingBank = 0x1332;
  static const int updateClearingBankEndpoint = 0x1333;
  static const int unregisterClearingBank = 0x1334;
  static const int internalVote = 0x1400;
  static const int jointVote = 0x1500;
  static const int castReferendum = 0x1501;
  static const int castPopularVote = 0x1602;
  static const int castMutualVote = 0x1603;
  // 立法(LegislationYuan=25=0x19 发起类节点端;LegislationVote=26=0x1a 投票/签署类)。
  static const int legislationEnact = 0x1900;
  static const int legislationAmend = 0x1901;
  static const int legislationRepeal = 0x1902;
  static const int legislationRepresentativeVote = 0x1a01;
  static const int legislationReferendum = 0x1a02;
  static const int legislationExecutiveSign = 0x1a03;
  static const int legislationOverrideSign = 0x1a04;
  static const int legislationGuardVote = 0x1a05;

  /// 链交易动作统一按 `(pallet_index << 8) | call_index` 生成。
  static int chain(int palletIndex, int callIndex) =>
      ((palletIndex & 0xff) << 8) | (callIndex & 0xff);

  static bool isChainAction(int action) => action >= 0x0100;

  /// 注册局代办占号/换绑域签名：b.u 留空，d 是含账户零槽的完整 Runtime 授权模板；
  /// 钱包严格解码后把所选账户原位填入，再对完整授权结构做域分离签名。
  static bool isSelfAccountDomainAction(int action) =>
      action == citizenOccupy || action == citizenRebind;

  static bool isBinaryRaw(int action) =>
      action == activateAdmin || action == decryptAdmin;

  static bool isRuntimeHashOnly(int action) =>
      GeneratedQrActionRegistry.isHashOnlyAction(action);

  /// QR 数字动作码 → registry action_key。查不到即未登记,签名端必须拒绝。
  static const Map<int, String> actionKeyByCode =
      GeneratedQrActionRegistry.actionKeyByCode;

  /// registry action_key → 中文动作名。签名 UI 只能展示这里的中文名。
  static const Map<String, String> actionLabelZhByKey =
      GeneratedQrActionRegistry.actionLabelZhByKey;

  static String? actionKeyForCode(int actionCode) =>
      actionKeyByCode[actionCode];

  static String? actionLabelForCode(int actionCode) {
    final key = actionKeyForCode(actionCode);
    if (key == null) return null;
    return actionLabelZhByKey[key];
  }

  static String? actionLabelForKey(String actionKey) =>
      actionLabelZhByKey[actionKey];

  static int fromDecodedAction(String action) {
    // 公民参选身份确认复用 a=2 的公民身份签名域，具体身份等级由 payload 字段展示。
    if (action == 'citizen_candidate_identity') return citizenIdentity;
    return GeneratedQrActionRegistry.actionCodeForKey(action) ?? 0;
  }
}
