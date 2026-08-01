/**
 * Shared design tokens — used by both web (Tailwind/inline) and mobile (StyleSheet).
 * Mobile apps import via @shared/theme.
 */

export const colors = {
  primary:    '#2563eb',  // blue-600
  primaryDark:'#1e3a8a',  // blue-900
  success:    '#16a34a',  // green-600
  error:      '#ef4444',  // red-500
  warning:    '#eab308',  // yellow-500
  background: '#ffffff',
  surface:    '#f4f4f5',  // zinc-100
  text:       '#27272a',  // zinc-800
  textMuted:  '#71717a',  // zinc-500
  border:     '#e4e4e7',  // zinc-200
  white:      '#ffffff',
  black:      '#000000',
} as const;

export const spacing = {
  xs: 4, sm: 8, md: 16, lg: 24, xl: 32, '2xl': 48,
} as const;

export const borderRadius = {
  sm: 4, md: 8, lg: 12, xl: 16, full: 9999,
} as const;

export const theme = { colors, spacing, borderRadius } as const;
export type Theme = typeof theme;
export default theme;
