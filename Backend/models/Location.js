// GPS or IP based location model
import mongoose from 'mongoose';

const locationSchema = new mongoose.Schema({

  type: {
    type: String,
    enum: ['Point'],
    default: 'Point'
  },
  coordinates: {
    type: [Number],
    required: true,
    default: [0, 0]
  },


  city: {
    type: String,
    trim: true,
    default: 'Unknown'
  },
  region: {
    type: String,
    trim: true,
    default: 'Unknown'
  },
  country: {
    type: String,
    trim: true,
    default: 'Unknown'
  },


  ipAddress: {
    type: String,
    trim: true
  },
  accuracy: {
    type: String,
    enum: ['gps', 'gps_device', 'city_level', 'approximate', 'unknown'],
    default: 'unknown'
  },
  source: {
    type: String,
    enum: ['gps', 'ip', 'manual', 'device'],
    default: 'ip'
  },


  label: {
    type: String,
    trim: true

  },
  lastUpdated: {
    type: Date,
    default: Date.now
  },
  metadata: {
    type: mongoose.Schema.Types.Mixed,
    default: {}

  }
}, {
  timestamps: true,
  collection: 'locations'
});

locationSchema.index({ coordinates: '2dsphere' });

locationSchema.index({ ipAddress: 1 });

locationSchema.index({ country: 1, city: 1 });

locationSchema.statics.findOrCreateByIp = async function (locationData) {
  if (!locationData || !locationData.ipAddress) {

    return this.create({
      coordinates: [locationData?.longitude || 0, locationData?.latitude || 0],
      city: locationData?.city || 'Unknown',
      region: locationData?.region || 'Unknown',
      country: locationData?.country || 'Unknown',
      accuracy: locationData?.accuracy || 'unknown',
      source: locationData?.source || 'ip',
      ipAddress: null,
      lastUpdated: new Date()
    });
  }


  const existing = await this.findOne({ ipAddress: locationData.ipAddress });

  if (existing) {

    existing.coordinates = [locationData.longitude || 0, locationData.latitude || 0];
    existing.city = locationData.city || existing.city;
    existing.region = locationData.region || existing.region;
    existing.country = locationData.country || existing.country;
    existing.accuracy = locationData.accuracy || existing.accuracy;
    existing.source = locationData.source || existing.source;
    existing.lastUpdated = new Date();
    await existing.save();
    return existing;
  }


  return this.create({
    coordinates: [locationData.longitude || 0, locationData.latitude || 0],
    city: locationData.city || 'Unknown',
    region: locationData.region || 'Unknown',
    country: locationData.country || 'Unknown',
    accuracy: locationData.accuracy || 'unknown',
    source: locationData.source || 'ip',
    ipAddress: locationData.ipAddress,
    lastUpdated: new Date()
  });
};

const Location = mongoose.model('Location', locationSchema);

export default Location;
