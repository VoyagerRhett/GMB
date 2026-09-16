# GitHub 工作流入口

GitHub 只发现 `.github/workflows` 目录中的工作流，因此本仓库固定只保留：

- `workflows/repository.yml`：本仓产品CI与Release唯一入口，只检出本仓源码并调用各产品`scripts`中的准确实现。

授权开发者可以直接发起准确产品、平台和流程；CI不得接收Release字段，Release必须绑定准确源码提交和成功CI Run。

禁止在 `.github` 增加产品级Workflow、依赖、工具、脚本副本、Start、Publish或仓库操作实现。
