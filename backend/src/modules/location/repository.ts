import type { LocationRepositoryContract, PublicLocationResult } from './types.js';
import type { ProviderLocationResult } from '../../providers/interfaces.js';

const maxFieldLength: Record<keyof PublicLocationResult, number> = {
  formattedAddress: 500,
  city: 120,
  region: 120,
  country: 120,
  countryCode: 3
};

export class LocationRepository implements LocationRepositoryContract {
  toPublicResult(result: ProviderLocationResult): PublicLocationResult {
    const projected: PublicLocationResult = {};
    for (const key of Object.keys(maxFieldLength) as (keyof PublicLocationResult)[]) {
      const value = result[key];
      if (typeof value === 'string' && value.trim()) {
        if (key === 'countryCode' && !/^[A-Za-z]{2,3}$/.test(value.trim())) continue;
        projected[key] = key === 'countryCode'
          ? value.trim().toUpperCase()
          : value.trim().slice(0, maxFieldLength[key]);
      }
    }
    if (Object.keys(projected).length === 0) throw new Error('Location provider returned no usable public fields');
    return projected;
  }
}
