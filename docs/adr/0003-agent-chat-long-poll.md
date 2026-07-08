# Agent Chat Long-Poll

Ask UI will connect Chat to the launching Agent Session through a local queued-message model and an Agent Session Command long-poll loop. The web app records user chat messages and selected-widget context into the local workbench session; the Codex, Claude Code, or similar skill that launched the workbench keeps polling for those messages, applies the requested changes with its normal tools, and posts agent replies back into the same Chat.

This avoids making the browser call a coding-agent runtime directly and keeps code editing authority inside the original Agent Session. It also matches the review-loop shape proven by Lavish Editor: queued browser feedback is durable, polling can be restarted without losing messages, and agent replies can be synchronized back to Chat History.

The first version uses the poller as the readiness boundary: Chat can send only while one Agent Session poller is actively waiting for the Bridge Session, and a Bridge Session rejects additional concurrent pollers. Ask UI does not provide an offline message queue; if delivery to the active poller fails during send, the Web composer keeps the unsent content and the developer can retry after the Agent Session is ready again.

Agent replies are written back through Agent Session Commands, with the standard loop shaped as poll, process, reply, and poll again. A combined CLI command such as `agent poll --agent-reply "..."` can write the reply and immediately wait for the next message; command-level failures use a separate error path that writes a system message rather than pretending to be an agent reply.
