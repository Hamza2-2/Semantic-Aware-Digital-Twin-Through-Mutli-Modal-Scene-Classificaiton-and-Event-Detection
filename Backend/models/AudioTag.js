// Audio classification tag model
import mongoose from 'mongoose';

const audioTagSchema = new mongoose.Schema({

  historyRef: {
    type: mongoose.Schema.Types.ObjectId,
    ref: 'AudioHistory',
    required: [true, 'Audio history reference is required']
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
  collection: 'audio_tags'
});

audioTagSchema.index({ historyRef: 1 });
audioTagSchema.index({ predictionRef: 1 });
audioTagSchema.index({ className: 1 });
audioTagSchema.index({ createdAt: -1 });
audioTagSchema.index({ className: 1, confidence: -1 });
audioTagSchema.index({ isPrimary: 1, createdAt: -1 });

const AudioTag = mongoose.model('AudioTag', audioTagSchema);

export default AudioTag;
