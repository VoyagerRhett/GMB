# GitHub 工作流入口

GitHub 只发现 `.github/workflows` 目录中的工作流，因此本仓库固定只保留：

- `workflows/repository.yml`：唯一入口，只接收塔塔控制台带短期读取租约的显式调度，按租约固定 TATA 提交并调用 `.tata-flow/tataconsole/flows` 中的中央流程。

代码必须先通过本机全仓门禁才允许推送；推送后由塔塔控制台显式发起远端全仓门禁，禁止自动 `push` 门禁读取漂移的 TATA `main`。

禁止在 `.github` 增加产品级 Workflow、脚本副本、测试目录或产品编译、签名、打包实现。
