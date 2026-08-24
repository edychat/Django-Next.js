/**
 * Platform-agnostic storage interface
 * Works with localStorage (web) or AsyncStorage (React Native)
 */

/**
 * Storage interface that can be implemented for different platforms
 */
export interface IStorage {
  getItem(key: string): Promise<string | null>;
  setItem(key: string, value: string): Promise<void>;
  removeItem(key: string): Promise<void>;
}

/**
 * Web storage implementation using localStorage
 */
export class WebStorage implements IStorage {
  async getItem(key: string): Promise<string | null> {
    if (typeof window === 'undefined') return null;
    return localStorage.getItem(key);
  }

  async setItem(key: string, value: string): Promise<void> {
    if (typeof window === 'undefined') return;
    localStorage.setItem(key, value);
  }

  async removeItem(key: string): Promise<void> {
    if (typeof window === 'undefined') return;
    localStorage.removeItem(key);
  }
}

/**
 * Storage manager that provides high-level storage operations
 */
export class StorageManager {
  private storage: IStorage;

  constructor(storage: IStorage) {
    this.storage = storage;
  }

  /**
   * Save data to storage
   */
  async save(key: string, data: any): Promise<void> {
    try {
      await this.storage.setItem(key, JSON.stringify(data));
    } catch (error) {
      console.error('Error saving data:', error);
    }
  }

  /**
   * Load data from storage
   */
  async load<T = any>(key: string): Promise<T | null> {
    try {
      const stored = await this.storage.getItem(key);
      if (stored) {
        return JSON.parse(stored) as T;
      }
    } catch (error) {
      console.error('Error loading data:', error);
    }
    return null;
  }

  /**
   * Remove data from storage
   */
  async remove(key: string): Promise<void> {
    try {
      await this.storage.removeItem(key);
    } catch (error) {
      console.error('Error removing data:', error);
    }
  }
}

// Export a default web storage instance for convenience
export const webStorage = new WebStorage();
export const storageManager = new StorageManager(webStorage);
