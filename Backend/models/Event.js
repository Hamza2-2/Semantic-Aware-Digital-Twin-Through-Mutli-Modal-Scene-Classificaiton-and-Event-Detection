// Detected event model with severity and status
import mongoose from 'mongoose';

const eventSchema = new mongoose.Schema({

  eventType: {
    type: String,
    required: [true, 'Event type is required'],
    trim: true,
    index: true


  },
  severity: {
    type: String,
    enum: ['low', 'medium', 'high', 'critical'],
    default: 'medium'
  },
  severityLevel: {
    type: Number,
    min: 1,
    max: 5,
    default: 3

  },


  predictedClass: {
    type: String,
    trim: true

  },
  confidence: {
    type: Number,
    min: 0,
    max: 1,
    default: 0
  },
  topPredictions: [{
    class: { type: String, required: true },
    confidence: { type: Number, required: true, min: 0, max: 1 }
  }],


  predictionId: {
    type: mongoose.Schema.Types.ObjectId,
    ref: 'Prediction',
    index: true
  },
  sourceCollection: {
    type: String,
    enum: ['video_history', 'audio_history', 'fusion_history'],
    trim: true
  },
  sourceType: {
    type: String,
    enum: ['video', 'audio', 'fusion', 'video_stream', 'audio_stream', 'fusion_stream'],
    trim: true
  },


  fileName: {
    type: String,
    trim: true
  },
  source: {
    type: String,
    enum: ['file', 'stream', 'url'],
    default: 'file'
  },
  streamUrl: {
    type: String,
    trim: true
  },
  deviceName: {
    type: String,
    trim: true
  },
  deviceId: {
    type: String,
    trim: true
  },
  deviceRef: {
    type: mongoose.Schema.Types.ObjectId,
    ref: 'Device'
  },


  locationId: {
    type: mongoose.Schema.Types.ObjectId,
    ref: 'Location'
  },


  details: {
    type: mongoose.Schema.Types.Mixed,
    default: {}


  },


  status: {
    type: String,
    enum: ['detected', 'acknowledged', 'investigating', 'resolved', 'false_alarm', 'neutralized'],
    default: 'detected',
    index: true
  },
  neutralizedBy: {
    type: mongoose.Schema.Types.ObjectId,
    ref: 'Admin'
  },
  neutralizedAt: {
    type: Date
  },
  adminId: {
    type: mongoose.Schema.Types.ObjectId,
    ref: 'Admin'
  },
  resolvedAt: {
    type: Date
  },
  notes: {
    type: String,
    trim: true
  }
}, {
  timestamps: true,
  collection: 'events'
});

eventSchema.index({ eventType: 1, createdAt: -1 });
eventSchema.index({ createdAt: -1 });
eventSchema.index({ severity: 1 });
eventSchema.index({ status: 1, createdAt: -1 });
eventSchema.index({ sourceType: 1 });
eventSchema.index({ locationId: 1 });

const Event = mongoose.model('Event', eventSchema);

export default Event;
