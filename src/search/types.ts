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

// The observed live shape (verified against real api/v3/search responses). Presentation-only
// fields (bump, favorited, is_top_profile, taxonomy, reserved, shipping, is_favoriteable,
// is_refurbished, has_warranty, user_id, category_id, modified_at) are typed loosely as
// `unknown` — present on the wire, deliberately unread by normalizeItem.
export interface RawSearchItem {
  id: string;
  title: string;
  description: string;
  price: { amount: number; currency: string };
  images: Array<{
    id: string;
    urls: { small: string; medium: string; big: string };
  }>;
  location: {
    latitude: number;
    longitude: number;
    postal_code: string;
    city: string;
    region: string;
    country_code: string;
  };
  web_slug: string;
  /** Epoch milliseconds. */
  created_at: number;
  /** Not present on any raw item observed live — kept optional, read through if Wallapop
   *  ever adds it for some category. */
  condition?: string;
  user_id?: unknown;
  category_id?: unknown;
  modified_at?: unknown;
  reserved?: unknown;
  shipping?: unknown;
  bump?: unknown;
  favorited?: unknown;
  taxonomy?: unknown;
  is_favoriteable?: unknown;
  is_refurbished?: unknown;
  is_top_profile?: unknown;
  has_warranty?: unknown;
}

export interface RawSearchResponse {
  data: {
    section: {
      payload: {
        items: RawSearchItem[];
      };
    };
  };
  meta?: {
    /** Opaque pagination cursor for the next page — passed through untouched. */
    next_page?: string;
  };
}

export interface SearchToolInput extends SearchInput {
  /** Default 40, clamped to a 200 cap. */
  maxResults?: number;
}
