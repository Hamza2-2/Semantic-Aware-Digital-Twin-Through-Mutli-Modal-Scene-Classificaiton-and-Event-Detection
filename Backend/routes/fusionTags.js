// Fusion tag CRUD routes
import express from 'express';
import FusionTag from '../models/FusionTag.js';
import FusionHistory from '../models/FusionHistory.js';

const router = express.Router();

// get all records
router.get('/', async (req, res) => {
  try {
    const { limit = 100, skip = 0, className, isPrimary, fusionMethod } = req.query;
    const lim = parseInt(limit);
    const sk = parseInt(skip);

    const query = {};
    if (className) query.className = className;
    if (isPrimary !== undefined) query.isPrimary = isPrimary === 'true';
    if (fusionMethod) query.fusionMethod = fusionMethod;

    const [tags, total] = await Promise.all([
      FusionTag.find(query).sort('-createdAt').skip(sk).limit(lim).lean(),
      FusionTag.countDocuments(query)
    ]);

    const data = tags.map(t => ({
      id: t._id.toString(),
      className: t.className,
      confidence: t.confidence,
      rank: t.rank,
      isPrimary: t.isPrimary,
      fileName: t.fileName,
      source: t.source,
      deviceName: t.deviceName,
      fusionMethod: t.fusionMethod,
      historyRef: t.historyRef,
      predictionRef: t.predictionRef,
      createdAt: t.createdAt
    }));

    res.json({ success: true, count: data.length, total, data });
  } catch (error) {
    res.status(500).json({ success: false, error: error.message });
  }
});

// get distinct classes
router.get('/classes', async (req, res) => {
  try {
    const classes = await FusionTag.aggregate([
      { $group: { _id: '$className', count: { $sum: 1 }, avgConfidence: { $avg: '$confidence' } } },
      { $sort: { count: -1 } }
    ]);

    res.json({
      success: true,
      count: classes.length,
      data: classes.map(c => ({
        className: c._id,
        count: c.count,
        avgConfidence: Math.round(c.avgConfidence * 10000) / 10000
      }))
    });
  } catch (error) {
    res.status(500).json({ success: false, error: error.message });
  }
});

// get statistics
router.get('/stats', async (req, res) => {
  try {
    const [total, primaryCount, classDist, topByConfidence, methodDist] = await Promise.all([
      FusionTag.countDocuments(),
      FusionTag.countDocuments({ isPrimary: true }),
      FusionTag.aggregate([
        { $group: { _id: '$className', count: { $sum: 1 } } },
        { $sort: { count: -1 } },
        { $limit: 10 }
      ]),
      FusionTag.find({ isPrimary: true }).sort('-confidence').limit(5).lean(),
      FusionTag.aggregate([
        { $match: { fusionMethod: { $ne: null } } },
        { $group: { _id: '$fusionMethod', count: { $sum: 1 } } },
        { $sort: { count: -1 } }
      ])
    ]);

    res.json({
      success: true,
      stats: {
        total,
        primaryCount,
        uniqueClasses: classDist.length,
        topClasses: classDist.map(c => ({ className: c._id, count: c.count })),
        highestConfidence: topByConfidence.map(t => ({
          className: t.className,
          confidence: t.confidence,
          fileName: t.fileName
        })),
        fusionMethods: methodDist.map(m => ({ method: m._id, count: m.count }))
      }
    });
  } catch (error) {
    res.status(500).json({ success: false, error: error.message });
  }
});

// get tags by history id
router.get('/by-history/:historyId', async (req, res) => {
  try {
    const tags = await FusionTag.find({ historyRef: req.params.historyId }).sort('rank').lean();

    res.json({
      success: true,
      count: tags.length,
      data: tags.map(t => ({
        id: t._id.toString(),
        className: t.className,
        confidence: t.confidence,
        rank: t.rank,
        isPrimary: t.isPrimary,
        fusionMethod: t.fusionMethod
      }))
    });
  } catch (error) {
    res.status(500).json({ success: false, error: error.message });
  }
});

// get one by id
router.get('/:id', async (req, res) => {
  try {
    const tag = await FusionTag.findById(req.params.id).lean();
    if (!tag) {
      return res.status(404).json({ success: false, error: 'Tag not found' });
    }

    const history = await FusionHistory.findById(tag.historyRef).lean();

    res.json({
      success: true,
      data: {
        id: tag._id.toString(),
        className: tag.className,
        confidence: tag.confidence,
        rank: tag.rank,
        isPrimary: tag.isPrimary,
        fileName: tag.fileName,
        source: tag.source,
        deviceName: tag.deviceName,
        fusionMethod: tag.fusionMethod,
        historyRef: tag.historyRef,
        predictionRef: tag.predictionRef,
        createdAt: tag.createdAt,
        history: history || null
      }
    });
  } catch (error) {
    res.status(500).json({ success: false, error: error.message });
  }
});

// delete by id
router.delete('/:id', async (req, res) => {
  try {
    const result = await FusionTag.findByIdAndDelete(req.params.id);
    if (!result) {
      return res.status(404).json({ success: false, error: 'Tag not found' });
    }
    res.json({ success: true, message: 'Fusion tag deleted' });
  } catch (error) {
    res.status(500).json({ success: false, error: error.message });
  }
});

// clear all records
router.delete('/', async (req, res) => {
  try {
    const { className } = req.query;
    const query = className ? { className } : {};
    const result = await FusionTag.deleteMany(query);
    res.json({
      success: true,
      message: `Deleted ${result.deletedCount} fusion tags`,
      deletedCount: result.deletedCount
    });
  } catch (error) {
    res.status(500).json({ success: false, error: error.message });
  }
});

export default router;
