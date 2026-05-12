// Fusion prediction history model
import mongoose from 'mongoose';

const fusionHistorySchema = new mongoose.Schema({
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


  fusionMethod: {
    type: String,
    enum: ['weighted', 'confidence', 'max', 'average'],
    trim: true
  },
  multiScene: {
    type: Boolean,
    default: false
  },

  metadata: {
    type: mongoose.Schema.Types.Mixed,
    default: {}
  }
}, {
  timestamps: true,
  collection: 'fusion_history'
});

fusionHistorySchema.index({ createdAt: -1 });
fusionHistorySchema.index({ predictedClass: 1 });
fusionHistorySchema.index({ source: 1, createdAt: -1 });
fusionHistorySchema.index({ fusionMethod: 1 });

const FusionHistory = mongoose.model('FusionHistory', fusionHistorySchema);

export default FusionHistory;
