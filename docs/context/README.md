# context/ — 项目知识库

> 存放项目开发过程中需要反复查阅的稳定知识。  
> 只记录已确认的事实，不记录尚未稳定的设计草案。

## 当前文档

| 文件 | 内容 | 维护者 |
|------|------|--------|
| [`QUICK_CONTEXT.md`](QUICK_CONTEXT.md) | **速查首选**：关键参数、性能指标、日志分类 | 全员 |
| [`ARCHITECTURE.md`](ARCHITECTURE.md) | 五层架构、依赖规则、核心协议、数据链路 | 架构 |
| [`GLOSSARY.md`](GLOSSARY.md) | 核心类型与概念定义 | 开发 |
| [`MODEL_SPECS.md`](MODEL_SPECS.md) | Chinese-CLIP 模型技术参数 | 算法 |
| [`EDGE_CASES.md`](EDGE_CASES.md) | 已知陷阱与边界场景 | 全员 |
| [`BASELINE_TESTS.md`](BASELINE_TESTS.md) | 基线回归测试说明 | 测试 |

## 阅读顺序

1. **新成员**：`QUICK_CONTEXT.md` → `ARCHITECTURE.md` → `GLOSSARY.md`
2. **调试问题**：`EDGE_CASES.md` → 代码注释
3. **模型相关**：`MODEL_SPECS.md` → `BASELINE_TESTS.md`

## 维护原则

- **只放稳定知识**：已落地实现，不会频繁变化
- **标注信息来源**：关键数据标注提取自哪个文件
- **及时同步**：代码变更后立即更新对应 context 文档
- **分层清晰**：context/ 描述现状，topics/ 记录历史

## 与 topics/ 的分界

| 放 context/ | 放 topics/ |
|-------------|------------|
| 当前架构事实 | 架构决策过程与演进 |
| 模型参数 | 模型选型讨论 |
| 已知陷阱 | 问题排查记录 |
| 性能指标 | 性能优化专项 |
