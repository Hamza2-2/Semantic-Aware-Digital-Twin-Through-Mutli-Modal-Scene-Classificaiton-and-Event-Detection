// Uploaded media file model
import mongoose from 'mongoose';

const mediaSchema = new mongoose.Schema({
  mediaId: {
    type: String,
    required: true,
    unique: true,
    default: () => `media_${Date.now()}_${Math.random().toString(36).substr(2, 9)}`,
    index: true
  },
  fileName: {
    type: String,
    trim: true
  },
  fileUrl: {
    type: String,
    trim: true
  },
  mediaType: {
    type: String,
    required: [true, 'Media type is required'],
    enum: {
      values: ['audio', 'video', 'fusion'],
      message: 'Media type must be "audio", "video", or "fusion"'
    }
  },
  enteredAt: {
    type: Date,
    default: Date.now
  },
  uploadedBy: {
    type: mongoose.Schema.Types.ObjectId,
    ref: 'Admin'
  }
}, {
  timestamps: true,
  collection: 'media'
});

// check file name or url exists
mediaSchema.pre('validate', function(next) {
  if (!this.fileName && !this.fileUrl) {
    return next(new Error('Either fileName or fileUrl must be provided'));
  }
  next();
});

mediaSchema.index({ mediaType: 1, enteredAt: -1 });

const Media = mongoose.model('Media', mediaSchema);

export default Media;
