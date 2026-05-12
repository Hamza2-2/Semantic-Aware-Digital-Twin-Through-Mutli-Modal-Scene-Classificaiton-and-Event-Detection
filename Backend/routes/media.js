// Media upload and listing routes
import express from 'express';
import Media from '../models/Media.js';

const router = express.Router();

// get all records
router.get('/', async (req, res) => {
  try {
    const { type, limit = 50 } = req.query;
    const query = type ? { mediaType: type } : {};
    const media = await Media.find(query).sort('-createdAt').limit(parseInt(limit));
    res.json({ success: true, count: media.length, data: media });
  } catch (error) {
    res.status(500).json({ success: false, error: error.message });
  }
});

// get one by id
router.get('/:id', async (req, res) => {
  try {
    const media = await Media.findById(req.params.id);
    if (!media) return res.status(404).json({ success: false, error: 'Media not found' });
    res.json({ success: true, data: media });
  } catch (error) {
    res.status(500).json({ success: false, error: error.message });
  }
});

// upload file
router.post('/upload', async (req, res) => {
  try {
    const { fileName, fileUrl, mediaType } = req.body;
    const media = new Media({ fileName, fileUrl, mediaType });
    await media.save();
    res.status(201).json({ success: true, data: media });
  } catch (error) {
    res.status(500).json({ success: false, error: error.message });
  }
});

export default router;
