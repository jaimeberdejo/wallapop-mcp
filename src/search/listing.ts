import type { RawSearchItem } from "./types.js";

export interface Listing {
  id: string;
  title: string;
  description: string;
  price: number;
  currency: string;
  imageUrl: string;
  url: string;
  location: {
    city: string;
    postalCode: string;
    countryCode: string;
  };
  condition: string | undefined;
  createdAt: string;
}

export function normalizeItem(raw: RawSearchItem): Listing {
  return {
    id: raw.id,
    title: raw.title,
    description: raw.description,
    price: raw.price.amount,
    currency: raw.price.currency,
    imageUrl: raw.images[0]!.urls.big,
    url: `https://es.wallapop.com/item/${raw.web_slug}`,
    location: {
      city: raw.location.city,
      postalCode: raw.location.postal_code,
      countryCode: raw.location.country_code,
    },
    condition: raw.condition,
    createdAt: new Date(raw.created_at).toISOString(),
  };
}
