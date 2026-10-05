import { AppError } from '../../middleware/errors.js';
import type { LocationProvider, LocationRepositoryContract, PublicLocationResult } from './types.js';

export class LocationService {
  constructor(private readonly provider: LocationProvider, private readonly repository: LocationRepositoryContract) {}

  capabilities() {
    try {
      const capability = this.provider.getCapabilities();
      return {
        providerAvailable: capability.available,
        reverseGeocodeAvailable: capability.available && capability.reverseGeocode,
        searchAvailable: capability.available && capability.search,
        persistentLocationSharingAvailable: false
      };
    } catch {
      return this.unavailable();
    }
  }

  async reverseGeocode(input: { latitude: number; longitude: number }): Promise<{ location: PublicLocationResult }> {
    if (!this.isAvailable('reverseGeocode')) return this.unavailable();
    try {
      const result = await this.provider.reverseGeocode(input);
      return { location: this.repository.toPublicResult(result) };
    } catch {
      return this.unavailable();
    }
  }

  async search(input: { query: string; limit: number }): Promise<{ items: PublicLocationResult[] }> {
    if (!this.isAvailable('search')) return this.unavailable();
    try {
      const results = await this.provider.search({ query: input.query, limit: input.limit });
      return { items: results.slice(0, input.limit).map(result => this.repository.toPublicResult(result)) };
    } catch {
      return this.unavailable();
    }
  }

  private isAvailable(operation: 'reverseGeocode' | 'search'): boolean {
    try {
      const capability = this.provider.getCapabilities();
      return capability.available && capability[operation];
    } catch {
      return false;
    }
  }

  private unavailable(): never {
    throw new AppError('SERVICE_UNAVAILABLE', 'Location provider is unavailable');
  }
}
