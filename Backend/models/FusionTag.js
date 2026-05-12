// Fusion classification tag model
import mongoose from 'mongoose';

const fusionTagSchema = new mongoose.Schema({

  historyRef: {
    type: mongoose.Schema.Types.ObjectId,
    ref: 'FusionHistory',
    required: [true, 'Fusion history reference is required']
  },
  predictionRef: {
    type: mongoose.Schema.Types.ObjectId,
    ref: 'Prediction'
  },


  className: {
    type: String,
    required: [true, 'Class name is required'],
    trim: true
  },
  confidence: {
    type: Number,
    required: true,
    min: 0,
    max: 1
  },
  rank: {
    type: Number,
    required: true,
    min: 1
  },
  isPrimary: {
    type: Boolean,
    default: false
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
  deviceName: {
    type: String,
    trim: true
  },


  fusionMethod: {
    type: String,
    enum: ['weighted', 'confidence', 'max', 'average'],
    trim: true
  }
}, {
  timestamps: true,
  collection: 'fusion_tags'
});

fusionTagSchema.index({ historyRef: 1 });
fusionTagSchema.index({ predictionRef: 1 });
fusionTagSchema.index({ className: 1 });
fusionTagSchema.index({ createdAt: -1 });
fusionTagSchema.index({ className: 1, confidence: -1 });
fusionTagSchema.index({ isPrimary: 1, createdAt: -1 });
fusionTagSchema.index({ fusionMethod: 1 });

const FusionTag = mongoose.model('FusionTag', fusionTagSchema);

export default FusionTag;
