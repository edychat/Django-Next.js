// frontend/components/api.ts
class ApiClient {
  private getBaseUrl(): string {
    // Always respect NEXT_PUBLIC_API_URL if set, regardless of environment
    if (process.env.NEXT_PUBLIC_API_URL) {
      return process.env.NEXT_PUBLIC_API_URL;
    }
    // For development fallback, use localhost:8000
    if (process.env.NODE_ENV === 'development') {
      return 'http://localhost:8000/api';
    }
    // For production fallback, use the custom domain from environment variable
    const domain = process.env.NEXT_PUBLIC_DOMAIN;
    if (domain) {
      return `https://api.${domain}/api`;
    }
    // Final fallback - you might want to handle this case differently
    throw new Error('Domain not configured for production environment');
  }

  buildUrl(path: string): string {
    const baseUrl = this.getBaseUrl();
    const normalizedPath = path.startsWith('/') ? path : `/${path}`;
    return `${baseUrl}${normalizedPath}`;
  }

  async getCSRFToken(): Promise<string> {
    try {
      const url = this.buildUrl('/csrf/');
      console.log('🔗 Fetching CSRF token from:', url);

      const response = await fetch(url, {
        credentials: 'include',
        cache: 'no-cache',
      });

      if (response.ok) {
        const data = await response.json();
        return data.csrfToken || '';
      }
    } catch (error) {
      console.error('❌ Error fetching CSRF token:', error);
    }
    return '';
  }

  async fetchWithAuth(url: string, options: RequestInit = {}) {
    const defaultOptions: RequestInit = {
      credentials: 'include',
      headers: {
        'Content-Type': 'application/json',
        ...options.headers,
      },
      cache: 'no-cache',
    };

    // For non-GET requests, add CSRF token
    if (options.method && options.method !== 'GET') {
      const csrfToken = await this.getCSRFToken();
      if (csrfToken) {
        defaultOptions.headers = {
          ...defaultOptions.headers,
          'X-CSRFToken': csrfToken,
        };
      }
    }

    return fetch(url, {
      ...defaultOptions,
      ...options,
      headers: {
        ...defaultOptions.headers,
        ...options.headers,
      },
    });
  }
}

export const apiClient = new ApiClient();