// Camera or mic device model
import mongoose from 'mongoose';

const deviceSchema = new mongoose.Schema({
  deviceId: {
    type: String,
    required: true,
    unique: true,
    index: true
  },
  label: {
    type: String,
    required: [true, 'Device label is required'],
    trim: true
  },
  address: {
    type: String,
    required: [true, 'Device address is required'],
    trim: true
  },
  type: {
    type: String,
    enum: ['droidcam', 'ipwebcam', 'rtsp', 'custom'],
    default: 'custom'
  },
  latitude: {
    type: Number,
    default: null
  },
  longitude: {
    type: Number,
    default: null
  },
  addedAt: {
    type: Date,
    default: Date.now
  },
  locationId: {
    type: mongoose.Schema.Types.ObjectId,
    ref: 'Location'
  }
}, {
  timestamps: true,
  collection: 'devices'
});

deviceSchema.index({ label: 1 });
deviceSchema.index({ type: 1 });

const Device = mongoose.model('Device', deviceSchema);

export default Device;
