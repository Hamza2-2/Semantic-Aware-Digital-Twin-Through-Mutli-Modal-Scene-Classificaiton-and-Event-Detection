// Unified prediction model linking history
import mongoose from 'mongoose';

const predictionSchema = new mongoose.Schema({

  historyRef: {
    type: mongoose.Schema.Types.ObjectId,
    required: [true, 'History reference ID is required'],
    refPath: 'sourceModel'
  },
  sourceModel: {
    type: String,
    required: true,
    enum: ['VideoHistory', 'AudioHistory', 'FusionHistory']
  },
  sourceCollection: {
    type: String,
    required: true,
    enum: ['video_history', 'audio_history', 'fusion_history']
  },


  type: {
    type: String,
    required: [true, 'Prediction type is required'],
    enum: ['video', 'audio', 'fusion', 'video_stream', 'audio_stream', 'fusion_stream']
  },


  predictedClass: {
    type: String,
    required: [true, 'Predicted class is required'],
    trim: true
  },
  confidence: {
    type: Number,
    required: true,
    min: 0,
    max: 1
  },
  fileName: {
    type: String,
    required: [true, 'File name is required'],
    trim: true
  },
  source: {
    type: String,
    enum: ['file', 'stream', 'url'],
    default: 'file'
  },
  processingTime: {
    type: Number,
    default: 0
  },
  modelVersion: {
    type: String,
    default: '1.0'
  },
  status: {
    type: String,
    enum: ['completed', 'processing', 'failed'],
    default: 'completed'
  },


  deviceName: {
    type: String,
    trim: true
  },
  deviceId: {
    type: String,
    trim: true
  },
  streamUrl: {
    type: String,
    trim: true
  },
  deviceRef: {
    type: mongoose.Schema.Types.ObjectId,
    ref: 'Device'
  },
  eventRef: {
    type: mongoose.Schema.Types.ObjectId,
    ref: 'Event'
  },


  tagCount: {
    type: Number,
    default: 0
  },

  metadata: {
    type: mongoose.Schema.Types.Mixed,
    default: {}
  }
}, {
  timestamps: true,
  collection: 'predictions'
});

predictionSchema.index({ createdAt: -1 });
predictionSchema.index({ type: 1, createdAt: -1 });
predictionSchema.index({ predictedClass: 1 });
predictionSchema.index({ source: 1 });
predictionSchema.index({ historyRef: 1 }, { unique: true });
predictionSchema.index({ sourceCollection: 1, createdAt: -1 });
predictionSchema.index({ status: 1 });

const Prediction = mongoose.model('Prediction', predictionSchema);

export default Prediction;
