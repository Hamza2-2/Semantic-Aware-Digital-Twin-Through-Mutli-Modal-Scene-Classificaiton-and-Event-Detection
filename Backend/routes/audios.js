// Audio file listing routes
import express from 'express';
import AudioHistory from '../models/AudioHistory.js';

const router = express.Router();

// get all records
router.get('/', async (req, res) => {
  try {
    const { limit = 50 } = req.query;
    const audios = await AudioHistory.find({ source: 'file' }).sort('-createdAt').limit(parseInt(limit));
    res.json({
      success: true,
      count: audios.length,
      data: audios.map(a => ({
        audio_id: a._id,
        fileName: a.fileName,
        filePath: a.filePath,
        predictedClass: a.predictedClass,
        confidence: a.confidence,
        tags: a.topPredictions,
        createdAt: a.createdAt
      }))
    });
  } catch (error) {
    res.status(500).json({ success: false, error: error.message });
  }
});

// get audio by id
router.get('/:audio_id', async (req, res) => {
  try {
    const audio = await AudioHistory.findById(req.params.audio_id);
    if (!audio) {
      return res.status(404).json({ success: false, error: 'Audio not found' });
    }
    res.json({ success: true, data: audio });
  } catch (error) {
    res.status(500).json({ success: false, error: error.message });
  }
});

// get tags for audio
router.get('/:audio_id/tags', async (req, res) => {
  try {
    const audio = await AudioHistory.findById(req.params.audio_id);
    if (!audio) return res.status(404).json({ success: false, error: 'Audio not found' });
    res.json({ success: true, data: audio.topPredictions || [] });
  } catch (error) {
    res.status(500).json({ success: false, error: error.message });
  }
});

// delete audio by id
router.delete('/:audio_id', async (req, res) => {
  try {
    const result = await AudioHistory.findByIdAndDelete(req.params.audio_id);
    if (!result) return res.status(404).json({ success: false, error: 'Audio not found' });
    res.json({ success: true, message: 'Audio deleted' });
  } catch (error) {
    res.status(500).json({ success: false, error: error.message });
  }
});

export default router;
