// Event CRUD and nearby search routes
import express from 'express';
import Event from '../models/Event.js';
import Location from '../models/Location.js';
import Device from '../models/Device.js';
import Prediction from '../models/Prediction.js';
import { getLocationFromRequest, getLocationFromIp, getClientIp } from '../utils/geolocation.js';

const router = express.Router();

// get all records
router.get('/', async (req, res) => {
  try {
    const { eventType, severity, status, sourceType, limit = 50, skip = 0 } = req.query;
    const query = {};

    if (eventType) query.eventType = eventType;
    if (severity && ['low', 'medium', 'high', 'critical'].includes(severity)) query.severity = severity;
    if (status) query.status = status;
    if (sourceType) query.sourceType = sourceType;

    const [events, total] = await Promise.all([
      Event.find(query).populate('locationId').sort('-createdAt').skip(parseInt(skip)).limit(parseInt(limit)).lean(),
      Event.countDocuments(query)
    ]);

    res.json({
      success: true,
      count: events.length,
      total,
      data: events.map(e => ({
        id: e._id.toString(),
        ...e,
        _id: undefined
      }))
    });
  } catch (error) {
    console.error('Error fetching events:', error);
    res.status(500).json({ success: false, error: error.message });
  }
});

router.get('/types', async (req, res) => {
  try {
    const types = await Event.aggregate([
      { $group: { _id: '$eventType', count: { $sum: 1 } } },
      { $sort: { count: -1 } }
    ]);

    res.json({
      success: true,
      data: types.map(t => ({ eventType: t._id, count: t.count }))
    });
  } catch (error) {
    console.error('Error fetching event types:', error);
    res.status(500).json({ success: false, error: error.message });
  }
});

// get statistics
router.get('/stats', async (req, res) => {
  try {
    const [total, byType, bySeverity, byStatus] = await Promise.all([
      Event.countDocuments(),
      Event.aggregate([
        { $group: { _id: '$eventType', count: { $sum: 1 } } },
        { $sort: { count: -1 } }
      ]),
      Event.aggregate([
        { $group: { _id: '$severity', count: { $sum: 1 } } },
        { $sort: { count: -1 } }
      ]),
      Event.aggregate([
        { $group: { _id: '$status', count: { $sum: 1 } } },
        { $sort: { count: -1 } }
      ])
    ]);

    res.json({
      success: true,
      stats: {
        total,
        byType: byType.map(t => ({ type: t._id, count: t.count })),
        bySeverity: bySeverity.map(s => ({ severity: s._id, count: s.count })),
        byStatus: byStatus.map(s => ({ status: s._id, count: s.count }))
      }
    });
  } catch (error) {
    console.error('Error fetching event stats:', error);
    res.status(500).json({ success: false, error: error.message });
  }
});

// get one by id
router.get('/:id', async (req, res) => {
  try {
    const event = await Event.findById(req.params.id).populate('locationId').lean();
    if (!event) return res.status(404).json({ success: false, error: 'Event not found' });

    res.json({ success: true, data: { id: event._id.toString(), ...event, _id: undefined } });
  } catch (error) {
    console.error('Error fetching event:', error);
    res.status(500).json({ success: false, error: error.message });
  }
});

// create new record
router.post('/', async (req, res) => {
  try {
    const {
      eventType, severity,
      predictedClass, confidence, topPredictions,
      predictionId, sourceCollection, sourceType,
      fileName, source, streamUrl, deviceName, deviceId,
      details, status, notes, location
    } = req.body;

    if (!eventType) {
      return res.status(400).json({ success: false, error: 'eventType is required' });
    }


    let locationId = null;
    try {
      let locData;
      if (location && location.coordinates && location.coordinates.length === 2) {

        locData = {
          ipAddress: location.ipAddress || null,
          latitude: location.coordinates[1] || location.latitude,
          longitude: location.coordinates[0] || location.longitude,
          city: location.city || 'Unknown',
          region: location.region || 'Unknown',
          country: location.country || 'Unknown',
          accuracy: location.accuracy || 'gps',
          source: location.source || 'manual'
        };
      } else {

        const clientIp = getClientIp(req);
        const geoResult = await getLocationFromIp(clientIp);
        if (geoResult) {
          locData = {
            ipAddress: geoResult.ip || clientIp,
            latitude: geoResult.latitude,
            longitude: geoResult.longitude,
            city: geoResult.city,
            region: geoResult.region,
            country: geoResult.country,
            accuracy: geoResult.accuracy || 'city_level',
            source: 'ip'
          };
        }
      }

      if (locData) {
        const locationDoc = await Location.findOrCreateByIp(locData);
        locationId = locationDoc._id;
      }
    } catch (locErr) {
      console.warn('[Events] Location resolution failed, continuing without:', locErr.message);
    }

    const event = new Event({
      eventType,
      severity: severity || 'medium',
      predictedClass,
      confidence: parseFloat(confidence) || 0,
      topPredictions: topPredictions || [],
      predictionId: predictionId || undefined,
      sourceCollection,
      sourceType,
      fileName,
      source: source || 'file',
      streamUrl,
      deviceName,
      deviceId,
      deviceRef: undefined,
      locationId,
      details: details || {},
      status: status || 'detected',
      notes
    });

    // Resolve deviceRef from deviceId string
    if (deviceId) {
      try {
        const deviceDoc = await Device.findOne({ deviceId });
        if (deviceDoc) event.deviceRef = deviceDoc._id;
      } catch (_) { /* non-critical */ }
    }

    await event.save();

    // Back-link: set eventRef on the Prediction doc
    if (event.predictionId) {
      try {
        await Prediction.findByIdAndUpdate(event.predictionId, { eventRef: event._id });
      } catch (_) { /* non-critical */ }
    }


    await event.populate('locationId');

    res.status(201).json({
      success: true,
      message: 'Event created successfully',
      data: {
        id: event._id.toString(),
        eventType: event.eventType,
        severity: event.severity,
        predictedClass: event.predictedClass,
        confidence: event.confidence,
        status: event.status,
        location: event.locationId ? {
          id: event.locationId._id.toString(),
          coordinates: event.locationId.coordinates,
          city: event.locationId.city,
          region: event.locationId.region,
          country: event.locationId.country,
          accuracy: event.locationId.accuracy,
          ipAddress: event.locationId.ipAddress,
          source: event.locationId.source
        } : null,
        createdAt: event.createdAt
      }
    });
  } catch (error) {
    console.error('Error creating event:', error);
    res.status(500).json({ success: false, error: error.message });
  }
});

// neutralize an event
router.put('/:id/neutralize', async (req, res) => {
  try {
    const { userId } = req.body;
    const event = await Event.findByIdAndUpdate(
      req.params.id,
      {
        status: 'neutralized',
        neutralizedBy: userId || undefined,
        neutralizedAt: new Date()
      },
      { new: true, runValidators: true }
    ).populate('locationId');
    if (!event) return res.status(404).json({ success: false, error: 'Event not found' });
    res.json({
      success: true,
      message: 'Event neutralized successfully',
      data: { id: event._id.toString(), ...event.toObject(), _id: undefined }
    });
  } catch (error) {
    res.status(500).json({ success: false, error: error.message });
  }
});

// update by id
router.put('/:id', async (req, res) => {
  try {
    const updates = {};
    const allowed = ['eventType', 'severity', 'status', 'notes', 'details', 'resolvedAt'];
    for (const key of allowed) {
      if (req.body[key] !== undefined) updates[key] = req.body[key];
    }


    if (updates.status === 'resolved' && !updates.resolvedAt) {
      updates.resolvedAt = new Date();
    }

    const event = await Event.findByIdAndUpdate(req.params.id, updates, { new: true, runValidators: true });
    if (!event) return res.status(404).json({ success: false, error: 'Event not found' });

    res.json({
      success: true,
      message: 'Event updated successfully',
      data: { id: event._id.toString(), ...event.toObject(), _id: undefined }
    });
  } catch (error) {
    console.error('Error updating event:', error);
    res.status(500).json({ success: false, error: error.message });
  }
});

// delete by id
router.delete('/:id', async (req, res) => {
  try {
    const result = await Event.findByIdAndDelete(req.params.id);
    if (!result) return res.status(404).json({ success: false, error: 'Event not found' });
    res.json({ success: true, message: 'Event deleted successfully' });
  } catch (error) {
    console.error('Error deleting event:', error);
    res.status(500).json({ success: false, error: error.message });
  }
});

// clear all records
router.delete('/', async (req, res) => {
  try {
    const { eventType } = req.query;
    const query = eventType ? { eventType } : {};
    const result = await Event.deleteMany(query);

    res.json({
      success: true,
      message: `Deleted ${result.deletedCount} events`,
      deletedCount: result.deletedCount
    });
  } catch (error) {
    console.error('Error clearing events:', error);
    res.status(500).json({ success: false, error: error.message });
  }
});

// find nearby records
router.get('/nearby', async (req, res) => {
  try {
    const { lat, lng, maxDistance = 5000, limit = 50, eventType, severity } = req.query;

    if (!lat || !lng) {
      return res.status(400).json({
        success: false,
        error: 'lat and lng query parameters are required'
      });
    }


    const nearbyLocations = await Location.find({
      coordinates: {
        $near: {
          $geometry: {
            type: 'Point',
            coordinates: [parseFloat(lng), parseFloat(lat)]
          },
          $maxDistance: parseInt(maxDistance)
        }
      }
    }).select('_id').lean();

    const locationIds = nearbyLocations.map(l => l._id);


    const eventQuery = { locationId: { $in: locationIds } };
    if (eventType) eventQuery.eventType = eventType;
    if (severity) eventQuery.severity = severity;

    const events = await Event.find(eventQuery)
      .populate('locationId')
      .limit(parseInt(limit))
      .sort('-createdAt')
      .lean();

    res.json({
      success: true,
      count: events.length,
      center: { lat: parseFloat(lat), lng: parseFloat(lng) },
      maxDistance: parseInt(maxDistance),
      data: events.map(e => ({
        id: e._id.toString(),
        ...e,
        _id: undefined
      }))
    });
  } catch (error) {
    console.error('Error fetching nearby events:', error);
    res.status(500).json({ success: false, error: error.message });
  }
});

router.get('/geolocation', async (req, res) => {
  try {
    const location = await getLocationFromRequest(req);
    res.json({
      success: true,
      data: location
    });
  } catch (error) {
    console.error('Error getting geolocation:', error);
    res.status(500).json({ success: false, error: error.message });
  }
});

export default router;
