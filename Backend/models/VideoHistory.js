// Video prediction history model
import mongoose from 'mongoose';

const videoHistorySchema = new mongoose.Schema({
  fileName: {
    type: String,
    required: [true, 'File name is required'],
    trim: true
  },
  filePath: {
    type: String,
    trim: true
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
  topPredictions: [{
    class: {
      type: String,
      required: true
    },
    confidence: {
      type: Number,
      required: true,
      min: 0,
      max: 1
    }
  }],
  processingTime: {
    type: Number,
    default: 0
  },
  modelVersion: {
    type: String,
    default: '1.0'
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
  streamDuration: {
    type: Number,
    min: 1
  },

  metadata: {
    type: mongoose.Schema.Types.Mixed,
    default: {}
  }
}, {
  timestamps: true,
  collection: 'video_history'
});

videoHistorySchema.index({ createdAt: -1 });
videoHistorySchema.index({ predictedClass: 1 });
videoHistorySchema.index({ source: 1, createdAt: -1 });

const VideoHistory = mongoose.model('VideoHistory', videoHistorySchema);

export default VideoHistory;
