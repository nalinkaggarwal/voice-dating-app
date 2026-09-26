import { decodeGeohash, geohashDistanceKm, haversineDistanceKm } from './geohash.util.js';

describe('decodeGeohash', () => {
  it('matches the well-known "ezs42" reference value (~42.6, -5.6)', () => {
    // Wikipedia's geohash article uses this exact example.
    const { lat, lon } = decodeGeohash('ezs42');
    expect(lat).toBeCloseTo(42.6, 0);
    expect(lon).toBeCloseTo(-5.6, 0);
  });

  it('decodes a longer, more precise hash consistently', () => {
    // "u4pruydqqvj" is San Francisco-ish; just check it's in a sane range
    // and doesn't throw -- precision, not an exact known value, matters here.
    const { lat, lon } = decodeGeohash('9q8yyk8ytpxr');
    expect(lat).toBeGreaterThan(30);
    expect(lat).toBeLessThan(40);
    expect(lon).toBeGreaterThan(-130);
    expect(lon).toBeLessThan(-110);
  });

  it('ignores stray invalid characters rather than throwing', () => {
    expect(() => decodeGeohash('ezs42!!')).not.toThrow();
  });
});

describe('haversineDistanceKm', () => {
  it('is zero for the same point', () => {
    expect(haversineDistanceKm({ lat: 40, lon: -74 }, { lat: 40, lon: -74 })).toBeCloseTo(0, 5);
  });

  it('roughly matches the known NYC <-> LA distance (~3940km)', () => {
    const nyc = { lat: 40.7128, lon: -74.006 };
    const la = { lat: 34.0522, lon: -118.2437 };
    const distance = haversineDistanceKm(nyc, la);
    expect(distance).toBeGreaterThan(3900);
    expect(distance).toBeLessThan(4000);
  });
});

describe('geohashDistanceKm', () => {
  it('returns null when either geohash is missing', () => {
    expect(geohashDistanceKm(null, 'ezs42')).toBeNull();
    expect(geohashDistanceKm('ezs42', undefined)).toBeNull();
  });

  it('returns a small distance for two nearby geohashes', () => {
    // Same 5-char prefix -> same bounding box -> should be a short distance.
    const distance = geohashDistanceKm('u4pruy', 'u4pruz');
    expect(distance).not.toBeNull();
    expect(distance!).toBeLessThan(50);
  });
});
