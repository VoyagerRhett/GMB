# smoldot Dart 示例

`smoldot_example.dart` 来源于 CitizenApp 已验证示例。Dart 包边界合并后只机械调整为
CitizenSDK 内部 import 与根测试夹具路径；示例行为保持不变。该文件是来源记录，不是
CitizenSDK 的公共接入入口，产品代码只应导入 `package:citizen_sdk/citizen_sdk.dart`。

禁止在本目录写入生成文件。本机 CitizenSDK 编译、测试和工具记录只能进入
`CITIZENSDK_NATIVE_OUTPUT_DIR`，GitHub 流程只能写入对应 Runner 临时目录。
