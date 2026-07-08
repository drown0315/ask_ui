import type { SendChatMessageRequest } from '../services/bridgeTypes.ts';
import type { SelectionComment } from '../selection-comments/selectionCommentTypes.ts';

export type ChatMessagePayload =
  | SendChatMessageRequest
  | {
      text: string;
    };

export function buildChatMessagePayload({
  projectRoot,
  selectionComments,
  text,
}: {
  projectRoot: string;
  selectionComments: SelectionComment[];
  text: string;
}): ChatMessagePayload {
  if (selectionComments.length === 0) {
    return { text };
  }

  const trimmedText = text.trim();

  return {
    context: {
      projectRoot,
    },
    parts: [
      ...selectionComments.map((comment) => ({
        type: 'selection_comment' as const,
        attachment: {
          id: comment.id,
          commentText: comment.text,
          selectedWidget: {
            id: comment.widgetId,
            displayLabel: comment.widgetLabel,
            ...(comment.sourceLocation
              ? {
                  sourceLocation: getProjectRelativeSourceLocation(
                    comment.sourceLocation,
                    projectRoot,
                  ),
                }
              : {}),
            ...(comment.visibleText ? { visibleText: comment.visibleText } : {}),
            ...(comment.semanticInfo
              ? { semanticInfo: comment.semanticInfo }
              : {}),
          },
          snapshot:
            comment.snapshot.status === 'available'
              ? {
                  status: 'available' as const,
                  path: comment.snapshot.path,
                }
              : {
                  status: 'unavailable' as const,
                },
        },
      })),
      ...(trimmedText.length > 0
        ? [
            {
              type: 'text' as const,
              text: trimmedText,
            },
          ]
        : []),
    ],
  };
}

function getProjectRelativeSourceLocation(
  sourceLocation: string,
  projectRoot: string,
): string {
  const trimmedSourceLocation = sourceLocation.trim();
  const trimmedProjectRoot = projectRoot.trim().replace(/\/+$/, '');

  if (
    trimmedProjectRoot.length > 0 &&
    trimmedSourceLocation.startsWith(`${trimmedProjectRoot}/`)
  ) {
    return trimmedSourceLocation.slice(trimmedProjectRoot.length + 1);
  }

  return trimmedSourceLocation;
}
