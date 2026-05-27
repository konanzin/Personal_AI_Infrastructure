/**
 * OpenCode Mobile Notification Plugin
 *
 * Server-side plugin within the OpenCode ecosystem.
 * Observes events, filters, deduplicates, and sends push notifications.
 */

export type PluginConfig = {
  expoAccessToken: string;
  maxDedupeWindowMs: number;
};

export class MobileNotificationPlugin {
  private config: PluginConfig;

  constructor(config: PluginConfig) {
    this.config = config;
  }

  // TODO(M7): Implement event observation
  // TODO(M7): Implement parent-session filtering
  // TODO(M7): Implement deduplication
  // TODO(M7): Implement device registry
  // TODO(M7): Implement Expo push delivery
}
