// Audio history CRUD routes
import express from 'express';
import AudioHistory from '../models/AudioHistory.js';

const router = express.Router();

// get all records
router.get('/', async (req, res) => {
  try {
    const { limit = 50, source } = req.query;
    const query = {};
    if (source && ['file', 'stream'].includes(source)) query.source = source;
    const predictions = await AudioHistory.find(query).sort('-createdAt').limit(parseInt(limit));
    res.json({ success: true, count: predictions.length, data: predictions });
  } catch (error) {
    res.status(500).json({ success: false, error: error.message });
  }
});

// create new record
router.post('/', async (req, res) => {
  try {
    const entry = new AudioHistory(req.body);
    await entry.save();
    res.status(201).json({ success: true, data: entry });
  } catch (error) {
    res.status(500).json({ success: false, error: error.message });
  }
});

// delete by id
router.delete('/:id', async (req, res) => {
  try {
    const result = await AudioHistory.findByIdAndDelete(req.params.id);
    if (!result) return res.status(404).json({ success: false, error: 'Not found' });
    res.json({ success: true, message: 'Audio history entry deleted' });
  } catch (error) {
    res.status(500).json({ success: false, error: error.message });
  }
});

export default router;
