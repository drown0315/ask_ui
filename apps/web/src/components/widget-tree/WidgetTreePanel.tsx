import type { CSSProperties } from 'react';

type WidgetTreeNode = {
  id: string;
  label: string;
  kind: 'app' | 'framework';
  badge?: string;
  children?: WidgetTreeNode[];
};

const selectedNodeId = 'primary-action';

const widgetTree: WidgetTreeNode[] = [
  {
    id: 'root',
    label: '[root]',
    kind: 'framework',
    badge: 'R',
    children: [
      {
        id: 'app',
        label: 'AskUiDemoApp',
        kind: 'app',
        badge: 'A',
        children: [
          {
            id: 'material-app',
            label: 'MaterialApp',
            kind: 'framework',
            badge: 'M',
            children: [
              {
                id: 'theme',
                label: 'Theme',
                kind: 'framework',
                badge: 'T',
              },
              {
                id: 'scaffold',
                label: 'Scaffold',
                kind: 'framework',
                badge: 'S',
                children: [
                  {
                    id: 'home-screen',
                    label: 'HomeScreen',
                    kind: 'app',
                    badge: 'H',
                    children: [
                      {
                        id: 'app-bar',
                        label: 'AppHeader',
                        kind: 'app',
                        badge: 'A',
                      },
                      {
                        id: 'body',
                        label: 'SafeArea',
                        kind: 'framework',
                        badge: 'S',
                        children: [
                          {
                            id: 'content-column',
                            label: 'Column',
                            kind: 'framework',
                            badge: 'C',
                            children: [
                              {
                                id: 'hero-card',
                                label: 'WonderCard',
                                kind: 'app',
                                badge: 'W',
                              },
                              {
                                id: 'primary-action',
                                label: 'PrimaryActionButton',
                                kind: 'app',
                                badge: 'P',
                              },
                              {
                                id: 'secondary-link',
                                label: 'SecondaryTextLink',
                                kind: 'app',
                                badge: 'L',
                              },
                            ],
                          },
                        ],
                      },
                    ],
                  },
                ],
              },
            ],
          },
        ],
      },
    ],
  },
];

function WidgetTreeNodeRow({
  node,
  depth,
}: {
  node: WidgetTreeNode;
  depth: number;
}) {
  const isSelected = node.id === selectedNodeId;
  const hasChildren = Boolean(node.children?.length);
  const rowClassName = [
    'widget-tree-row',
    `widget-tree-row-${node.kind}`,
    isSelected ? 'widget-tree-row-selected' : '',
  ]
    .filter(Boolean)
    .join(' ');

  return (
    <li>
      <div
        className={rowClassName}
        style={{ '--tree-depth': depth } as CSSProperties}
      >
        <span className="widget-tree-toggle" aria-hidden="true">
          {hasChildren ? 'v' : ''}
        </span>
        <span className="widget-tree-branch" aria-hidden="true" />
        <span className="widget-tree-badge">{node.badge}</span>
        <span className="widget-tree-label">{node.label}</span>
      </div>
      {hasChildren ? (
        <ol className="widget-tree-list">
          {node.children?.map((child) => (
            <WidgetTreeNodeRow key={child.id} node={child} depth={depth + 1} />
          ))}
        </ol>
      ) : null}
    </li>
  );
}

export function WidgetTreePanel() {
  return (
    <aside className="workbench-panel widget-tree-panel">
      <div className="widget-tree-header">
        <div>
          <div className="widget-tree-title">Widget Tree</div>
          <div className="widget-tree-subtitle">Full Flutter tree prototype</div>
        </div>
        <button
          aria-label="Refresh widget tree"
          className="widget-tree-icon-button"
          type="button"
        >
          ↻
        </button>
      </div>
      <div className="widget-tree-search">
        <span aria-hidden="true" className="widget-tree-search-icon">
          ⌕
        </span>
        <input
          aria-label="Search widget tree"
          className="widget-tree-search-input"
          placeholder="Search widgets"
          type="search"
        />
      </div>
      <ol className="widget-tree-list widget-tree-root-list">
        {widgetTree.map((node) => (
          <WidgetTreeNodeRow key={node.id} node={node} depth={0} />
        ))}
      </ol>
    </aside>
  );
}
