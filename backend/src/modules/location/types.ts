import type { ProviderLocationResult } from '../../providers/interfaces.js';

export type { LocationProvider, LocationProviderCapabilities, ProviderLocationResult } from '../../providers/interfaces.js';

export interface PublicLocationResult {
  formattedAddress?: string;
  city?: string;
  region?: string;
  country?: string;
  countryCode?: string;
}

export interface LocationRepositoryContract {
  toPublicResult(result: ProviderLocationResult): PublicLocationResult;
}
