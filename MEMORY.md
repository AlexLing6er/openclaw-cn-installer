# MEMORY

## User / Project Focus
- Douhao is exploring an OpenClaw-based business automation setup for a TCM consultation funnel across pre-sales, in-sales, and post-sales stages.
- Core channel goal is China private-domain operations, with emphasis on personal WeChat / WeCom / Official Account compatibility and mainland-hosted APIs/servers.

## Technical Findings (2026-03-03)
- OpenClaw has a documented community WeChat plugin (`@icesword760/openclaw-wechat`) for personal-account connectivity (WeChatPadPro path).
- No direct built-in docs evidence yet for first-party WeCom or WeChat Official Account channels.
- Feishu is supported via plugin (`@openclaw/feishu`) and can use WebSocket event subscription (no public webhook required), useful as an enterprise alternative in China.
