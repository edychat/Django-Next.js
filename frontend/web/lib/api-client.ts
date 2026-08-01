/**
 * Platform-agnostic API client — works in Next.js (web) and React Native (mobile).
 *
 * Mobile apps import this via the @shared alias wired in metro.config.base.js:
 *   import { apiClient } from '@shared/api-client'
 *
 * Web imports it directly or via the @shared/* path alias in tsconfig.json.
 */

export interface ApiResponse<T = unknown> {
  data?: T;
  error?: string;
}

const getBaseUrl = (): string =>
  (typeof process !== 'undefined' &&
    (process.env.NEXT_PUBLIC_API_URL || process.env.EXPO_PUBLIC_API_URL)) ||
  '/api';

async function request<T>(
  path: string,
  options: RequestInit = {},
): Promise<ApiResponse<T>> {
  const url = `${getBaseUrl()}${path.startsWith('/') ? path : `/${path}`}`;
  try {
    const res = await fetch(url, {
      credentials: 'include',
      headers: { 'Content-Type': 'application/json', ...options.headers },
      ...options,
    });
    const data = await res.json().catch(() => null);
    if (!res.ok) return { error: data?.error ?? `HTTP ${res.status}` };
    return { data };
  } catch (err) {
    return { error: 'Network error' };
  }
}

export const apiClient = {
  get:    <T>(path: string)                   => request<T>(path),
  post:   <T>(path: string, body?: unknown)   => request<T>(path, { method: 'POST',   body: JSON.stringify(body) }),
  put:    <T>(path: string, body?: unknown)   => request<T>(path, { method: 'PUT',    body: JSON.stringify(body) }),
  patch:  <T>(path: string, body?: unknown)   => request<T>(path, { method: 'PATCH',  body: JSON.stringify(body) }),
  delete: <T>(path: string)                   => request<T>(path, { method: 'DELETE' }),
};

export default apiClient;
