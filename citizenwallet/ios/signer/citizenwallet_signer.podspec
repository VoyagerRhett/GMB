#
# CitizenWallet 冷钱包 sr25519 原生签名静态库（schnorrkel）。
#
# 实现来自 citizenwallet/rust/src/sr25519.rs（由公民钱包独立维护），
# 由 scripts/build-signer-native.sh ios 交叉编译产出 libcitizenwallet_signer.a。
#
# 为什么用静态库而不是 dylib：裸 .dylib 需要嵌入 App 并单独代码签名，且 App Store
# 要求动态库必须包在 .framework 里；静态库直接链进 App 二进制，无这些坑。
# `-force_load` 与逐符号 `-u` 保证两组共 8 个 FFI 符号不被链接器当未引用剔除，
# Dart 侧因此可用 DynamicLibrary.process() 直接取到。
#
# 符号检查要查对文件（查错了会误判成"没链接进去"）：
#   Debug   → Runner.app/Runner.debug.dylib   （Runner 只是 ~70KB 启动壳，
#                                              新版 Xcode 的 debug 构建把代码放
#                                              进 debug dylib）
#   Release → Runner.app/Runner
#   命令：llvm-nm -g <binary> | grep -c citizen_sr25519   应为 4
#
native_dir = ENV['CITIZENWALLET_NATIVE_IOS_DIR'] || File.dirname(__FILE__)
library_path = File.expand_path('libcitizenwallet_signer.a', native_dir)

Pod::Spec.new do |s|
  s.name             = 'citizenwallet_signer'
  s.version          = '1.0.0'
  s.summary          = 'CitizenWallet sr25519 原生签名静态库'
  s.description      = <<-DESC
CitizenWallet 冷钱包 sr25519 原生签名（schnorrkel）。全端唯一实现，
使用公民钱包内部 citizenwallet/rust/src/sr25519.rs。
                       DESC
  s.homepage         = 'https://github.com/VoyagerRhett/GMB'
  s.license          = { :type => 'MIT' }
  s.author           = { 'voyager_rhett' => 'chinanation@icloud.com' }
  s.source           = { :path => '.' }
  s.platform         = :ios, '16.0'

  # CocoaPods 要求至少有一个源文件；用一个空的占位 .m，真正的实现全在 .a 里。
  s.source_files     = 'placeholder.m'
  s.vendored_libraries = library_path

  s.pod_target_xcconfig = {
    'DEFINES_MODULE' => 'YES',
    'EXCLUDED_ARCHS[sdk=iphonesimulator*]' => 'i386 x86_64',
  }
  # 两件事缺一不可，否则运行时 DynamicLibrary.process().lookup 找不到符号：
  # 1) -force_load：整库加载。App 侧没有任何 ObjC/Swift 代码引用这些 Rust 符号，
  #    普通链接会把整个 .a 当无用直接跳过。
  # 2) -u（force undefined）：把签名和账户用途钥共 8 个 FFI 符号声明为"必需"。**Release 开启
  #    -dead_strip**，即使 force_load 进来了，没被引用的符号仍会被剔除——
  #    表现为 Debug 正常、Release 静默失效（实测：release 二进制里连
  #    schnorrkel 特征串都没有）。-u 让链接器必须保留它们。
  # 必须写成 `-Wl,-u,<符号>` 而不是 `-u <符号>`：CocoaPods 会把重复的 `-u` 前缀
  # 去重合并成 `-u a b c d`，后三个于是被链接器当成文件名
  # （"No such file or directory: '_citizen_sr25519_public_key'"）。
  # `-Wl,-u,x` 每个都是独立的一个参数，不会被合并。
  s.user_target_xcconfig = {
    'OTHER_LDFLAGS' => "-force_load #{library_path} " \
                       '-Wl,-u,_citizen_sr25519_derive_hard ' \
                       '-Wl,-u,_citizen_sr25519_public_key ' \
                       '-Wl,-u,_citizen_sr25519_sign ' \
                       '-Wl,-u,_citizen_sr25519_verify ' \
                       '-Wl,-u,_account_crypto_derive_key ' \
                       '-Wl,-u,_account_crypto_x25519_public_key ' \
                       '-Wl,-u,_account_crypto_seal ' \
                       '-Wl,-u,_account_crypto_open',
  }
end
