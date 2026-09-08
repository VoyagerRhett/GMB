part of 'governance_registry.dart';

// 本文件由 citizenapp/scripts/generate_citizenapp_governance_registry.mjs 自动生成。
// 中文注释：创世治理机构中英全称/简称、cid_number 和制度账户来自 runtime primitives；管理员必须动态读取链上 AdminAccounts。

/// 国储会（1 个）。
const List<InstitutionInfo> kNrc = [
  InstitutionInfo(
    cidFullName: '中华民族联邦共和国公民储备委员会',
    cidShortName: '国家储委会',
    cidFullNameEn:
        'Citizen Reserve Committee of the Federal Republic of the Chinese Nation',
    cidShortNameEn: 'National Reserve Committee',
    cidNumber: 'LN001-NRC0G-944805165-2026',
    orgType: OrgType.nrc,
    accounts: InstitutionAccounts(
      mainAccountId:
          '0x7c0c099ee4df10c5bd3f618ddf132b6d15390fa27d2c1369f70aeb6b5f3907e5',
      feeAccountId:
          '0xfabe3c11d600221ab4156ebaae3c00c8efae939442f4cd1a764cfdf62461a387',
      safetyFundAccountId:
          '0x4ac779852c175087c445c35efecfef3ce6e0232702152ea2283f0b5ec3952e53',
      heAccountId:
          '0xda5544a52e806f6e5daeba3e2f0be134b218a9c348f2804b7e933deb9ed84e86',
    ),
  ),
];

/// 省储会（43 个）。
const List<InstitutionInfo> kPrcs = [
  InstitutionInfo(
    cidFullName: '中枢省公民储备委员会',
    cidShortName: '中枢省储委会',
    cidFullNameEn: 'Zhongshu Provincial Citizen Reserve Committee',
    cidShortNameEn: 'Zhongshu Provincial Reserve Committee',
    cidNumber: 'ZS001-PRC0E-016974075-2026',
    orgType: OrgType.prc,
    accounts: InstitutionAccounts(
      mainAccountId:
          '0x54bad80b12cedbf7a1569fb96d18d90c4793949a356eb16c6304841af81001dd',
      feeAccountId:
          '0x1f88202bf56fad5c7acfb08bc95322bb0149f8561cdb1f10a9331d46067b353a',
    ),
  ),
  InstitutionInfo(
    cidFullName: '岭南省公民储备委员会',
    cidShortName: '岭南省储委会',
    cidFullNameEn: 'Lingnan Provincial Citizen Reserve Committee',
    cidShortNameEn: 'Lingnan Provincial Reserve Committee',
    cidNumber: 'LN001-PRC05-773405642-2026',
    orgType: OrgType.prc,
    accounts: InstitutionAccounts(
      mainAccountId:
          '0xd9ef67d0e814fa3a927b9e6a0ebb7dbf6c15d669fc3067600adcab0016ea1cdb',
      feeAccountId:
          '0xa1dca778ce1ceedf1e94bccae8ef011f07b15134e20f2bcd6f00457517792ad8',
    ),
  ),
  InstitutionInfo(
    cidFullName: '广东省公民储备委员会',
    cidShortName: '广东省储委会',
    cidFullNameEn: 'Guangdong Provincial Citizen Reserve Committee',
    cidShortNameEn: 'Guangdong Provincial Reserve Committee',
    cidNumber: 'GD001-PRC0V-067440774-2026',
    orgType: OrgType.prc,
    accounts: InstitutionAccounts(
      mainAccountId:
          '0x9d19ff83985b2bd8d30b2845d9d4c7ab90083f98cfe127a0e2297cb30cbc0085',
      feeAccountId:
          '0xe7c8c2e464dda3e504551c1770556b33370f5f0eba3877ceee0d81cf752df0e0',
    ),
  ),
  InstitutionInfo(
    cidFullName: '广西省公民储备委员会',
    cidShortName: '广西省储委会',
    cidFullNameEn: 'Guangxi Provincial Citizen Reserve Committee',
    cidShortNameEn: 'Guangxi Provincial Reserve Committee',
    cidNumber: 'GX001-PRC0C-663454043-2026',
    orgType: OrgType.prc,
    accounts: InstitutionAccounts(
      mainAccountId:
          '0xf6d5db67d791d8a7f2b35d00cf2e1f72ce1277d18bcb1addf04c8e97a9bb452b',
      feeAccountId:
          '0x2181ecdf5c83dfd5d06aabda9a69e18b5b3b230ae4a74cc574bb52f4c61eae42',
    ),
  ),
  InstitutionInfo(
    cidFullName: '福建省公民储备委员会',
    cidShortName: '福建省储委会',
    cidFullNameEn: 'Fujian Provincial Citizen Reserve Committee',
    cidShortNameEn: 'Fujian Provincial Reserve Committee',
    cidNumber: 'FJ001-PRC0I-389570546-2026',
    orgType: OrgType.prc,
    accounts: InstitutionAccounts(
      mainAccountId:
          '0x1431de61e3e80e5c7830d475cb6587cb7dde89c050c90aa1b40672a8e39b0c36',
      feeAccountId:
          '0x9efd82060cc4bebbd19431f20513f29cd5f310bd124002c963dec23e4c2a197a',
    ),
  ),
  InstitutionInfo(
    cidFullName: '海南省公民储备委员会',
    cidShortName: '海南省储委会',
    cidFullNameEn: 'Hainan Provincial Citizen Reserve Committee',
    cidShortNameEn: 'Hainan Provincial Reserve Committee',
    cidNumber: 'HN001-PRC0S-545676096-2026',
    orgType: OrgType.prc,
    accounts: InstitutionAccounts(
      mainAccountId:
          '0xcd5f16df4e71f6bf5cf9080d0576730f8f3a17f7a7e4a291214f6ad3ac656941',
      feeAccountId:
          '0x6ed7f59670c695838dfacacbfa04e8688714c7eb4ba353bcbcc247dbb309cedb',
    ),
  ),
  InstitutionInfo(
    cidFullName: '云南省公民储备委员会',
    cidShortName: '云南省储委会',
    cidFullNameEn: 'Yunnan Provincial Citizen Reserve Committee',
    cidShortNameEn: 'Yunnan Provincial Reserve Committee',
    cidNumber: 'YN001-PRC0W-145427171-2026',
    orgType: OrgType.prc,
    accounts: InstitutionAccounts(
      mainAccountId:
          '0x96b5f59842dffd1ca7f27cf004cbaff3be5afd02cf1935fe52670d0c858f0d57',
      feeAccountId:
          '0x61a3d8b8328f2bb80c8660cecd29fe7e172ed1143272e4421043b76e9afcf5b2',
    ),
  ),
  InstitutionInfo(
    cidFullName: '贵州省公民储备委员会',
    cidShortName: '贵州省储委会',
    cidFullNameEn: 'Guizhou Provincial Citizen Reserve Committee',
    cidShortNameEn: 'Guizhou Provincial Reserve Committee',
    cidNumber: 'GZ001-PRC02-969970096-2026',
    orgType: OrgType.prc,
    accounts: InstitutionAccounts(
      mainAccountId:
          '0xc25d8cf44c827852777ee62f5ea0ecccb539b2cac04628c2277aa0ab17101002',
      feeAccountId:
          '0x657d267730cc00787d4b0b44c1a434cc6f3923153741208a2b65b143ae65d0bb',
    ),
  ),
  InstitutionInfo(
    cidFullName: '湖南省公民储备委员会',
    cidShortName: '湖南省储委会',
    cidFullNameEn: 'Hunan Provincial Citizen Reserve Committee',
    cidShortNameEn: 'Hunan Provincial Reserve Committee',
    cidNumber: 'HU001-PRC0P-400319700-2026',
    orgType: OrgType.prc,
    accounts: InstitutionAccounts(
      mainAccountId:
          '0x0de24adffa51d31085f41f30c96ef92aa979181e6abd22ea53567a26048e4d40',
      feeAccountId:
          '0x296e2ea36b08f3e5b5ba8bf7f2c33da26ef2b21fe9da46783eae52472a0084aa',
    ),
  ),
  InstitutionInfo(
    cidFullName: '江西省公民储备委员会',
    cidShortName: '江西省储委会',
    cidFullNameEn: 'Jiangxi Provincial Citizen Reserve Committee',
    cidShortNameEn: 'Jiangxi Provincial Reserve Committee',
    cidNumber: 'JX001-PRC0J-458681566-2026',
    orgType: OrgType.prc,
    accounts: InstitutionAccounts(
      mainAccountId:
          '0x26ce33ca747e1e51d102c1c70708a6e73b9ab57d1edfa2889e923eff06575592',
      feeAccountId:
          '0x5a39ff5c324ad8f9fe55fe8e4d8accdff320f4aa78234568d169ebcd65ac436e',
    ),
  ),
  InstitutionInfo(
    cidFullName: '浙江省公民储备委员会',
    cidShortName: '浙江省储委会',
    cidFullNameEn: 'Zhejiang Provincial Citizen Reserve Committee',
    cidShortNameEn: 'Zhejiang Provincial Reserve Committee',
    cidNumber: 'ZJ001-PRC08-471270801-2026',
    orgType: OrgType.prc,
    accounts: InstitutionAccounts(
      mainAccountId:
          '0xb8eb8e8b5df07eb15c9bb5f7b0bb371683ef263646f8a5cd4f6637ee38b4fea3',
      feeAccountId:
          '0xbebcf7f822fd2d3d63931214a3e36393e1af3fe25dee2776f33e95403b441414',
    ),
  ),
  InstitutionInfo(
    cidFullName: '江苏省公民储备委员会',
    cidShortName: '江苏省储委会',
    cidFullNameEn: 'Jiangsu Provincial Citizen Reserve Committee',
    cidShortNameEn: 'Jiangsu Provincial Reserve Committee',
    cidNumber: 'JS001-PRC0O-358467174-2026',
    orgType: OrgType.prc,
    accounts: InstitutionAccounts(
      mainAccountId:
          '0x1de52f16c1be56a716209b1e3f6c79deeb00652b4afe16d0cb24725b9b274b4d',
      feeAccountId:
          '0x01fc4e7a445ece8dcaf190b59587eee83d9c55a2933b1eadd15a965cf57c3e33',
    ),
  ),
  InstitutionInfo(
    cidFullName: '山东省公民储备委员会',
    cidShortName: '山东省储委会',
    cidFullNameEn: 'Shandong Provincial Citizen Reserve Committee',
    cidShortNameEn: 'Shandong Provincial Reserve Committee',
    cidNumber: 'SD001-PRC07-027328848-2026',
    orgType: OrgType.prc,
    accounts: InstitutionAccounts(
      mainAccountId:
          '0xb83a2219f9b5ca85685cfb7392ecda03ac443592d73d6d56241f719baf3b561f',
      feeAccountId:
          '0xe41ff39318f6d93e6a2ab024cf5dc7894496b9e3684035b373a41d754650e4f0',
    ),
  ),
  InstitutionInfo(
    cidFullName: '山西省公民储备委员会',
    cidShortName: '山西省储委会',
    cidFullNameEn: 'Shanxi Provincial Citizen Reserve Committee',
    cidShortNameEn: 'Shanxi Provincial Reserve Committee',
    cidNumber: 'SX001-PRC0O-104465679-2026',
    orgType: OrgType.prc,
    accounts: InstitutionAccounts(
      mainAccountId:
          '0xb30c88f3752ed770d120acc2481f0357f9b4bb052058fea819cdd3eff36e5526',
      feeAccountId:
          '0x038541720507172bb48c3b367d6bca84d8688fbeb773c6417b0c6f10624b2cb5',
    ),
  ),
  InstitutionInfo(
    cidFullName: '河南省公民储备委员会',
    cidShortName: '河南省储委会',
    cidFullNameEn: 'Henan Provincial Citizen Reserve Committee',
    cidShortNameEn: 'Henan Provincial Reserve Committee',
    cidNumber: 'HE001-PRC0S-849245626-2026',
    orgType: OrgType.prc,
    accounts: InstitutionAccounts(
      mainAccountId:
          '0x0df1ae8648f0617c96f42a108803622a319ce3e150efecc50c8e5d57d560e22a',
      feeAccountId:
          '0xd450f18bc580abedcdf064632be9fbc0c62a5c022c9abdc4a8a936a56199f8db',
    ),
  ),
  InstitutionInfo(
    cidFullName: '河北省公民储备委员会',
    cidShortName: '河北省储委会',
    cidFullNameEn: 'Hebei Provincial Citizen Reserve Committee',
    cidShortNameEn: 'Hebei Provincial Reserve Committee',
    cidNumber: 'HB001-PRC0W-499533387-2026',
    orgType: OrgType.prc,
    accounts: InstitutionAccounts(
      mainAccountId:
          '0xbe5e60c9c96cdc7e65a570172a7f2a9467e0b85e2790fdc411af12c89d71aebf',
      feeAccountId:
          '0xc4f39ddf074a2b08fabc5925de87b7e799b1e0b4845d4a4d8687c04d4aff9daf',
    ),
  ),
  InstitutionInfo(
    cidFullName: '湖北省公民储备委员会',
    cidShortName: '湖北省储委会',
    cidFullNameEn: 'Hubei Provincial Citizen Reserve Committee',
    cidShortNameEn: 'Hubei Provincial Reserve Committee',
    cidNumber: 'HI001-PRC0D-659443961-2026',
    orgType: OrgType.prc,
    accounts: InstitutionAccounts(
      mainAccountId:
          '0x7ff4742a43efa3fd02d94006d4ce838c7eb380a10423eee040b84531603b9614',
      feeAccountId:
          '0x2848b936046ec37c4652a078b5d1be0ac8fd395f78dc917465c452271955e6eb',
    ),
  ),
  InstitutionInfo(
    cidFullName: '陕西省公民储备委员会',
    cidShortName: '陕西省储委会',
    cidFullNameEn: 'Shaanxi Provincial Citizen Reserve Committee',
    cidShortNameEn: 'Shaanxi Provincial Reserve Committee',
    cidNumber: 'SI001-PRC0T-711309909-2026',
    orgType: OrgType.prc,
    accounts: InstitutionAccounts(
      mainAccountId:
          '0x00d09d3a723fb14c435ff3c474fbe333ca247efea81b84f765f45558c950063c',
      feeAccountId:
          '0x860d529462d95746a5100bb3cfeba072cd13076852dc962cc2cb112fbb640d09',
    ),
  ),
  InstitutionInfo(
    cidFullName: '重庆省公民储备委员会',
    cidShortName: '重庆省储委会',
    cidFullNameEn: 'Chongqing Provincial Citizen Reserve Committee',
    cidShortNameEn: 'Chongqing Provincial Reserve Committee',
    cidNumber: 'CQ001-PRC06-478472058-2026',
    orgType: OrgType.prc,
    accounts: InstitutionAccounts(
      mainAccountId:
          '0x9c1a3f35ec63f61cc350e431895c307c3c4b251abffc511d5524916816963e72',
      feeAccountId:
          '0x033caba4f5245ddcfeb474ca28921c4abfade4f3dfe36c3f352b2b8bbb38537d',
    ),
  ),
  InstitutionInfo(
    cidFullName: '四川省公民储备委员会',
    cidShortName: '四川省储委会',
    cidFullNameEn: 'Sichuan Provincial Citizen Reserve Committee',
    cidShortNameEn: 'Sichuan Provincial Reserve Committee',
    cidNumber: 'SC001-PRC0Y-935659021-2026',
    orgType: OrgType.prc,
    accounts: InstitutionAccounts(
      mainAccountId:
          '0x0267991ba2e7345703c28470cf721522ca1f38fe83e6452303efaa137517c71e',
      feeAccountId:
          '0xd2bf97803809e1a00d9d21b390ad1aaba3bbfc67c45f0ed2c84ae72f66afc6ca',
    ),
  ),
  InstitutionInfo(
    cidFullName: '甘肃省公民储备委员会',
    cidShortName: '甘肃省储委会',
    cidFullNameEn: 'Gansu Provincial Citizen Reserve Committee',
    cidShortNameEn: 'Gansu Provincial Reserve Committee',
    cidNumber: 'GS001-PRC0L-679051155-2026',
    orgType: OrgType.prc,
    accounts: InstitutionAccounts(
      mainAccountId:
          '0x49e3f7a807f2ff0cababe59d1c31279e4c50687b81485c025b78550f00ff83b4',
      feeAccountId:
          '0x79cd9f78f56f9d0e305eb9265def10efb2250fc6c4fcdb34fe512caddd20069e',
    ),
  ),
  InstitutionInfo(
    cidFullName: '北平省公民储备委员会',
    cidShortName: '北平省储委会',
    cidFullNameEn: 'Beiping Provincial Citizen Reserve Committee',
    cidShortNameEn: 'Beiping Provincial Reserve Committee',
    cidNumber: 'BP001-PRC0R-189323546-2026',
    orgType: OrgType.prc,
    accounts: InstitutionAccounts(
      mainAccountId:
          '0xf43653d988585331dbe53e654c0b12e00ba67561f858945e99f27fbfb5c961a3',
      feeAccountId:
          '0x8db2a91c01105004227154952996b0ada94a63feb27b561d744f19d6cfffc12e',
    ),
  ),
  InstitutionInfo(
    cidFullName: '海滨省公民储备委员会',
    cidShortName: '海滨省储委会',
    cidFullNameEn: 'Haibin Provincial Citizen Reserve Committee',
    cidShortNameEn: 'Haibin Provincial Reserve Committee',
    cidNumber: 'HA001-PRC0Y-214178517-2026',
    orgType: OrgType.prc,
    accounts: InstitutionAccounts(
      mainAccountId:
          '0x4e78cc42842740c058a589b75ad9c5710d4026524371eb786514f50f50d45339',
      feeAccountId:
          '0x8d846856e3df9add807df0037ea6dbfbc7db672ccf3cbd99062ab16a36728bb7',
    ),
  ),
  InstitutionInfo(
    cidFullName: '松江省公民储备委员会',
    cidShortName: '松江省储委会',
    cidFullNameEn: 'Songjiang Provincial Citizen Reserve Committee',
    cidShortNameEn: 'Songjiang Provincial Reserve Committee',
    cidNumber: 'SJ001-PRC09-044490898-2026',
    orgType: OrgType.prc,
    accounts: InstitutionAccounts(
      mainAccountId:
          '0x679104bd5edef4032d11cab381c94ac9ad89df4f365e8d309a965b30daba368d',
      feeAccountId:
          '0xb08020d89c3f220658d27d011a36177c212099b7d28be54036fdb892de464c4c',
    ),
  ),
  InstitutionInfo(
    cidFullName: '龙江省公民储备委员会',
    cidShortName: '龙江省储委会',
    cidFullNameEn: 'Longjiang Provincial Citizen Reserve Committee',
    cidShortNameEn: 'Longjiang Provincial Reserve Committee',
    cidNumber: 'LJ001-PRC08-279890045-2026',
    orgType: OrgType.prc,
    accounts: InstitutionAccounts(
      mainAccountId:
          '0x849442bed3bc17e958af1612cb560d4594755324df3e56b81245bf65f4076558',
      feeAccountId:
          '0xe1794019bfea7b4cd975338a857533293059a1645c93e856347c3f309b9347e2',
    ),
  ),
  InstitutionInfo(
    cidFullName: '吉林省公民储备委员会',
    cidShortName: '吉林省储委会',
    cidFullNameEn: 'Jilin Provincial Citizen Reserve Committee',
    cidShortNameEn: 'Jilin Provincial Reserve Committee',
    cidNumber: 'JL001-PRC05-850461124-2026',
    orgType: OrgType.prc,
    accounts: InstitutionAccounts(
      mainAccountId:
          '0x91822638bcd0a5028d470bac69c8d7a9f3a10d995b291b79ef2febac76ce81a6',
      feeAccountId:
          '0x3d5b9f48527ca0052c110157068d74c22803ba8c3e7d2d6a25ce867c4dd0fd83',
    ),
  ),
  InstitutionInfo(
    cidFullName: '辽宁省公民储备委员会',
    cidShortName: '辽宁省储委会',
    cidFullNameEn: 'Liaoning Provincial Citizen Reserve Committee',
    cidShortNameEn: 'Liaoning Provincial Reserve Committee',
    cidNumber: 'LI001-PRC0T-978545133-2026',
    orgType: OrgType.prc,
    accounts: InstitutionAccounts(
      mainAccountId:
          '0xe9e22ea860eef168eaa319245d40fa255d5a3a722ae34823e66590d0bdc92684',
      feeAccountId:
          '0x538494cd0c2b9bf80ff51591d7f20925cc404bd0c0c93dbcbb0066ba76b8e9f5',
    ),
  ),
  InstitutionInfo(
    cidFullName: '宁夏省公民储备委员会',
    cidShortName: '宁夏省储委会',
    cidFullNameEn: 'Ningxia Provincial Citizen Reserve Committee',
    cidShortNameEn: 'Ningxia Provincial Reserve Committee',
    cidNumber: 'NX001-PRC0J-389752794-2026',
    orgType: OrgType.prc,
    accounts: InstitutionAccounts(
      mainAccountId:
          '0xa4095a3a388044d7a6ff154d4bcfb35cec384eefe8382d9e1d59710f1b16b347',
      feeAccountId:
          '0xf6de3a8a2f1c04e32b1a181672d7911d94ff37602662136b7a308b5455431ee3',
    ),
  ),
  InstitutionInfo(
    cidFullName: '青海省公民储备委员会',
    cidShortName: '青海省储委会',
    cidFullNameEn: 'Qinghai Provincial Citizen Reserve Committee',
    cidShortNameEn: 'Qinghai Provincial Reserve Committee',
    cidNumber: 'QH001-PRC0C-882026762-2026',
    orgType: OrgType.prc,
    accounts: InstitutionAccounts(
      mainAccountId:
          '0x972fd76274a5aa2a5781ebc1f78996b89716f2a43806469641888cc8bab628fb',
      feeAccountId:
          '0x8266ec270d22ccc8e757d59e26911769409ced871f73a48baf111f37cb675658',
    ),
  ),
  InstitutionInfo(
    cidFullName: '安徽省公民储备委员会',
    cidShortName: '安徽省储委会',
    cidFullNameEn: 'Anhui Provincial Citizen Reserve Committee',
    cidShortNameEn: 'Anhui Provincial Reserve Committee',
    cidNumber: 'AH001-PRC00-589856828-2026',
    orgType: OrgType.prc,
    accounts: InstitutionAccounts(
      mainAccountId:
          '0x6ed62e6ed8d66b93ce7de191b31d46a4645314830ec254498c9d8e72d03a8b17',
      feeAccountId:
          '0xf20174e8e24aed91623d69253e4ec670932f6b80600cafce6f754b00a921ccc9',
    ),
  ),
  InstitutionInfo(
    cidFullName: '台湾省公民储备委员会',
    cidShortName: '台湾省储委会',
    cidFullNameEn: 'Taiwan Provincial Citizen Reserve Committee',
    cidShortNameEn: 'Taiwan Provincial Reserve Committee',
    cidNumber: 'TW001-PRC07-265218823-2026',
    orgType: OrgType.prc,
    accounts: InstitutionAccounts(
      mainAccountId:
          '0xee3adae7d737c734a0c167fdd553d085451f5391cafeb2baed289f11be422076',
      feeAccountId:
          '0xd8d8f5889b1c30a67541e376d758d4e5e81adb817e4fedd6e11111f672fdb602',
    ),
  ),
  InstitutionInfo(
    cidFullName: '西藏省公民储备委员会',
    cidShortName: '西藏省储委会',
    cidFullNameEn: 'Xizang Provincial Citizen Reserve Committee',
    cidShortNameEn: 'Xizang Provincial Reserve Committee',
    cidNumber: 'XZ001-PRC02-435616961-2026',
    orgType: OrgType.prc,
    accounts: InstitutionAccounts(
      mainAccountId:
          '0x7e57913cbe8fb3f5e7731a041c72a62caf210124823dd368323f0c2927070fae',
      feeAccountId:
          '0x618a1ce7e0845c209cbddc9a80ea5a646f557354f13c80789a0a6c4fcadc2f8d',
    ),
  ),
  InstitutionInfo(
    cidFullName: '新疆省公民储备委员会',
    cidShortName: '新疆省储委会',
    cidFullNameEn: 'Xinjiang Provincial Citizen Reserve Committee',
    cidShortNameEn: 'Xinjiang Provincial Reserve Committee',
    cidNumber: 'XJ001-PRC02-671044381-2026',
    orgType: OrgType.prc,
    accounts: InstitutionAccounts(
      mainAccountId:
          '0x603fd39b08aa180ce23131902b6617937c1e0458f2ddd8d9fede9b91f9d5c955',
      feeAccountId:
          '0x9bde932d949465cd2187c588df79f4b8fc059d22d809d400695f71161650bb27',
    ),
  ),
  InstitutionInfo(
    cidFullName: '西康省公民储备委员会',
    cidShortName: '西康省储委会',
    cidFullNameEn: 'Xikang Provincial Citizen Reserve Committee',
    cidShortNameEn: 'Xikang Provincial Reserve Committee',
    cidNumber: 'XK001-PRC0P-695945392-2026',
    orgType: OrgType.prc,
    accounts: InstitutionAccounts(
      mainAccountId:
          '0x937e6a8d5e08e283141ea99c3ee4864922fc153ed1d60a6c959a9139abba32ad',
      feeAccountId:
          '0x1fef56f77e941977b7c3a8e891427d3fd58f3808729db78d5fb919b78db21a9a',
    ),
  ),
  InstitutionInfo(
    cidFullName: '阿里省公民储备委员会',
    cidShortName: '阿里省储委会',
    cidFullNameEn: 'Ali Provincial Citizen Reserve Committee',
    cidShortNameEn: 'Ali Provincial Reserve Committee',
    cidNumber: 'AL001-PRC0D-487847725-2026',
    orgType: OrgType.prc,
    accounts: InstitutionAccounts(
      mainAccountId:
          '0x9179901438d3fa33d76f7fe8578c054754954eeba2a8257df37db761265a129c',
      feeAccountId:
          '0x920d6d2516973dd09f777b3e7982f048f803f43026f46c2f637a7631c7b781d6',
    ),
  ),
  InstitutionInfo(
    cidFullName: '葱岭省公民储备委员会',
    cidShortName: '葱岭省储委会',
    cidFullNameEn: 'Congling Provincial Citizen Reserve Committee',
    cidShortNameEn: 'Congling Provincial Reserve Committee',
    cidNumber: 'CL001-PRC0J-771698743-2026',
    orgType: OrgType.prc,
    accounts: InstitutionAccounts(
      mainAccountId:
          '0x45939c77d7c4a02b91777a7d5577d3934a12ac8803f66cbc2ebd4dcb83147a5a',
      feeAccountId:
          '0x3da7aab561f4e6fbc8a8dbf0fa2c8240a9f795c7f0e9992cd2a50b41ca8d9ef0',
    ),
  ),
  InstitutionInfo(
    cidFullName: '伊犁省公民储备委员会',
    cidShortName: '伊犁省储委会',
    cidFullNameEn: 'Yili Provincial Citizen Reserve Committee',
    cidShortNameEn: 'Yili Provincial Reserve Committee',
    cidNumber: 'YL001-PRC0Q-293160581-2026',
    orgType: OrgType.prc,
    accounts: InstitutionAccounts(
      mainAccountId:
          '0x19e8cac822cc520209a1f02789732c4320eb55e319bb9ef1852d0ff3bd0306ad',
      feeAccountId:
          '0x1013b888d2203fa1e4cbde4988aac7ca05894406cd065188a359bea4824d4074',
    ),
  ),
  InstitutionInfo(
    cidFullName: '河西省公民储备委员会',
    cidShortName: '河西省储委会',
    cidFullNameEn: 'Hexi Provincial Citizen Reserve Committee',
    cidShortNameEn: 'Hexi Provincial Reserve Committee',
    cidNumber: 'HX001-PRC0D-475713213-2026',
    orgType: OrgType.prc,
    accounts: InstitutionAccounts(
      mainAccountId:
          '0xa31f30cbb854362a6de74a6e67b2602caa019e71cb661715edd348a2e30078a3',
      feeAccountId:
          '0xaeeb5928c668f810498ef947ab0f45636a05c7e92df87fcaf92a55fc861dfb34',
    ),
  ),
  InstitutionInfo(
    cidFullName: '昆仑省公民储备委员会',
    cidShortName: '昆仑省储委会',
    cidFullNameEn: 'Kunlun Provincial Citizen Reserve Committee',
    cidShortNameEn: 'Kunlun Provincial Reserve Committee',
    cidNumber: 'KL001-PRC0O-091969119-2026',
    orgType: OrgType.prc,
    accounts: InstitutionAccounts(
      mainAccountId:
          '0xc97a3d8e211609b7aa55c7f75c9e1d44c161287c69609840f3b7f296bd82d8b4',
      feeAccountId:
          '0x8c5db2704bef12e3a1e932ea3c55041465fe3939f67d27b288f7760a86b77bb0',
    ),
  ),
  InstitutionInfo(
    cidFullName: '河套省公民储备委员会',
    cidShortName: '河套省储委会',
    cidFullNameEn: 'Hetao Provincial Citizen Reserve Committee',
    cidShortNameEn: 'Hetao Provincial Reserve Committee',
    cidNumber: 'HT001-PRC00-481172908-2026',
    orgType: OrgType.prc,
    accounts: InstitutionAccounts(
      mainAccountId:
          '0xeb4cbfe90cbc0ec9f46b5a77c697e0462bde29b546d65b17e0e6fff2541c20c2',
      feeAccountId:
          '0x386392814bbf4513bb2ce079cbfc12033c8b345d571c0a3878761078890c316f',
    ),
  ),
  InstitutionInfo(
    cidFullName: '热河省公民储备委员会',
    cidShortName: '热河省储委会',
    cidFullNameEn: 'Rehe Provincial Citizen Reserve Committee',
    cidShortNameEn: 'Rehe Provincial Reserve Committee',
    cidNumber: 'RH001-PRC0F-697831866-2026',
    orgType: OrgType.prc,
    accounts: InstitutionAccounts(
      mainAccountId:
          '0xa68904edd0892ddb585b31bdb13711f9919f1e1bdb8a2b243ed8462295ff0787',
      feeAccountId:
          '0xbfb36313a0d5cc0dcb82a7b2fd27ae88c427e48f4888b1cb8fbdafcdf54c9218',
    ),
  ),
  InstitutionInfo(
    cidFullName: '兴安省公民储备委员会',
    cidShortName: '兴安省储委会',
    cidFullNameEn: 'Xingan Provincial Citizen Reserve Committee',
    cidShortNameEn: 'Xingan Provincial Reserve Committee',
    cidNumber: 'XA001-PRC0H-384161601-2026',
    orgType: OrgType.prc,
    accounts: InstitutionAccounts(
      mainAccountId:
          '0x38b95239084a4d72f46899781fb9fa619e901e39e1f3d225fd37c3165d4a9409',
      feeAccountId:
          '0x01a1df0cf49b383fbe8afcbc9e02d26ea44e7c2e1f5bac31837e827360b1cd51',
    ),
  ),
  InstitutionInfo(
    cidFullName: '合江省公民储备委员会',
    cidShortName: '合江省储委会',
    cidFullNameEn: 'Hejiang Provincial Citizen Reserve Committee',
    cidShortNameEn: 'Hejiang Provincial Reserve Committee',
    cidNumber: 'HJ001-PRC0V-963948997-2026',
    orgType: OrgType.prc,
    accounts: InstitutionAccounts(
      mainAccountId:
          '0x13695b601d837128635740439d81e8ffb955abd2edde9efc34b870d5745f1f64',
      feeAccountId:
          '0x994f7f0ec3cde1bb1bfb28aadeb0d6f103ff35b2ad2802b6ac9425231d3f31af',
    ),
  ),
];

/// 省储行（43 个）。
const List<InstitutionInfo> kProvincialBanks = [
  InstitutionInfo(
    cidFullName: '中枢省公民储备银行',
    cidShortName: '中枢省储行',
    cidFullNameEn: 'Zhongshu Provincial Citizen Reserve Bank',
    cidShortNameEn: 'Zhongshu Provincial Reserve Bank',
    cidNumber: 'ZS001-PRB08-233384677-2026',
    orgType: OrgType.prb,
    accounts: InstitutionAccounts(
      mainAccountId:
          '0xaf881a7feb5ea6653fcfc1e801308b4cc0aeedf85bd0674c992830a4e2ccfc46',
      feeAccountId:
          '0x6a0c89dfe0fbd9d475226c9163e936f400f960bf63743f46463e75a6c159bcdb',
      stakeAccountId:
          '0x9ef37de03eaf9108bd90479843c749be3a14da20fbc23cd3916da1897f83fc59',
    ),
  ),
  InstitutionInfo(
    cidFullName: '岭南省公民储备银行',
    cidShortName: '岭南省储行',
    cidFullNameEn: 'Lingnan Provincial Citizen Reserve Bank',
    cidShortNameEn: 'Lingnan Provincial Reserve Bank',
    cidNumber: 'LN001-PRB0K-703127075-2026',
    orgType: OrgType.prb,
    accounts: InstitutionAccounts(
      mainAccountId:
          '0x86f1e88c787286ab371cef9ca4ada192f6d98e950cba5586de3280a0ad748c33',
      feeAccountId:
          '0x75a2285a594c249db42fb12228c3cfc4f825e090d19373f29b9ef23741162693',
      stakeAccountId:
          '0x70a3369e3354296d8248263b6fafcaca12c7eacc59e1cb5d1f0f3f4e51a604df',
    ),
  ),
  InstitutionInfo(
    cidFullName: '广东省公民储备银行',
    cidShortName: '广东省储行',
    cidFullNameEn: 'Guangdong Provincial Citizen Reserve Bank',
    cidShortNameEn: 'Guangdong Provincial Reserve Bank',
    cidNumber: 'GD001-PRB0T-239565809-2026',
    orgType: OrgType.prb,
    accounts: InstitutionAccounts(
      mainAccountId:
          '0x46fb2dfc71054c9d5187772dd69f4097636454a679a14c73ff20409c000de1c8',
      feeAccountId:
          '0xa084bfe5ddce3d77b3e947e5c08de796d38ecc6c29ef35180fec241e184b608b',
      stakeAccountId:
          '0x7cfcb5d0f87fe8eb6a932f5f5296a45a745b8ab5b636f07d97b8cf3d27350d93',
    ),
  ),
  InstitutionInfo(
    cidFullName: '广西省公民储备银行',
    cidShortName: '广西省储行',
    cidFullNameEn: 'Guangxi Provincial Citizen Reserve Bank',
    cidShortNameEn: 'Guangxi Provincial Reserve Bank',
    cidNumber: 'GX001-PRB01-025559630-2026',
    orgType: OrgType.prb,
    accounts: InstitutionAccounts(
      mainAccountId:
          '0xaece89d4edcbc584933fc22f306dd855de67fbeb9bd13223bc7c9c4d8be490f8',
      feeAccountId:
          '0xa58dd0ee88d3eb2a14130c1bdf2c3a56072a3d8bcc9a05f789d396a587463486',
      stakeAccountId:
          '0x2f67685bb99921eb5f9313ed5b3f0100ab8e8b6cab46b8e17c72603980dd9eea',
    ),
  ),
  InstitutionInfo(
    cidFullName: '福建省公民储备银行',
    cidShortName: '福建省储行',
    cidFullNameEn: 'Fujian Provincial Citizen Reserve Bank',
    cidShortNameEn: 'Fujian Provincial Reserve Bank',
    cidNumber: 'FJ001-PRB0V-504679612-2026',
    orgType: OrgType.prb,
    accounts: InstitutionAccounts(
      mainAccountId:
          '0x329e53e43c1a68a6a31aa88705c576963e4ff230abbcea9a09be369f60af599e',
      feeAccountId:
          '0x589fd173a787ae33d1baca04fa120be4724835ddd3fd0d9fe56114d41b17da87',
      stakeAccountId:
          '0x734bae15748cba684670f659ea924e9a95708dfd7fae45bf8ade1f75dbacdd1a',
    ),
  ),
  InstitutionInfo(
    cidFullName: '海南省公民储备银行',
    cidShortName: '海南省储行',
    cidFullNameEn: 'Hainan Provincial Citizen Reserve Bank',
    cidShortNameEn: 'Hainan Provincial Reserve Bank',
    cidNumber: 'HN001-PRB0P-723623074-2026',
    orgType: OrgType.prb,
    accounts: InstitutionAccounts(
      mainAccountId:
          '0xe5fbc89f5366aeb575380066fc4df33f3938d1376087108787f2549cbec4a779',
      feeAccountId:
          '0xcc4ad3d70c61312b445c5e652d70bc8ffd35c0d8627e0f62375b26b1326ac87e',
      stakeAccountId:
          '0xc1b4a030fb7b132a10ede39aad8809cb66ff62763551b36558b9c050ba57c3b7',
    ),
  ),
  InstitutionInfo(
    cidFullName: '云南省公民储备银行',
    cidShortName: '云南省储行',
    cidFullNameEn: 'Yunnan Provincial Citizen Reserve Bank',
    cidShortNameEn: 'Yunnan Provincial Reserve Bank',
    cidNumber: 'YN001-PRB08-692525950-2026',
    orgType: OrgType.prb,
    accounts: InstitutionAccounts(
      mainAccountId:
          '0x5b2b6206e34cd3e0540b90fe44818c52ed4361e3425186889c29f186574b55aa',
      feeAccountId:
          '0x09d2dc993adc04d3b666db10a42f11568b843ee05105eca8984fed258d678b6b',
      stakeAccountId:
          '0x7df57c6f7348a0649bf5c6cb4982d0fb1009a33f6ff7ce493112195a61cef699',
    ),
  ),
  InstitutionInfo(
    cidFullName: '贵州省公民储备银行',
    cidShortName: '贵州省储行',
    cidFullNameEn: 'Guizhou Provincial Citizen Reserve Bank',
    cidShortNameEn: 'Guizhou Provincial Reserve Bank',
    cidNumber: 'GZ001-PRB00-490015860-2026',
    orgType: OrgType.prb,
    accounts: InstitutionAccounts(
      mainAccountId:
          '0x155dcbfa1fe28f6a085db3373c5a30e2bfb796713feb8e624d4e63d229f8e079',
      feeAccountId:
          '0x933b8fd387a7072b7bdc99ed37d110908a4e0f55e3ecf9993a12f5a78c978573',
      stakeAccountId:
          '0xb405ae36058889f023c2128b32b170bff3192e8bec92c9a3a86b31eb9f4ebaba',
    ),
  ),
  InstitutionInfo(
    cidFullName: '湖南省公民储备银行',
    cidShortName: '湖南省储行',
    cidFullNameEn: 'Hunan Provincial Citizen Reserve Bank',
    cidShortNameEn: 'Hunan Provincial Reserve Bank',
    cidNumber: 'HU001-PRB0F-084835673-2026',
    orgType: OrgType.prb,
    accounts: InstitutionAccounts(
      mainAccountId:
          '0xd6b3115e4b1aae55f1c3601a7b0612c304b8d9699cc7a9993fd182382e77ad0c',
      feeAccountId:
          '0xf9c1c2d5a242707780a1f431cabe22e828f12782d2757702de552d255fa21d29',
      stakeAccountId:
          '0x0fd79babfe287658b98931bf64f82678bec89a00a8f858490394b36f5b20c7c2',
    ),
  ),
  InstitutionInfo(
    cidFullName: '江西省公民储备银行',
    cidShortName: '江西省储行',
    cidFullNameEn: 'Jiangxi Provincial Citizen Reserve Bank',
    cidShortNameEn: 'Jiangxi Provincial Reserve Bank',
    cidNumber: 'JX001-PRB09-243765987-2026',
    orgType: OrgType.prb,
    accounts: InstitutionAccounts(
      mainAccountId:
          '0xde3584a03bd971117b22a746b5ce1dcea73828d76e079882bd6e0b54db126bca',
      feeAccountId:
          '0x7033fc1f98c21021d4650e430ed068cf46d4a93a7f1d8f14c8f35b68da5839d8',
      stakeAccountId:
          '0x1c43cf5fb00f42f352f375ca905783539d72f5284a19a5a95af908e2381862d1',
    ),
  ),
  InstitutionInfo(
    cidFullName: '浙江省公民储备银行',
    cidShortName: '浙江省储行',
    cidFullNameEn: 'Zhejiang Provincial Citizen Reserve Bank',
    cidShortNameEn: 'Zhejiang Provincial Reserve Bank',
    cidNumber: 'ZJ001-PRB0R-296232973-2026',
    orgType: OrgType.prb,
    accounts: InstitutionAccounts(
      mainAccountId:
          '0x4b05f4fd4e07fe55084d26a64ca7fa787681e5130dd02344851d5f1ea93e95e0',
      feeAccountId:
          '0xf57da45b2648193199c09269945555ce9b8f8e355339a429a23d799992a3d333',
      stakeAccountId:
          '0xb4334034e6b79304790fda6361a800409efa8abcd32ff8c03c16d4e02f530303',
    ),
  ),
  InstitutionInfo(
    cidFullName: '江苏省公民储备银行',
    cidShortName: '江苏省储行',
    cidFullNameEn: 'Jiangsu Provincial Citizen Reserve Bank',
    cidShortNameEn: 'Jiangsu Provincial Reserve Bank',
    cidNumber: 'JS001-PRB01-890774605-2026',
    orgType: OrgType.prb,
    accounts: InstitutionAccounts(
      mainAccountId:
          '0x3f75ec35139fe076e006ebc8c0352dfbba3d1a7d484a0ff33a3984426932dd4e',
      feeAccountId:
          '0xae66d540fe1dca4092f5c4df7e8c605c32152fdf9ca7af3dc861c58a9d77cf07',
      stakeAccountId:
          '0x97b032845532a02f352116096f6ea8d8605f03ec7418de67a376b0fb8c721ede',
    ),
  ),
  InstitutionInfo(
    cidFullName: '山东省公民储备银行',
    cidShortName: '山东省储行',
    cidFullNameEn: 'Shandong Provincial Citizen Reserve Bank',
    cidShortNameEn: 'Shandong Provincial Reserve Bank',
    cidNumber: 'SD001-PRB0G-114256751-2026',
    orgType: OrgType.prb,
    accounts: InstitutionAccounts(
      mainAccountId:
          '0x85f850faf1f4ace6c3169a61fbe129e2486878dae1d6380a698c2a0fcd70a564',
      feeAccountId:
          '0x9ab73917fca226990eddae1e6eba1b6b8b05cac60357cf1037ce65727e5db467',
      stakeAccountId:
          '0xe4aa7a234a1d44b0194ccf423345b5aeccd16fb9d7724376fd1133728d92eb72',
    ),
  ),
  InstitutionInfo(
    cidFullName: '山西省公民储备银行',
    cidShortName: '山西省储行',
    cidFullNameEn: 'Shanxi Provincial Citizen Reserve Bank',
    cidShortNameEn: 'Shanxi Provincial Reserve Bank',
    cidNumber: 'SX001-PRB0K-520132196-2026',
    orgType: OrgType.prb,
    accounts: InstitutionAccounts(
      mainAccountId:
          '0x7cb015e5de047a799f66b33bef38f2ec28505d87ffa083e741dd498677cdf5d2',
      feeAccountId:
          '0x71c92875a01d78a54f9e0032524435b73bc949e368e5495174eff4530f7a1c1a',
      stakeAccountId:
          '0x36e985c4f53b5aad0414654020487ecd4f13a96ea2d89b875c571999c313da37',
    ),
  ),
  InstitutionInfo(
    cidFullName: '河南省公民储备银行',
    cidShortName: '河南省储行',
    cidFullNameEn: 'Henan Provincial Citizen Reserve Bank',
    cidShortNameEn: 'Henan Provincial Reserve Bank',
    cidNumber: 'HE001-PRB03-158889343-2026',
    orgType: OrgType.prb,
    accounts: InstitutionAccounts(
      mainAccountId:
          '0x6efbdece0985faa711ad64f07bcce5e706bac2d127aedf413f8c8f577441d397',
      feeAccountId:
          '0x7c3a4bbff9ea5923b137e6f404c30794347869264e4d150c563083ca13c2a26b',
      stakeAccountId:
          '0x0851c9c4ac37a27e2a9bac065c3351c43ff43b3b5d0381feff932b6711a77f4d',
    ),
  ),
  InstitutionInfo(
    cidFullName: '河北省公民储备银行',
    cidShortName: '河北省储行',
    cidFullNameEn: 'Hebei Provincial Citizen Reserve Bank',
    cidShortNameEn: 'Hebei Provincial Reserve Bank',
    cidNumber: 'HB001-PRB0Z-484022741-2026',
    orgType: OrgType.prb,
    accounts: InstitutionAccounts(
      mainAccountId:
          '0x8794b9837ea3ea84b68af195ff5815bf260fc8f085dd8eec0646d3dd17a3eac4',
      feeAccountId:
          '0xa1cf47deaed6648501ddcbc35d06e5d16d8a9ddbf93f69a83f30e41cf6f6f8b9',
      stakeAccountId:
          '0x63d6d0456ce14fa47dd6596dd4b25bd1171d07b0189cb3e25d637fc984df1477',
    ),
  ),
  InstitutionInfo(
    cidFullName: '湖北省公民储备银行',
    cidShortName: '湖北省储行',
    cidFullNameEn: 'Hubei Provincial Citizen Reserve Bank',
    cidShortNameEn: 'Hubei Provincial Reserve Bank',
    cidNumber: 'HI001-PRB0V-514948302-2026',
    orgType: OrgType.prb,
    accounts: InstitutionAccounts(
      mainAccountId:
          '0x0405200fc6a67d2b4a5b1602ccc55009bfa0148c7f4d7e4552a7ec6b8c561f96',
      feeAccountId:
          '0x06ac835853610374c4ff60f6508502313ca555fc5379bddbb7f871b730e12369',
      stakeAccountId:
          '0x676e929eff0c6ff1aaac27889caa5dee332e54c13f1ffb369b709f3a26b026f8',
    ),
  ),
  InstitutionInfo(
    cidFullName: '陕西省公民储备银行',
    cidShortName: '陕西省储行',
    cidFullNameEn: 'Shaanxi Provincial Citizen Reserve Bank',
    cidShortNameEn: 'Shaanxi Provincial Reserve Bank',
    cidNumber: 'SI001-PRB0N-245618374-2026',
    orgType: OrgType.prb,
    accounts: InstitutionAccounts(
      mainAccountId:
          '0xd3d8e94d9dc2eb0457ebb871d551e46ba749cdfaae97e295ca20356add922fda',
      feeAccountId:
          '0xeae9574351984389de27c3ebdef6a3a374621385b470f6a052a7cd9cff107911',
      stakeAccountId:
          '0x3d0ab1d6b42b0c374613d038a44110b4c597c504b331ec45f3b5d2a2be0246cd',
    ),
  ),
  InstitutionInfo(
    cidFullName: '重庆省公民储备银行',
    cidShortName: '重庆省储行',
    cidFullNameEn: 'Chongqing Provincial Citizen Reserve Bank',
    cidShortNameEn: 'Chongqing Provincial Reserve Bank',
    cidNumber: 'CQ001-PRB0C-694162045-2026',
    orgType: OrgType.prb,
    accounts: InstitutionAccounts(
      mainAccountId:
          '0x8e7397e21e3c7d345b68fbeb3e479936bec8f697cb83cf90b81382d6ac5f7cab',
      feeAccountId:
          '0x68887536644c8c402c303d930c44af6e68c505f7dfd10f2a6df97c50a99195ab',
      stakeAccountId:
          '0xf583247e82cb83f8fb280feadc8647dafc10d7712b2ada045ddd23cf310cbf0d',
    ),
  ),
  InstitutionInfo(
    cidFullName: '四川省公民储备银行',
    cidShortName: '四川省储行',
    cidFullNameEn: 'Sichuan Provincial Citizen Reserve Bank',
    cidShortNameEn: 'Sichuan Provincial Reserve Bank',
    cidNumber: 'SC001-PRB0Q-764253139-2026',
    orgType: OrgType.prb,
    accounts: InstitutionAccounts(
      mainAccountId:
          '0x445832e057237b6c0ca00d9ed474e9fc01d28e3f6f4c7d8cc7c4a3d61785ae69',
      feeAccountId:
          '0x35c3366db061dd2645a8d609ad2339865eab41fc9f847ecb3fef7fac0a6b2a1c',
      stakeAccountId:
          '0x5d93831162b61898960303b4b5e93b87995adb38a16d32cc51e65e716fbd46d4',
    ),
  ),
  InstitutionInfo(
    cidFullName: '甘肃省公民储备银行',
    cidShortName: '甘肃省储行',
    cidFullNameEn: 'Gansu Provincial Citizen Reserve Bank',
    cidShortNameEn: 'Gansu Provincial Reserve Bank',
    cidNumber: 'GS001-PRB08-005784877-2026',
    orgType: OrgType.prb,
    accounts: InstitutionAccounts(
      mainAccountId:
          '0xd36f42f0b356092a5bee8d0df2d8c44fef5e4130b543aeedb4b0a4171a0ebe10',
      feeAccountId:
          '0xf00c243942dbdaf80833d8500416692a9223ad5f7d89a866e7c4e38d8574932d',
      stakeAccountId:
          '0x82e19122eb66a2b875f8c157093ee10bd9c86c61c2bb454ae2f3efc0a8e927ec',
    ),
  ),
  InstitutionInfo(
    cidFullName: '北平省公民储备银行',
    cidShortName: '北平省储行',
    cidFullNameEn: 'Beiping Provincial Citizen Reserve Bank',
    cidShortNameEn: 'Beiping Provincial Reserve Bank',
    cidNumber: 'BP001-PRB0Q-434307982-2026',
    orgType: OrgType.prb,
    accounts: InstitutionAccounts(
      mainAccountId:
          '0x5ecefffbb5c631d39618f08c952ad6bc34e0365c80ff3f73221e28bd4d6cdddf',
      feeAccountId:
          '0xc842a048d42b3b5eb4ac844afce9afaf2d93ef454d64cf57a4d836dcd5655070',
      stakeAccountId:
          '0x74b2a5526aafd050c4384409147a851259af31206e67698a919aa237ab46e7ba',
    ),
  ),
  InstitutionInfo(
    cidFullName: '海滨省公民储备银行',
    cidShortName: '海滨省储行',
    cidFullNameEn: 'Haibin Provincial Citizen Reserve Bank',
    cidShortNameEn: 'Haibin Provincial Reserve Bank',
    cidNumber: 'HA001-PRB08-969179618-2026',
    orgType: OrgType.prb,
    accounts: InstitutionAccounts(
      mainAccountId:
          '0x21723c4ffbdedfe3dc03f8f99f2be69d38974cefb8baaa5ae0dccb2aa19a2894',
      feeAccountId:
          '0xce51ee3dfe8bdd27ea58290bbf873bbe3f1cdaf2ae9d83b5bda546ebeed2c221',
      stakeAccountId:
          '0xae68191eff0ab539d94fe65706c51e4999d4f5f668d15a4aaf9b14c3841a319c',
    ),
  ),
  InstitutionInfo(
    cidFullName: '松江省公民储备银行',
    cidShortName: '松江省储行',
    cidFullNameEn: 'Songjiang Provincial Citizen Reserve Bank',
    cidShortNameEn: 'Songjiang Provincial Reserve Bank',
    cidNumber: 'SJ001-PRB03-644104544-2026',
    orgType: OrgType.prb,
    accounts: InstitutionAccounts(
      mainAccountId:
          '0x3e32836b01771c6e78ca0352f272a1c9a6f94a48c2fe43eb404ed12a28b0556f',
      feeAccountId:
          '0xc9d1ee88617e82d574446ca791246b46b76fe13da37a503af6dc4b34725eba3e',
      stakeAccountId:
          '0x7b65ef6465bbdecd5e0cfffad763502ac7737228ae8e6b973855fd6defb5e862',
    ),
  ),
  InstitutionInfo(
    cidFullName: '龙江省公民储备银行',
    cidShortName: '龙江省储行',
    cidFullNameEn: 'Longjiang Provincial Citizen Reserve Bank',
    cidShortNameEn: 'Longjiang Provincial Reserve Bank',
    cidNumber: 'LJ001-PRB0T-280510636-2026',
    orgType: OrgType.prb,
    accounts: InstitutionAccounts(
      mainAccountId:
          '0x880a95a01195ecab49863ac2941da1b3e24d1498b975d8bf17fb658e27f7d355',
      feeAccountId:
          '0xfbbfc3cd2fb99b1939539b02cdc3ef145b82d60f35fb6a0a963cf93dcc6b2f2e',
      stakeAccountId:
          '0xe7acb22227c602a2a28e4d3aa691ca3990e436ae23d60d8f301e5a9d72119404',
    ),
  ),
  InstitutionInfo(
    cidFullName: '吉林省公民储备银行',
    cidShortName: '吉林省储行',
    cidFullNameEn: 'Jilin Provincial Citizen Reserve Bank',
    cidShortNameEn: 'Jilin Provincial Reserve Bank',
    cidNumber: 'JL001-PRB07-129935340-2026',
    orgType: OrgType.prb,
    accounts: InstitutionAccounts(
      mainAccountId:
          '0xcfd73254a825eda01cf08614205b4175d682613604e795982af1507a40b768af',
      feeAccountId:
          '0x9f4cd452e0a136f55dca8a4016c122f7981b4a356a41c894c98e762cae814adb',
      stakeAccountId:
          '0xab92278c58834b68f4597bc68cf829e39e205d494cbb186a4ee9427084548f3d',
    ),
  ),
  InstitutionInfo(
    cidFullName: '辽宁省公民储备银行',
    cidShortName: '辽宁省储行',
    cidFullNameEn: 'Liaoning Provincial Citizen Reserve Bank',
    cidShortNameEn: 'Liaoning Provincial Reserve Bank',
    cidNumber: 'LI001-PRB0J-249814963-2026',
    orgType: OrgType.prb,
    accounts: InstitutionAccounts(
      mainAccountId:
          '0xfe9782b1cb4961ee45717105db51d7f9dca16d87c3399125778a9140ee71b9b1',
      feeAccountId:
          '0xea877c4fb6a99b92a1d670de59b6a44bec2e85270a6d945f0343fbc78c8adfbf',
      stakeAccountId:
          '0x69cac61df1286c84fe5a71276fc9a6a23123fdc5e282d8e4754f376423792a56',
    ),
  ),
  InstitutionInfo(
    cidFullName: '宁夏省公民储备银行',
    cidShortName: '宁夏省储行',
    cidFullNameEn: 'Ningxia Provincial Citizen Reserve Bank',
    cidShortNameEn: 'Ningxia Provincial Reserve Bank',
    cidNumber: 'NX001-PRB0F-292327153-2026',
    orgType: OrgType.prb,
    accounts: InstitutionAccounts(
      mainAccountId:
          '0x7e802a3dc6982cacc75bfa02e46bc8f1d074eb55f92acba831e5fbfdfa656627',
      feeAccountId:
          '0xedcb2ee9ad255d650f5e4854032822787ed7de7bc91f5b9b9e28abd6ce6bc071',
      stakeAccountId:
          '0x27fdbac513c52a901f4e7df7925bddde7f9b167aff76d38159265e8889538048',
    ),
  ),
  InstitutionInfo(
    cidFullName: '青海省公民储备银行',
    cidShortName: '青海省储行',
    cidFullNameEn: 'Qinghai Provincial Citizen Reserve Bank',
    cidShortNameEn: 'Qinghai Provincial Reserve Bank',
    cidNumber: 'QH001-PRB0V-075657014-2026',
    orgType: OrgType.prb,
    accounts: InstitutionAccounts(
      mainAccountId:
          '0xe52d727901162c6e4cf6e03f2066e057399ad9292001820d436dabdec2ed0679',
      feeAccountId:
          '0xcba5c8145bd6f14b1792e91489068655df18bee79fa751c029dbdaf0539712af',
      stakeAccountId:
          '0x63d81904d696e9a2351f447a744970077421831c6f6662b38715ffa64a8ed385',
    ),
  ),
  InstitutionInfo(
    cidFullName: '安徽省公民储备银行',
    cidShortName: '安徽省储行',
    cidFullNameEn: 'Anhui Provincial Citizen Reserve Bank',
    cidShortNameEn: 'Anhui Provincial Reserve Bank',
    cidNumber: 'AH001-PRB0M-388477914-2026',
    orgType: OrgType.prb,
    accounts: InstitutionAccounts(
      mainAccountId:
          '0x0003751d234a7a8afd21b2f5ec07f7bfc8232b20e38a7cd3f7b2c261bf164a7f',
      feeAccountId:
          '0xb21f3f0ac6b5ffbda92677932db40cc4901a52d7e112314b97971d7db24772a2',
      stakeAccountId:
          '0x5ac0e39f5136796ae3f9fe4627cde3953e354504ddb8dc4bbc4b18fc3c602469',
    ),
  ),
  InstitutionInfo(
    cidFullName: '台湾省公民储备银行',
    cidShortName: '台湾省储行',
    cidFullNameEn: 'Taiwan Provincial Citizen Reserve Bank',
    cidShortNameEn: 'Taiwan Provincial Reserve Bank',
    cidNumber: 'TW001-PRB0S-266238196-2026',
    orgType: OrgType.prb,
    accounts: InstitutionAccounts(
      mainAccountId:
          '0x6e52e744891abe902a42b039276cbf0593989d4ed4806fda54d19c69a73cda14',
      feeAccountId:
          '0x1aab1f7f10d33e3721e011f290c725453afa732a281d5ebfcd5bdf8b86c88566',
      stakeAccountId:
          '0x589f072691fc649620e797a730c56dcb288d5e0e513f335e7692fd77286bb854',
    ),
  ),
  InstitutionInfo(
    cidFullName: '西藏省公民储备银行',
    cidShortName: '西藏省储行',
    cidFullNameEn: 'Xizang Provincial Citizen Reserve Bank',
    cidShortNameEn: 'Xizang Provincial Reserve Bank',
    cidNumber: 'XZ001-PRB06-210788637-2026',
    orgType: OrgType.prb,
    accounts: InstitutionAccounts(
      mainAccountId:
          '0xe84daa85a070ae64eb1b7f18f75223158039349276df7e697737ee19086fe34b',
      feeAccountId:
          '0x885c1ee80f7cb124fa4b02c81bf8134fa86f192cb22859041e874039f132c613',
      stakeAccountId:
          '0xeac74424a7fdfcb66c327c93cb9c0bc3031e05f4307397c72b0afe36a815d9a2',
    ),
  ),
  InstitutionInfo(
    cidFullName: '新疆省公民储备银行',
    cidShortName: '新疆省储行',
    cidFullNameEn: 'Xinjiang Provincial Citizen Reserve Bank',
    cidShortNameEn: 'Xinjiang Provincial Reserve Bank',
    cidNumber: 'XJ001-PRB0V-233325633-2026',
    orgType: OrgType.prb,
    accounts: InstitutionAccounts(
      mainAccountId:
          '0xe3e528582c58cb319c0941bef1354b8303d2c1a9865b18f73b107e2354cee5e6',
      feeAccountId:
          '0xd8dd32e8f0ef1b843b8e1088d3a3a81e617d760768e57cd5cb889b59542b9444',
      stakeAccountId:
          '0x691f213f19f0b18a88469132e17f29a19443914ae618d6e68f815a98ee9c19c9',
    ),
  ),
  InstitutionInfo(
    cidFullName: '西康省公民储备银行',
    cidShortName: '西康省储行',
    cidFullNameEn: 'Xikang Provincial Citizen Reserve Bank',
    cidShortNameEn: 'Xikang Provincial Reserve Bank',
    cidNumber: 'XK001-PRB0Q-300401625-2026',
    orgType: OrgType.prb,
    accounts: InstitutionAccounts(
      mainAccountId:
          '0x0016695ce634d377fc5348f6e31bac12f89c275112bbf0683783a026e7d6e1bb',
      feeAccountId:
          '0xf8b0ce8c6dd9e6291063e9d1fa272d60e46248a53156d4da7309db23e3a66fe0',
      stakeAccountId:
          '0x3e9887da978e3fdc61c3d1a381408d9d53f9d1c47b481ff26a1ff8890af30fc5',
    ),
  ),
  InstitutionInfo(
    cidFullName: '阿里省公民储备银行',
    cidShortName: '阿里省储行',
    cidFullNameEn: 'Ali Provincial Citizen Reserve Bank',
    cidShortNameEn: 'Ali Provincial Reserve Bank',
    cidNumber: 'AL001-PRB0S-527686065-2026',
    orgType: OrgType.prb,
    accounts: InstitutionAccounts(
      mainAccountId:
          '0xcd15753c666a0604b68cf9a2af1626e17f0a259da8db94c3c54d4a092fbeac9c',
      feeAccountId:
          '0xc7764f932bef9b979daad3bb8e31c38aa35cab068a13a78ab1773dff21589114',
      stakeAccountId:
          '0xb1b7de69db50aa72ee171cc718c215d88722b0321604dae5ab536ced4fc12a5f',
    ),
  ),
  InstitutionInfo(
    cidFullName: '葱岭省公民储备银行',
    cidShortName: '葱岭省储行',
    cidFullNameEn: 'Congling Provincial Citizen Reserve Bank',
    cidShortNameEn: 'Congling Provincial Reserve Bank',
    cidNumber: 'CL001-PRB0Q-951267669-2026',
    orgType: OrgType.prb,
    accounts: InstitutionAccounts(
      mainAccountId:
          '0x9f5bd94ff37a8d3f04c8e90560782f5c6f20477bf813059e4d8bb3c17ae2bcc6',
      feeAccountId:
          '0xd971cc69417f5d1d777358c249295928ed9583cac22fdf9ca8e5f7a30a4e5f98',
      stakeAccountId:
          '0x873ffc96880f33b63f1ecf9ee4500e48654886f908b28346dc4a157029fc1d60',
    ),
  ),
  InstitutionInfo(
    cidFullName: '伊犁省公民储备银行',
    cidShortName: '伊犁省储行',
    cidFullNameEn: 'Yili Provincial Citizen Reserve Bank',
    cidShortNameEn: 'Yili Provincial Reserve Bank',
    cidNumber: 'YL001-PRB0A-142800261-2026',
    orgType: OrgType.prb,
    accounts: InstitutionAccounts(
      mainAccountId:
          '0x0da105fd6917c7703b6f357eeb7e05c445c63200eaab80efa93a66b1b286f9b6',
      feeAccountId:
          '0x5e44f4d61ba255aece31e1431772fe581202d9d94228de2b001da7e6b878aca4',
      stakeAccountId:
          '0xcfa537b3733e731c78b86d110f4582bd70bf8271a7c2539902283c1865e087e8',
    ),
  ),
  InstitutionInfo(
    cidFullName: '河西省公民储备银行',
    cidShortName: '河西省储行',
    cidFullNameEn: 'Hexi Provincial Citizen Reserve Bank',
    cidShortNameEn: 'Hexi Provincial Reserve Bank',
    cidNumber: 'HX001-PRB0F-215310265-2026',
    orgType: OrgType.prb,
    accounts: InstitutionAccounts(
      mainAccountId:
          '0x219a983e60a6e9f684632e0783374f4fec3325f46d5c7de3cb1d05dde7599193',
      feeAccountId:
          '0x9c32f71166acabb5c83a3f996da1799850ee81085238ab3f77769c1b9be17fd2',
      stakeAccountId:
          '0x8788f04c31560597da4c7a88547bf7ce6b3f3bdb3a2314ec38f2ac8eb8841166',
    ),
  ),
  InstitutionInfo(
    cidFullName: '昆仑省公民储备银行',
    cidShortName: '昆仑省储行',
    cidFullNameEn: 'Kunlun Provincial Citizen Reserve Bank',
    cidShortNameEn: 'Kunlun Provincial Reserve Bank',
    cidNumber: 'KL001-PRB08-682838027-2026',
    orgType: OrgType.prb,
    accounts: InstitutionAccounts(
      mainAccountId:
          '0xd2f1ca163d87fcc96546ebd5891c2487f21b6fd1702de8a1182da79651cc89a7',
      feeAccountId:
          '0x286f18c7b374885dcd2a8c5e742180c73370cdfca2477936fd9f780c83d2fe8f',
      stakeAccountId:
          '0x7e076e31849d096e9d7eade9ec39cbcd1fea6573035f489270a8919f2b15e4de',
    ),
  ),
  InstitutionInfo(
    cidFullName: '河套省公民储备银行',
    cidShortName: '河套省储行',
    cidFullNameEn: 'Hetao Provincial Citizen Reserve Bank',
    cidShortNameEn: 'Hetao Provincial Reserve Bank',
    cidNumber: 'HT001-PRB0L-210616196-2026',
    orgType: OrgType.prb,
    accounts: InstitutionAccounts(
      mainAccountId:
          '0x6c59fa9059358d7bf95f83b0c4eaaf6f2e4837a7151174e128ffd2acc8f23f39',
      feeAccountId:
          '0x778ba42edb6e07a03b2e23d5f4ba297d1afa5e2ed3c52c05dbba9646ddc52646',
      stakeAccountId:
          '0xa67902e6f6c3dde951e65fc1dba0073a433ba39b312ef6e016d2c55d7257173f',
    ),
  ),
  InstitutionInfo(
    cidFullName: '热河省公民储备银行',
    cidShortName: '热河省储行',
    cidFullNameEn: 'Rehe Provincial Citizen Reserve Bank',
    cidShortNameEn: 'Rehe Provincial Reserve Bank',
    cidNumber: 'RH001-PRB0C-380830938-2026',
    orgType: OrgType.prb,
    accounts: InstitutionAccounts(
      mainAccountId:
          '0x8d59d4a31ab0cb729ce80b42d1d82f50d87a8557b1008a960a30892772a7d296',
      feeAccountId:
          '0xaece412409c5309ffbe83f67ee32d1ebb8b6192d767411d4af57d11c5122e2ab',
      stakeAccountId:
          '0x73478b9dd06ce5bb8ba1f485ce5742667d20b5b9a177c48ace31e651079f213d',
    ),
  ),
  InstitutionInfo(
    cidFullName: '兴安省公民储备银行',
    cidShortName: '兴安省储行',
    cidFullNameEn: 'Xingan Provincial Citizen Reserve Bank',
    cidShortNameEn: 'Xingan Provincial Reserve Bank',
    cidNumber: 'XA001-PRB0Q-928028839-2026',
    orgType: OrgType.prb,
    accounts: InstitutionAccounts(
      mainAccountId:
          '0x4123d536f6277e041f1b983274fa77ecb004e698e8195bf81263277a3e92a750',
      feeAccountId:
          '0xeed8acdd92edf647e50c814d184dcb945d3144ec501f71755d511e03fd25b1bc',
      stakeAccountId:
          '0xdf07ab53cd4108f5b31235240a8ecd0647f796c24e381ad761eaecb1cadf82eb',
    ),
  ),
  InstitutionInfo(
    cidFullName: '合江省公民储备银行',
    cidShortName: '合江省储行',
    cidFullNameEn: 'Hejiang Provincial Citizen Reserve Bank',
    cidShortNameEn: 'Hejiang Provincial Reserve Bank',
    cidNumber: 'HJ001-PRB0I-089279108-2026',
    orgType: OrgType.prb,
    accounts: InstitutionAccounts(
      mainAccountId:
          '0xa2f41e35019070029a4fc5a56b379973d51c48a5dab940a010bdd8e28c4ec434',
      feeAccountId:
          '0x0ef2de0db2ef2fbd6b077f92eff51fce641809d5bc9017cb31df2f47842daf5e',
      stakeAccountId:
          '0xb06c0d382b8703a08a86d18b15431996d4e63eabf460ffe1f423520f9a288c34',
    ),
  ),
];

/// 其它固定治理机构（不进入治理 tab 联合投票列表）。
const List<InstitutionInfo> kFixedGovernanceInstitutions = [
  InstitutionInfo(
    cidFullName: '总统府联邦注册局',
    cidShortName: '联邦注册局',
    cidFullNameEn: 'Federal Registry Bureau of the Presidential Office',
    cidShortNameEn: 'Federal Registry Bureau',
    cidNumber: 'ZS001-FRG07-249474503-2026',
    orgType: OrgType.institution,
    adminAccountCode: 'FRG',
    accounts: InstitutionAccounts(
      mainAccountId:
          '0x831af9dc35a112bf5152051d672e84ff803cea53952c199691c7aff246e4cd29',
      feeAccountId:
          '0x55d55d4b4e5ea2a9952c991c6568954a9be7efe469e45edc834abbb937eaa1a3',
    ),
  ),
  InstitutionInfo(
    cidFullName: '中华民族联邦共和国司法院',
    cidShortName: '国家司法院',
    cidFullNameEn:
        'Judicial Yuan of the Federal Republic of the Chinese Nation',
    cidShortNameEn: 'National Judicial Yuan',
    cidNumber: 'ZS001-NJD0T-052283563-2026',
    orgType: OrgType.institution,
    adminAccountCode: 'NJD',
    accounts: InstitutionAccounts(
      mainAccountId:
          '0xeeae43b9f99f561836366bdd3fda3f3a4dccf59cf58cd7e45204c4f6b2283c3a',
      feeAccountId:
          '0xa87bc7fc0c5018b7d7dee14d2b6f1695da04d93719e12db394c802894040c9ae',
    ),
  ),
];
