export interface SearchInput {
  keywords?: string;
  categoryId?: number;
  minPrice?: number;
  maxPrice?: number;
  distanceInKm?: number;
  orderBy?: string;
  latitude?: number;
  longitude?: number;
  /** Opaque pagination cursor — passed through untouched, never decoded/reconstructed. */
  nextPage?: string;
}

export interface BuiltSearchRequest {
  url: URL;
  headers: Record<string, string>;
}
