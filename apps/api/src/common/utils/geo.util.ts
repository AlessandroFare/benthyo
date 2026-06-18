export interface Coordinates {
  lat: number;
  lng: number;
}

/**
 * Parses PostGIS WKT "POINT(lng lat)" or GeoJSON Point into coordinates.
 */
export function parseLocation(
  location: string | { type: string; coordinates: [number, number] } | null,
): Coordinates | null {
  if (!location) {
    return null;
  }

  if (typeof location === 'object' && location.type === 'Point') {
    const [lng, lat] = location.coordinates;
    return { lat, lng };
  }

  if (typeof location === 'string') {
    const match = location.match(/POINT\s*\(\s*([-\d.]+)\s+([-\d.]+)\s*\)/i);
    if (match) {
      return { lat: parseFloat(match[2]), lng: parseFloat(match[1]) };
    }
  }

  return null;
}

export function toGeoJsonPoint(lat: number, lng: number): {
  type: 'Point';
  coordinates: [number, number];
} {
  return { type: 'Point', coordinates: [lng, lat] };
}
