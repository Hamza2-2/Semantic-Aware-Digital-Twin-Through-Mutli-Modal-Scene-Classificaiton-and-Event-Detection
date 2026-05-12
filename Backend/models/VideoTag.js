// Video classification tag model
import mongoose from 'mongoose';

const videoTagSchema = new mongoose.Schema({

  historyRef: {
    type: mongoose.Schema.Types.ObjectId,
    ref: 'VideoHistory',
    required: [true, 'Video history reference is required']
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
  }
}, {
  timestamps: true,
  collection: 'video_tags'
});

videoTagSchema.index({ historyRef: 1 });
videoTagSchema.index({ predictionRef: 1 });
videoTagSchema.index({ className: 1 });
videoTagSchema.index({ createdAt: -1 });
videoTagSchema.index({ className: 1, confidence: -1 });
videoTagSchema.index({ isPrimary: 1, createdAt: -1 });

const VideoTag = mongoose.model('VideoTag', videoTagSchema);

export default VideoTag;
