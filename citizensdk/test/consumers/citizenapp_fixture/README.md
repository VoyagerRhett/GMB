# CitizenApp-shaped consumer fixture

本目录故意包含 CitizenApp 业务字段、storage key、SCALE 风格事件和 RuntimeCall 编码，以证明这些语义由
消费 App 持有。`CitizenAppFixture` 只把最终 storage key 与 opaque callData 交给 CitizenSDK 公开接口。
