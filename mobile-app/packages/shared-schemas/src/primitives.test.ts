import { describe, it, expect } from 'bun:test';
import {
  isString,
  isNumber,
  isBoolean,
  isObject,
  isArray,
  isOptional,
  isLiteral,
} from './primitives';

describe('isString', () => {
  it('accepts a string', () => {
    expect(isString('hello')).toBe(true);
  });

  it('rejects numbers', () => {
    expect(isString(42)).toBe(false);
  });

  it('rejects null', () => {
    expect(isString(null)).toBe(false);
  });

  it('rejects undefined', () => {
    expect(isString(undefined)).toBe(false);
  });

  it('rejects objects', () => {
    expect(isString({})).toBe(false);
  });

  it('rejects booleans', () => {
    expect(isString(true)).toBe(false);
  });
});

describe('isNumber', () => {
  it('accepts a finite number', () => {
    expect(isNumber(42)).toBe(true);
    expect(isNumber(0)).toBe(true);
    expect(isNumber(-3.14)).toBe(true);
  });

  it('rejects NaN', () => {
    expect(isNumber(NaN)).toBe(false);
  });

  it('rejects Infinity', () => {
    expect(isNumber(Infinity)).toBe(false);
    expect(isNumber(-Infinity)).toBe(false);
  });

  it('rejects strings', () => {
    expect(isNumber('42')).toBe(false);
  });

  it('rejects null', () => {
    expect(isNumber(null)).toBe(false);
  });
});

describe('isBoolean', () => {
  it('accepts true and false', () => {
    expect(isBoolean(true)).toBe(true);
    expect(isBoolean(false)).toBe(true);
  });

  it('rejects strings', () => {
    expect(isBoolean('true')).toBe(false);
    expect(isBoolean('false')).toBe(false);
  });

  it('rejects numbers', () => {
    expect(isBoolean(1)).toBe(false);
    expect(isBoolean(0)).toBe(false);
  });

  it('rejects null', () => {
    expect(isBoolean(null)).toBe(false);
  });

  it('rejects undefined', () => {
    expect(isBoolean(undefined)).toBe(false);
  });

  it('rejects objects', () => {
    expect(isBoolean({})).toBe(false);
    expect(isBoolean([])).toBe(false);
  });
});

describe('isObject', () => {
  it('accepts plain objects', () => {
    expect(isObject({})).toBe(true);
    expect(isObject({ a: 1 })).toBe(true);
  });

  it('rejects null', () => {
    expect(isObject(null)).toBe(false);
  });

  it('rejects arrays', () => {
    expect(isObject([])).toBe(false);
    expect(isObject([1, 2])).toBe(false);
  });

  it('rejects strings', () => {
    expect(isObject('hello')).toBe(false);
  });

  it('rejects numbers', () => {
    expect(isObject(42)).toBe(false);
  });
});

describe('isArray', () => {
  it('accepts empty arrays', () => {
    expect(isArray([], isString)).toBe(true);
  });

  it('accepts homogeneous arrays', () => {
    expect(isArray(['a', 'b'], isString)).toBe(true);
    expect(isArray([1, 2, 3], isNumber)).toBe(true);
  });

  it('rejects non-arrays', () => {
    expect(isArray('not array', isString)).toBe(false);
    expect(isArray(42, isNumber)).toBe(false);
    expect(isArray(null, isString)).toBe(false);
  });

  it('rejects mixed arrays', () => {
    expect(isArray([1, 'two'], isNumber)).toBe(false);
  });
});

describe('isOptional', () => {
  const optString = isOptional(isString);

  it('accepts undefined', () => {
    expect(optString(undefined)).toBe(true);
  });

  it('accepts the underlying type', () => {
    expect(optString('hello')).toBe(true);
  });

  it('rejects other types', () => {
    expect(optString(42)).toBe(false);
    expect(optString(null)).toBe(false);
  });
});

describe('isLiteral', () => {
  const isStatus = isLiteral('active', 'completed', 'error');

  it('accepts valid literals', () => {
    expect(isStatus('active')).toBe(true);
    expect(isStatus('completed')).toBe(true);
    expect(isStatus('error')).toBe(true);
  });

  it('rejects invalid strings', () => {
    expect(isStatus('pending')).toBe(false);
    expect(isStatus('')).toBe(false);
  });

  it('rejects non-strings', () => {
    expect(isStatus(42)).toBe(false);
    expect(isStatus(null)).toBe(false);
    expect(isStatus(undefined)).toBe(false);
  });
});
