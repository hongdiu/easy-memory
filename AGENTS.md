# AGENTS.md — 任务执行总纲



状态机：IDLE → PLAN(方案) → WAIT(批准) → CODE(改+测+脚本) → BUILD(构建) → FIX(自动修≤5轮) → DONE(交付)。
不可逆、不可跳。

## 0. 验证方式（关键约定）
- 本机**不安装** Flutter SDK，也不要在本地寻找/下载 Flutter 环境。
- 代码改完直接 `git commit` + `git push`，由 **GitHub Actions CI** 编译验证：
  - `.github/workflows/ci.yml` → `flutter analyze` + `flutter test`
  - `.github/workflows/build-*.yml` → 各平台 release 构建
- CI 失败时用 `curl https://api.github.com/repos/hongdiu/easy-memory/actions/runs/...` 查状态，日志贴给用户核对。
- 依赖冲突（pub get 失败）先从 pub.dev API 查版本约束再改 pubspec。

## 1. 铁律（违禁即错）
- 无方案无批准 = 禁改代码（方案必须含：目标/范围/步骤/风险）。
- 禁改无关代码。
- 编译/测试不通过 = 任务未完成。完成时执行 git add。
- 中文回答。

## 2. 自动修复边界（关键决策点）
- 免批自动修：编译报错、类型/API错误、依赖缺失、测试语法错。
- 必须报备修：影响业务逻辑、UI行为、数据存储的功能性变更。

## 3. 硬性产出（缺一不可）
- 大任务拆子任务（由简至繁），每步独立编译通过再下一步。
- 生成测试用例→ 输出 build_test.sh 跑全测 → 捕获失败自动修≤5轮（功能变更需报备）→ 最终交付通过代码+测试+日志。



**响应前自检（必问）**：
当前状态？方案获批否？编译过了？轮次超限否？
