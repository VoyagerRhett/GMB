# CitizenSDK 本地生成目录规则

- `.dart_tool` 不在本规则范围内。
- 禁止在 `/Users/rhett/GMB/citizensdk` 源码树中生成 `build`、`target` 或其它编译、测试目录。
- 禁止直接运行裸 `flutter test` 或 `cargo test`；统一使用 `scripts/test.sh`。
- 本地测试生成物统一写入`CITIZENSDK_TEST_WORK_DIR`指定的源码外测试目录。
- 不得为了测试复制 CitizenSDK 源码；测试必须直接读取产品源码并把生成物写到上述缓存目录。
