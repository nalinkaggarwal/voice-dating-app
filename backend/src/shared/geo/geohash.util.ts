// Minimal, dependency-free geohash decode + haversine distance -- WP3
// needs "is candidate within maxDistanceKm" using ONLY the coarse
// geohash already stored on Profile (never exact lat/long, per the
// product rule already documented on Profile.geohash). A geohash
// decodes to a bounding box, not a point -- this uses the box's center,
// which is exactly as precise as the stored geohash itself and no more.

const BASE32 = '0123456789bcdefghjkmnpqrstuvwxyz';

export interface LatLon {
  lat: number;
  lon: number;
}

export function decodeGeohash(geohash: string): LatLon {
  let evenBit = true;
  let latMin = -90, latMax = 90;
  let lonMin = -180, lonMax = 180;

  for (const char of geohash.toLowerCase()) {
    const idx = BASE32.indexOf(char);
    if (idx === -1) continue; // skip any stray invalid character rather than throw
    for (let bit = 4; bit >= 0; bit--) {
      const bitValue = (idx >> bit) & 1;
      if (evenBit) {
        const lonMid = (lonMin + lonMax) / 2;
        if (bitValue === 1) lonMin = lonMid; else lonMax = lonMid;
      } else {
        const latMid = (latMin + latMax) / 2;
        if (bitValue === 1) latMin = latMid; else latMax = latMid;
      }
      evenBit = !evenBit;
    }
  }

  return { lat: (latMin + latMax) / 2, lon: (lonMin + lonMax) / 2 };
}

const EARTH_RADIUS_KM = 6371;

export function haversineDistanceKm(a: LatLon, b: LatLon): number {
  const toRad = (deg: number) => (deg * Math.PI) / 180;
  const dLat = toRad(b.lat - a.lat);
  const dLon = toRad(b.lon - a.lon);
  const lat1 = toRad(a.lat);
  const lat2 = toRad(b.lat);

  const h =
    Math.sin(dLat / 2) ** 2 + Math.sin(dLon / 2) ** 2 * Math.cos(lat1) * Math.cos(lat2);
  return 2 * EARTH_RADIUS_KM * Math.asin(Math.sqrt(h));
}

/** Convenience: distance in km between two geohashes, or null if either
 * is missing/unparseable -- callers treat null as "can't verify distance". */
export function geohashDistanceKm(a: string | null | undefined, b: string | null | undefined): number | null {
  if (!a || !b) return null;
  try {
    return haversineDistanceKm(decodeGeohash(a), decodeGeohash(b));
  } catch {
    return null;
  }
}
