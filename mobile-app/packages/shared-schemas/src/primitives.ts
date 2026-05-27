export function isString(v: unknown): v is string {
  return typeof v === 'string';
}

export function isNumber(v: unknown): v is number {
  return typeof v === 'number' && Number.isFinite(v);
}

export function isBoolean(v: unknown): v is boolean {
  return typeof v === 'boolean';
}

export function isObject(v: unknown): v is Record<string, unknown> {
  return typeof v === 'object' && v !== null && !Array.isArray(v);
}

export function isArray<T>(
  v: unknown,
  itemCheck: (item: unknown) => item is T
): v is T[] {
  return Array.isArray(v) && v.every(itemCheck);
}

export function isOptional<T>(
  check: (v: unknown) => v is T
): (v: unknown) => v is T | undefined {
  return (v: unknown): v is T | undefined => v === undefined || check(v);
}

export function isLiteral<T extends string>(
  ...values: T[]
): (v: unknown) => v is T {
  return (v: unknown): v is T =>
    typeof v === 'string' && values.includes(v as T);
}
