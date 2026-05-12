// Device CRUD and sync routes
import express from 'express';
import Device from '../models/Device.js';
import Location from '../models/Location.js';

const router = express.Router();

// get all records
router.get('/', async (req, res) => {
  try {
    const { type } = req.query;
    const query = {};
    if (type && ['droidcam', 'ipwebcam', 'rtsp', 'custom'].includes(type)) {
      query.type = type;
    }

    const devices = await Device.find(query).sort('label').lean();

    res.json({
      success: true,
      count: devices.length,
      data: devices.map(d => ({
        id: d.deviceId,
        label: d.label,
        address: d.address,
        type: d.type,
        latitude: d.latitude || null,
        longitude: d.longitude || null,
        addedAt: d.addedAt || d.createdAt
      }))
    });
  } catch (error) {
    console.error('Error fetching devices:', error);
    res.status(500).json({ success: false, error: error.message });
  }
});

// get one by id
router.get('/:id', async (req, res) => {
  try {
    const device = await Device.findOne({ deviceId: req.params.id }).lean();

    if (!device) {
      return res.status(404).json({ success: false, error: 'Device not found' });
    }

    res.json({
      success: true,
      data: {
        id: device.deviceId,
        label: device.label,
        address: device.address,
        type: device.type,
        latitude: device.latitude || null,
        longitude: device.longitude || null,
        addedAt: device.addedAt || device.createdAt
      }
    });
  } catch (error) {
    console.error('Error fetching device:', error);
    res.status(500).json({ success: false, error: error.message });
  }
});

// create new record
router.post('/', async (req, res) => {
  try {
    const { id, label, address, type, addedAt, latitude, longitude } = req.body;

    if (!label || !address) {
      return res.status(400).json({
        success: false,
        error: 'label and address are required'
      });
    }

    const deviceId = id || `dev_${Date.now()}_${Math.random().toString(36).substr(2, 6)}`;

    // Resolve locationId from lat/lon
    let locationId;
    const lat = latitude != null ? parseFloat(latitude) : null;
    const lon = longitude != null ? parseFloat(longitude) : null;
    if (lat != null && lon != null) {
      try {
        const locDoc = await Location.findOrCreateByIp({
          latitude: lat,
          longitude: lon,
          source: 'device',
          accuracy: 'gps',
          ipAddress: address
        });
        if (locDoc) locationId = locDoc._id;
      } catch (_) { /* non-critical */ }
    }


    const device = await Device.findOneAndUpdate(
      { deviceId },
      {
        deviceId,
        label,
        address,
        type: type || 'custom',
        latitude: lat,
        longitude: lon,
        locationId: locationId || undefined,
        addedAt: addedAt ? new Date(addedAt) : new Date()
      },
      { upsert: true, new: true, runValidators: true }
    );

    res.status(201).json({
      success: true,
      message: 'Device saved successfully',
      data: {
        id: device.deviceId,
        label: device.label,
        address: device.address,
        type: device.type,
        latitude: device.latitude || null,
        longitude: device.longitude || null,
        addedAt: device.addedAt
      }
    });
  } catch (error) {
    console.error('Error saving device:', error);
    res.status(500).json({ success: false, error: error.message });
  }
});

// update by id
router.put('/:id', async (req, res) => {
  try {
    const { label, address, type, latitude, longitude } = req.body;

    const updates = { label, address, type };
    if (latitude !== undefined) updates.latitude = latitude != null ? parseFloat(latitude) : null;
    if (longitude !== undefined) updates.longitude = longitude != null ? parseFloat(longitude) : null;

    const device = await Device.findOneAndUpdate(
      { deviceId: req.params.id },
      updates,
      { new: true, runValidators: true }
    );

    if (!device) {
      return res.status(404).json({ success: false, error: 'Device not found' });
    }

    res.json({
      success: true,
      message: 'Device updated successfully',
      data: {
        id: device.deviceId,
        label: device.label,
        address: device.address,
        type: device.type,
        latitude: device.latitude || null,
        longitude: device.longitude || null,
        addedAt: device.addedAt
      }
    });
  } catch (error) {
    console.error('Error updating device:', error);
    res.status(500).json({ success: false, error: error.message });
  }
});

// delete by id
router.delete('/:id', async (req, res) => {
  try {
    const result = await Device.findOneAndDelete({ deviceId: req.params.id });

    if (!result) {
      return res.status(404).json({ success: false, error: 'Device not found' });
    }

    res.json({
      success: true,
      message: 'Device deleted successfully'
    });
  } catch (error) {
    console.error('Error deleting device:', error);
    res.status(500).json({ success: false, error: error.message });
  }
});

// clear all records
router.delete('/', async (req, res) => {
  try {
    const result = await Device.deleteMany({});
    res.json({
      success: true,
      message: `Deleted ${result.deletedCount} devices`,
      deletedCount: result.deletedCount
    });
  } catch (error) {
    console.error('Error clearing devices:', error);
    res.status(500).json({ success: false, error: error.message });
  }
});

// bulk sync from client
router.post('/sync', async (req, res) => {
  try {
    const { devices } = req.body;

    if (!Array.isArray(devices)) {
      return res.status(400).json({
        success: false,
        error: 'devices array is required'
      });
    }


    await Device.deleteMany({});

    const docs = devices.map(d => ({
      deviceId: d.id || `dev_${Date.now()}_${Math.random().toString(36).substr(2, 6)}`,
      label: d.label,
      address: d.address,
      type: d.type || 'custom',
      latitude: d.latitude != null ? parseFloat(d.latitude) : null,
      longitude: d.longitude != null ? parseFloat(d.longitude) : null,
      addedAt: d.addedAt ? new Date(d.addedAt) : new Date()
    }));

    if (docs.length > 0) {
      await Device.insertMany(docs);
    }

    res.json({
      success: true,
      message: `Synced ${docs.length} devices`,
      count: docs.length
    });
  } catch (error) {
    console.error('Error syncing devices:', error);
    res.status(500).json({ success: false, error: error.message });
  }
});

export default router;
