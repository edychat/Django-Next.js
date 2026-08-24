/**
 * Shared TypeScript type definitions
 * Used by both web and mobile applications
 */

// Coordinates type
export interface Coordinates {
  lat: number;
  lng: number;
}

// API Response types
export interface ApiResponse<T = any> {
  data?: T;
  error?: string;
  message?: string;
}

// User types
export interface User {
  id: number;
  email: string;
  name: string;
  phone?: string;
}

// Payment method types
export interface PaymentMethod {
  id: string;
  type: 'card' | 'cash';
  last4?: string;
  brand?: string;
  default?: boolean;
}

// Subscription types
export interface Subscription {
  id: string;
  type: string;
  status: 'active' | 'inactive' | 'cancelled';
  startDate: string;
  endDate?: string;
}

// Map-related types
export interface MapLocation {
  coordinates: Coordinates;
  address: string;
}

// Navigation types for mobile
export type RootStackParamList = {
  Home: undefined;
  Profile: undefined;
  Settings: undefined;
};
