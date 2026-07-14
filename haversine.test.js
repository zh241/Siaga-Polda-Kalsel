const { haversineDistance, isInsideGeofence } = require('./haversine');

describe('Haversine Formula & Geofence Logic Unit Tests', () => {
    // Pusat koordinat Banjarbaru (di peta geofence)
    const centerLat = -3.4428;
    const centerLng = 114.8306;
    const radiusMeters = 100; // Radius geofence 100 meter

    test('should calculate distance correctly between two points', () => {
        // Koordinat titik 1 (Pusat) dan titik 2 (berjarak sekitar 22 meter)
        const userLat = -3.4428;
        const userLng = 114.8308;
        
        const dist = haversineDistance(centerLat, centerLng, userLat, userLng);
        
        // Jarak matematis harus berkisar di 22.2 meter
        expect(dist).toBeGreaterThan(21);
        expect(dist).toBeLessThan(23);
    });

    test('should return true if user is inside the geofence boundary', () => {
        // Koordinat dekat pusat (~22 meter), harus dianggap masuk zona 100m
        const userLat = -3.4428;
        const userLng = 114.8308;
        
        const inside = isInsideGeofence(userLat, userLng, centerLat, centerLng, radiusMeters);
        expect(inside).toBe(true);
    });

    test('should return false if user is outside the geofence boundary', () => {
        // Koordinat jauh (~222 meter), harus dianggap di luar zona 100m
        const userLat = -3.4428;
        const userLng = 114.8326;
        
        const inside = isInsideGeofence(userLat, userLng, centerLat, centerLng, radiusMeters);
        expect(inside).toBe(false);
    });

    test('should handle edge cases where coordinates are exactly the same (0 meters)', () => {
        const dist = haversineDistance(centerLat, centerLng, centerLat, centerLng);
        expect(dist).toBe(0);
        
        const inside = isInsideGeofence(centerLat, centerLng, centerLat, centerLng, radiusMeters);
        expect(inside).toBe(true);
    });
});
