// frontend/components/api.ts
  class ApiClient {
    private getBaseUrl(): string {
      // Always use NEXT_PUBLIC_API_URL if defined
      if (process.env.NEXT_PUBLIC_API_URL) {
        return process.env.NEXT_PUBLIC_API_URL;
      }

      if (process.env.NODE_ENV === 'development') {
        return 'http://localhost/api';
      }

      throw new Error('API base URL not configured. Please set NEXT_PUBLIC_API_URL environment variable.');
    }

    buildUrl(path: string): string {
      const baseUrl = this.getBaseUrl();
      const normalizedPath = path.startsWith('/') ? path : `/${path}`;
      return `${baseUrl}${normalizedPath}`;
    }

    async getCSRFToken(): Promise<string> {
      try {
        // Use the csrf endpoint without /api prefix since buildUrl will handle it
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

    // Convenience methods
    async get(path: string) {
      const url = this.buildUrl(path);
      return this.fetchWithAuth(url);
    }

    async post(path: string, data: any) {
      const url = this.buildUrl(path);
      return this.fetchWithAuth(url, {
        method: 'POST',
        body: JSON.stringify(data),
      });
    }

    async put(path: string, data: any) {
      const url = this.buildUrl(path);
      return this.fetchWithAuth(url, {
        method: 'PUT',
        body: JSON.stringify(data),
      });
    }

    async delete(path: string) {
      const url = this.buildUrl(path);
      return this.fetchWithAuth(url, {
        method: 'DELETE',
      });
    }
  }

  export const apiClient = new ApiClient();