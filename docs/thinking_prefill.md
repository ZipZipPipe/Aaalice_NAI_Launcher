# DeepSeek 每轮思考预填

开启现有助手预填设置并选择 DeepSeek 思考等级后，每次聊天模型请求都从用户填写的思考前缀继续，包括工具结果返回后的续跑。空格、换行原样保留；后台摘要显式不使用预填。设置的保存、导入、导出与云同步边界保持原有协议。

## 请求边界

发送到官方 `/beta/chat/completions` 的最后一条消息为：

```json
{"role":"assistant","content":"","reasoning_content":"用户填写的思考前缀","prefix":true}
```

`thinking.type` 必须为 `enabled`。用户关闭思考时，在发送请求前报告错误，不静默切换为正文预填。自定义 DeepSeek 网关保留用户配置的 URL，由网关决定是否支持相同的扩展。

DeepSeek 的原生前缀续写与原生工具上下文不能同时使用。预填启用时，应用层适配器把工具定义放入文本协议说明，并把历史 `tool_calls`、工具结果转换为普通消息；请求不携带原生 `tools`、`tool_choice` 或 `tool` 角色。会话内部仍保存标准工具调用与工具结果，不改动 Harness 类型或持久化格式。关闭预填后继续使用原有原生接口。

## 文本工具协议

需要执行工具时，模型正文只能包含下面的完整区块：

```text
<launcher_tool_calls>[{"name":"工具名称","arguments":{}}]</launcher_tool_calls>
```

普通最终回答保持文本流式输出。工具请求缓冲至响应正常以 `stop` 结束后才解析，并转换为 `AgentWireToolCallDone`；未知工具、非对象参数、无效 JSON、残缺区块或异常结束均不发出可执行事件。工具参数的业务 schema 校验与权限确认由原有执行路径完成。批次使用客户端生成的唯一调用 ID，历史调用与结果通过同一 ID 关联。

工具结果作为包含 `launcher_tool_result` 的普通用户消息回传，保留调用 ID、工具名、错误标志和文本。模型允许图片输入时，用户附件与工具图片继续使用图片内容块；关闭图片输入时不发送图片字节。

预填只在当前请求尾部注入，绝不修改历史。桥接层在收到有效响应后将前缀与生成的思考合并一次，保存为 `AssistantThinkingContent`；前缀不会混入回答正文。重试重新构造当前请求，不向历史追加独立的预填消息。

## 代码与验证入口

- `agent_prefill.dart`：确定每个响应边界的前缀，排除摘要。
- `thinking_prefill_messages.dart`：原生思考前缀、文本工具定义与历史转换。
- `prefill_tool_decoder.dart`：流式区分正文和工具请求，完整结束后解析工具。
- `openai_chat_completions_adapter.dart`：HTTP 请求与响应适配。
- `agent_stream_bridge.dart`：思考前缀合并、UI 事件与标准消息生成。

对应测试覆盖请求字段、每轮续跑、重试不重复、任意分片位置、工具权限、参数校验、图片、截断与取消。`thinking_prefill_integration_test.dart` 使用真实 Agent loop 和模拟的严格服务端协议检查；它不能证明真实 DeepSeek 一定遵守文本工具协议。服务端验收仍需实际模型完成多轮任务。

官方依据：[对话前缀续写](https://api-docs.deepseek.com/zh-cn/guides/chat_prefix_completion/)、[请求校验与思考续写阶段](https://github.com/deepseek-ai/deepseek-recipe/blob/935817c66f5d6e64838f419692545f06787e485f/deepseek-recipe/src/protocol/openai/chat_completion/request/convert.rs)。
