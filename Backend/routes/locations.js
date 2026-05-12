// Location CRUD and geo routes
import express from 'express';
import Location from '../models/Location.js';
import { getLocationFromIp, getClientIp, isPrivateIp } from '../utils/geolocation.js';

const router = express.Router();

// get all records
router.get('/', async (req, res) => {
  try {
    const { city, country, source, limit = 100, skip = 0 } = req.query;
    const query = {};

    if (city) query.city = new RegExp(city, 'i');
    if (country) query.country = new RegExp(country, 'i');
    if (source) query.source = source;

    const [locations, total] = await Promise.all([
      Location.find(query)
        .sort('-lastUpdated')
        .skip(parseInt(skip))
        .limit(parseInt(limit))
        .lean(),
      Location.countDocuments(query)
    ]);

    res.json({
      success: true,
      count: locations.length,
      total,
      data: locations.map(l => ({
        id: l._id.toString(),
        ...l,
        _id: undefined
      }))
    });
  } catch (error) {
    console.error('Error fetching locations:', error);
    res.status(500).json({ success: false, error: error.message });
  }
});

// find nearby records
router.get('/nearby', async (req, res) => {
  try {
    const { lat, lng, maxDistance = 10000, limit = 50 } = req.query;

    if (!lat || !lng) {
      return res.status(400).json({
        success: false,
        error: 'lat and lng query parameters are required'
      });
    }

    const locations = await Location.find({
      coordinates: {
        $near: {
          $geometry: {
            type: 'Point',
            coordinates: [parseFloat(lng), parseFloat(lat)]
          },
          $maxDistance: parseInt(maxDistance)
        }
      }
    })
      .limit(parseInt(limit))
      .lean();

    res.json({
      success: true,
      count: locations.length,
      center: { lat: parseFloat(lat), lng: parseFloat(lng) },
      maxDistance: parseInt(maxDistance),
      data: locations.map(l => ({
        id: l._id.toString(),
        ...l,
        _id: undefined
      }))
    });
  } catch (error) {
    console.error('Error fetching nearby locations:', error);
    res.status(500).json({ success: false, error: error.message });
  }
});

// lookup by ip address
router.get('/by-ip/:ip', async (req, res) => {
  try {
    const location = await Location.findOne({ ipAddress: req.params.ip }).lean();
    if (!location) {
      return res.status(404).json({ success: false, error: 'Location not found for this IP' });
    }

    res.json({
      success: true,
      data: { id: location._id.toString(), ...location, _id: undefined }
    });
  } catch (error) {
    console.error('Error fetching location by IP:', error);
    res.status(500).json({ success: false, error: error.message });
  }
});

router.get('/geolocate/:ip', async (req, res) => {
  try {
    const locData = await getLocationFromIp(req.params.ip);
    if (!locData || (locData.latitude === 0 && locData.longitude === 0)) {
      return res.status(404).json({ success: false, error: 'Could not geolocate this IP' });
    }
    res.json({
      success: true,
      data: {
        latitude: locData.latitude,
        longitude: locData.longitude,
        city: locData.city || 'Unknown',
        region: locData.region || 'Unknown',
        country: locData.country || 'Unknown',
        accuracy: locData.accuracy || 'city_level',
        ipAddress: req.params.ip
      }
    });
  } catch (error) {
    console.error('Error geolocating IP:', error);
    res.status(500).json({ success: false, error: error.message });
  }
});

router.get('/geolocate-me', async (req, res) => {
  try {
    const clientIp = getClientIp(req);


    let publicIp = clientIp;
    if (isPrivateIp(clientIp)) {

      try {
        const { default: axios } = await import('axios');
        const extResp = await axios.get('https://api.ipify.org?format=json', { timeout: 5000 });
        publicIp = extResp.data.ip;
      } catch (e) {
        try {
          const { default: axios } = await import('axios');
          const extResp = await axios.get('https://ifconfig.me/ip', { timeout: 5000 });
          publicIp = extResp.data.trim();
        } catch (e2) {
          return res.status(500).json({
            success: false,
            error: 'Could not determine public IP. Set location manually.'
          });
        }
      }
    }

    const locData = await getLocationFromIp(publicIp);
    if (!locData || (locData.latitude === 0 && locData.longitude === 0)) {
      return res.status(404).json({ success: false, error: 'Could not geolocate detected IP' });
    }

    res.json({
      success: true,
      data: {
        latitude: locData.latitude,
        longitude: locData.longitude,
        city: locData.city || 'Unknown',
        region: locData.region || 'Unknown',
        country: locData.country || 'Unknown',
        accuracy: locData.accuracy || 'city_level',
        ipAddress: publicIp,
        detectedFrom: clientIp !== publicIp ? 'nat_resolved' : 'direct'
      }
    });
  } catch (error) {
    console.error('Error in geolocate-me:', error);
    res.status(500).json({ success: false, error: error.message });
  }
});

router.get('/reverse-geocode', async (req, res) => {
  try {
    const { lat, lng } = req.query;
    if (!lat || !lng) {
      return res.status(400).json({ success: false, error: 'lat and lng query params required' });
    }
    const { default: axios } = await import('axios');
    const response = await axios.get(
      `https://nominatim.openstreetmap.org/reverse?lat=${lat}&lon=${lng}&format=json&addressdetails=1`,
      {
        timeout: 8000,
        headers: { 'User-Agent': 'MVATS-Emergency-System/1.0' }
      }
    );
    const data = response.data;
    const addr = data.address || {};
    res.json({
      success: true,
      data: {
        displayName: data.display_name || 'Unknown',
        road: addr.road || addr.pedestrian || '',
        neighbourhood: addr.neighbourhood || addr.suburb || '',
        city: addr.city || addr.town || addr.village || '',
        state: addr.state || '',
        country: addr.country || '',
        postcode: addr.postcode || '',
        latitude: parseFloat(lat),
        longitude: parseFloat(lng)
      }
    });
  } catch (error) {
    console.error('Error in reverse-geocode:', error.message);
    res.status(500).json({ success: false, error: 'Reverse geocode failed' });
  }
});

router.post('/hybrid-locate', async (req, res) => {
  try {
    const { gps_latitude, gps_longitude, ip_address } = req.body;


    if (gps_latitude != null && gps_longitude != null &&
        gps_latitude !== 0 && gps_longitude !== 0) {

      let address = 'GPS location';
      try {
        const { default: axios } = await import('axios');
        const geoResp = await axios.get(
          `https://nominatim.openstreetmap.org/reverse?lat=${gps_latitude}&lon=${gps_longitude}&format=json&addressdetails=1`,
          { timeout: 5000, headers: { 'User-Agent': 'MVATS-Emergency-System/1.0' } }
        );
        if (geoResp.data && geoResp.data.display_name) {
          address = geoResp.data.display_name;
          const addr = geoResp.data.address || {};
          var neighbourhood = addr.neighbourhood || addr.suburb || '';
          var city = addr.city || addr.town || addr.village || '';
        }
      } catch (_) {  }

      return res.json({
        success: true,
        data: {
          latitude: parseFloat(gps_latitude),
          longitude: parseFloat(gps_longitude),
          accuracy: 'gps_precise',
          accuracyMeters: 5,
          source: 'device_gps',
          address: address,
          neighbourhood: neighbourhood || '',
          city: city || '',
          note: 'Precise GPS location (±3-5 meters)'
        }
      });
    }


    if (ip_address) {
      if (isPrivateIp(ip_address)) {

        let publicIp = ip_address;
        try {
          const { default: axios } = await import('axios');
          const extResp = await axios.get('https://api.ipify.org?format=json', { timeout: 5000 });
          publicIp = extResp.data.ip;
        } catch (_) {}

        if (isPrivateIp(publicIp)) {
          return res.status(400).json({
            success: false,
            error: 'Private IP cannot be geolocated. Enable GPS for precise location.'
          });
        }
        ip_address_resolved = publicIp;
      }

      const locData = await getLocationFromIp(ip_address);
      if (locData && (locData.latitude !== 0 || locData.longitude !== 0)) {
        return res.json({
          success: true,
          data: {
            latitude: locData.latitude,
            longitude: locData.longitude,
            accuracy: 'city_level',
            accuracyMeters: 15000,
            source: 'ip_geolocation',
            city: locData.city || 'Unknown',
            region: locData.region || 'Unknown',
            country: locData.country || 'Unknown',
            ipAddress: ip_address,
            note: 'Approximate location (±10-15 km). Enable GPS for precise location.'
          }
        });
      }
    }


    const clientIp = getClientIp(req);
    let resolveIp = clientIp;
    if (isPrivateIp(clientIp)) {
      try {
        const { default: axios } = await import('axios');
        const extResp = await axios.get('https://api.ipify.org?format=json', { timeout: 5000 });
        resolveIp = extResp.data.ip;
      } catch (_) {
        return res.status(500).json({
          success: false,
          error: 'Could not determine location. Please enable GPS or enter a public IP.'
        });
      }
    }

    const locData = await getLocationFromIp(resolveIp);
    if (locData && (locData.latitude !== 0 || locData.longitude !== 0)) {
      return res.json({
        success: true,
        data: {
          latitude: locData.latitude,
          longitude: locData.longitude,
          accuracy: 'city_level',
          accuracyMeters: 15000,
          source: 'ip_auto_detected',
          city: locData.city || 'Unknown',
          region: locData.region || 'Unknown',
          country: locData.country || 'Unknown',
          ipAddress: resolveIp,
          note: 'Approximate location from auto-detected IP. Enable GPS for precise location.'
        }
      });
    }

    res.status(404).json({
      success: false,
      error: 'Could not determine location by any method. Please set location manually on the map.'
    });
  } catch (error) {
    console.error('Error in hybrid-locate:', error);
    res.status(500).json({ success: false, error: error.message });
  }
});

// get one by id
router.get('/:id', async (req, res) => {
  try {
    const location = await Location.findById(req.params.id).lean();
    if (!location) {
      return res.status(404).json({ success: false, error: 'Location not found' });
    }

    res.json({
      success: true,
      data: { id: location._id.toString(), ...location, _id: undefined }
    });
  } catch (error) {
    console.error('Error fetching location:', error);
    res.status(500).json({ success: false, error: error.message });
  }
});

// create new record
router.post('/', async (req, res) => {
  try {
    const { ipAddress, latitude, longitude, city, region, country, accuracy, source, label, metadata } = req.body;

    if (latitude == null || longitude == null) {
      return res.status(400).json({
        success: false,
        error: 'latitude and longitude are required'
      });
    }

    let location;
    if (ipAddress) {

      location = await Location.findOrCreateByIp({
        ipAddress,
        latitude: parseFloat(latitude),
        longitude: parseFloat(longitude),
        city,
        region,
        country,
        accuracy: accuracy || 'city_level',
        source: source || 'ip'
      });
    } else {
      location = await Location.create({
        coordinates: [parseFloat(longitude), parseFloat(latitude)],
        city: city || 'Unknown',
        region: region || 'Unknown',
        country: country || 'Unknown',
        accuracy: accuracy || 'unknown',
        source: source || 'manual',
        label,
        metadata: metadata || {},
        lastUpdated: new Date()
      });
    }

    res.status(201).json({
      success: true,
      message: 'Location created/updated successfully',
      data: {
        id: location._id.toString(),
        coordinates: location.coordinates,
        city: location.city,
        region: location.region,
        country: location.country,
        ipAddress: location.ipAddress,
        accuracy: location.accuracy,
        source: location.source
      }
    });
  } catch (error) {
    console.error('Error creating location:', error);
    res.status(500).json({ success: false, error: error.message });
  }
});

// update by id
router.put('/:id', async (req, res) => {
  try {
    const updates = {};
    const allowed = ['city', 'region', 'country', 'accuracy', 'source', 'label', 'metadata'];

    for (const key of allowed) {
      if (req.body[key] !== undefined) updates[key] = req.body[key];
    }


    if (req.body.latitude != null && req.body.longitude != null) {
      updates.coordinates = [parseFloat(req.body.longitude), parseFloat(req.body.latitude)];
    }

    updates.lastUpdated = new Date();

    const location = await Location.findByIdAndUpdate(
      req.params.id,
      updates,
      { new: true, runValidators: true }
    );

    if (!location) {
      return res.status(404).json({ success: false, error: 'Location not found' });
    }

    res.json({
      success: true,
      message: 'Location updated successfully',
      data: { id: location._id.toString(), ...location.toObject(), _id: undefined }
    });
  } catch (error) {
    console.error('Error updating location:', error);
    res.status(500).json({ success: false, error: error.message });
  }
});

// delete by id
router.delete('/:id', async (req, res) => {
  try {
    const result = await Location.findByIdAndDelete(req.params.id);
    if (!result) {
      return res.status(404).json({ success: false, error: 'Location not found' });
    }
    res.json({ success: true, message: 'Location deleted successfully' });
  } catch (error) {
    console.error('Error deleting location:', error);
    res.status(500).json({ success: false, error: error.message });
  }
});

// clear all records
router.delete('/', async (req, res) => {
  try {
    const result = await Location.deleteMany({});
    res.json({
      success: true,
      message: `Deleted ${result.deletedCount} locations`,
      deletedCount: result.deletedCount
    });
  } catch (error) {
    console.error('Error clearing locations:', error);
    res.status(500).json({ success: false, error: error.message });
  }
});

export default router;
