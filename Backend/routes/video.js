// Video upload and listing routes
import express from 'express';
import VideoHistory from '../models/VideoHistory.js';

const router = express.Router();

// get all records
router.get('/', async (req, res) => {
  try {
    const { limit = 50 } = req.query;
    const videos = await VideoHistory.find({ source: 'file' }).sort('-createdAt').limit(parseInt(limit));
    res.json({
      success: true,
      count: videos.length,
      data: videos.map(v => ({
        video_id: v._id,
        fileName: v.fileName,
        filePath: v.filePath,
        predictedClass: v.predictedClass,
        confidence: v.confidence,
        tags: v.topPredictions,
        createdAt: v.createdAt
      }))
    });
  } catch (error) {
    res.status(500).json({ success: false, error: error.message });
  }
});

// get video by id
router.get('/:video_id', async (req, res) => {
  try {
    const video = await VideoHistory.findById(req.params.video_id);
    if (!video) return res.status(404).json({ success: false, error: 'Video not found' });
    res.json({ success: true, data: video });
  } catch (error) {
    res.status(500).json({ success: false, error: error.message });
  }
});

// get tags for video
router.get('/:video_id/tags', async (req, res) => {
  try {
    const video = await VideoHistory.findById(req.params.video_id);
    if (!video) return res.status(404).json({ success: false, error: 'Video not found' });
    res.json({ success: true, data: video.topPredictions || [] });
  } catch (error) {
    res.status(500).json({ success: false, error: error.message });
  }
});

// delete video by id
router.delete('/:video_id', async (req, res) => {
  try {
    const result = await VideoHistory.findByIdAndDelete(req.params.video_id);
    if (!result) return res.status(404).json({ success: false, error: 'Video not found' });
    res.json({ success: true, message: 'Video deleted' });
  } catch (error) {
    res.status(500).json({ success: false, error: error.message });
  }
});

export default router;
