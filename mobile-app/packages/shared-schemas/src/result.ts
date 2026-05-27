export type SchemaResult<T> =
  | { success: true; data: T }
  | { success: false; errors: string[] };
