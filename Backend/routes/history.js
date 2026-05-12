// Combined history listing routes
import express from 'express';
import VideoHistory from '../models/VideoHistory.js';
import AudioHistory from '../models/AudioHistory.js';
import FusionHistory from '../models/FusionHistory.js';

const router = express.Router();

// get all records
router.get('/', async (req, res) => {
  try {
    const { limit = 50 } = req.query;
    const perCollection = Math.ceil(parseInt(limit) / 3);

    const [videos, audios, fusions] = await Promise.all([
      VideoHistory.find().sort('-createdAt').limit(perCollection).lean(),
      AudioHistory.find().sort('-createdAt').limit(perCollection).lean(),
      FusionHistory.find().sort('-createdAt').limit(perCollection).lean()
    ]);


    const tagged = [
      ...videos.map(v => ({ ...v, type: v.source === 'stream' ? 'video_stream' : 'video' })),
      ...audios.map(a => ({ ...a, type: a.source === 'stream' ? 'audio_stream' : 'audio' })),
      ...fusions.map(f => ({ ...f, type: f.source === 'stream' ? 'fusion_stream' : 'fusion' }))
    ];


    tagged.sort((a, b) => new Date(b.createdAt) - new Date(a.createdAt));
    const data = tagged.slice(0, parseInt(limit));

    res.json({ success: true, count: data.length, data });
  } catch (error) {
    res.status(500).json({ success: false, error: error.message });
  }
});

router.get('/:mediaId', async (req, res) => {
  try {
    const id = req.params.mediaId;
    const result =
      await VideoHistory.findById(id) ||
      await AudioHistory.findById(id) ||
      await FusionHistory.findById(id);

    if (!result) return res.status(404).json({ success: false, error: 'Not found' });
    res.json({ success: true, data: result });
  } catch (error) {
    res.status(500).json({ success: false, error: error.message });
  }
});

export default router;
