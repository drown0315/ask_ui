export function ChatPanelHeader({
  agentStatusLabel,
  agentStatusValue,
  title,
}: {
  agentStatusLabel: string;
  agentStatusValue: string;
  title: string;
}) {
  return (
    <header className="chat-panel-header">
      <div className="chat-panel-title">{title}</div>
      <div className="agent-status" aria-label={agentStatusLabel}>
        <span className="agent-status-dot" aria-hidden="true" />
        <span className="agent-status-label">{agentStatusLabel}</span>
        <span className="agent-status-value">{agentStatusValue}</span>
      </div>
    </header>
  );
}
