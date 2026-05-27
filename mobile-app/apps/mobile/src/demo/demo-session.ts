import type { Session, SessionMessage, SessionSummary } from '@pai/shared-types';
import { buildPreviewFromMessages } from '../lib/session-preview';

export const DEMO_SESSION_ID = 'demo-preview';

const now = Date.now();

export const demoSessionSummary: SessionSummary = {
  id: DEMO_SESSION_ID,
  title: 'Demo Conversation',
  updatedAt: new Date(now).toISOString(),
  lastMessagePreview: 'Preview chat bubbles, code, tools, and errors.',
  messageCount: 6,
};

export function buildDemoSessionSummary(messages: SessionMessage[]): SessionSummary {
  const { preview, count } = buildPreviewFromMessages(messages);
  return {
    id: DEMO_SESSION_ID,
    title: 'Demo Conversation',
    updatedAt: new Date().toISOString(),
    lastMessagePreview: preview,
    messageCount: count,
  };
}

export const demoSession: Session = {
  id: DEMO_SESSION_ID,
  title: 'Demo Conversation',
  status: 'active',
  createdAt: new Date(now - 5 * 60_000).toISOString(),
  updatedAt: new Date(now).toISOString(),
  metadata: {
    source: 'local-demo',
    tags: ['demo', 'preview'],
  },
};

export const demoMessages: SessionMessage[] = [
  {
    id: 'demo-msg-1',
    sessionId: DEMO_SESSION_ID,
    role: 'assistant',
    createdAt: new Date(now - 4 * 60_000).toISOString(),
    parts: [
      {
        type: 'text',
        text: 'Welcome to the local demo session. This lets you validate the mobile UI without configuring any backend server.',
      },
    ],
  },
  {
    id: 'demo-msg-2',
    sessionId: DEMO_SESSION_ID,
    role: 'user',
    createdAt: new Date(now - 3 * 60_000).toISOString(),
    parts: [{ type: 'text', text: 'Show me what code blocks look like.' }],
  },
  {
    id: 'demo-msg-3',
    sessionId: DEMO_SESSION_ID,
    role: 'assistant',
    createdAt: new Date(now - 2 * 60_000).toISOString(),
    parts: [
      { type: 'text', text: 'Here is a small TypeScript example:' },
      {
        type: 'code',
        language: 'typescript',
        code: "function greet(name: string) {\n  return 'Hello, ' + name;\n}\nconsole.log(greet('PAI'));",
      },
    ],
  },
  {
    id: 'demo-msg-4',
    sessionId: DEMO_SESSION_ID,
    role: 'assistant',
    createdAt: new Date(now - 90_000).toISOString(),
    parts: [
      {
        type: 'tool_call',
        toolName: 'read_file',
        args: { path: 'TECHNICAL_PLAN.md' },
        callId: 'call-demo-1',
      },
      {
        type: 'tool_result',
        callId: 'call-demo-1',
        result: { ok: true, bytesRead: 2048 },
      },
    ],
  },
  {
    id: 'demo-msg-5',
    sessionId: DEMO_SESSION_ID,
    role: 'assistant',
    createdAt: new Date(now - 45_000).toISOString(),
    parts: [
      {
        type: 'text',
        text: "## Markdown Support\n\nThis message demonstrates **bold**, *italic*, and `inline code` formatting.\n\n### Features\n- Headers at multiple levels\n- **Bold** and *italic* text\n- `Inline code` snippets\n- [Tappable links](https://example.com)\n\nAll styled with the current Material-3 theme tokens.",
      },
    ],
  },
  {
    id: 'demo-msg-6',
    sessionId: DEMO_SESSION_ID,
    role: 'assistant',
    createdAt: new Date(now - 30_000).toISOString(),
    parts: [
      {
        type: 'permission_request',
        requestId: 'perm-demo-1',
        action: 'Open browser',
        resource: 'https://example.com',
        description: 'This is a sample permission card for layout validation.',
      },
      {
        type: 'question',
        questionId: 'question-demo-1',
        text: 'Which style feels clearest on the phone?',
        options: ['Compact', 'Balanced', 'Detailed'],
      },
      {
        type: 'error',
        message: 'Sample error rendering for edge-case validation.',
        code: 'DEMO_PREVIEW',
      },
    ],
  },
];
