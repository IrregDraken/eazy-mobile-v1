import type { LocationProvider, ProviderLocationResult } from '../types.js';

export class UnavailableLocationProvider implements LocationProvider {
  getCapabilities() {
    return { available: false, reverseGeocode: false, search: false } as const;
  }

  async reverseGeocode(_input: { latitude: number; longitude: number }): Promise<ProviderLocationResult> {
    throw new Error('Location provider is not configured');
  }

  async search(_input: { query: string; limit: number }): Promise<ProviderLocationResult[]> {
    throw new Error('Location provider is not configured');
  }
}
