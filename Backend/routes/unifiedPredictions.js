// Prediction create, list, sync routes
import express from 'express';
import VideoHistory from '../models/VideoHistory.js';
import AudioHistory from '../models/AudioHistory.js';
import FusionHistory from '../models/FusionHistory.js';
import Prediction from '../models/Prediction.js';
import VideoTag from '../models/VideoTag.js';
import AudioTag from '../models/AudioTag.js';
import FusionTag from '../models/FusionTag.js';
import Event from '../models/Event.js';
import Device from '../models/Device.js';

const router = express.Router();

function historyModelForType(type) {
  if (type === 'video' || type === 'video_stream') return VideoHistory;
  if (type === 'audio' || type === 'audio_stream') return AudioHistory;
  if (type === 'fusion' || type === 'fusion_stream') return FusionHistory;
  return null;
}

function tagModelForType(type) {
  if (type === 'video' || type === 'video_stream') return VideoTag;
  if (type === 'audio' || type === 'audio_stream') return AudioTag;
  if (type === 'fusion' || type === 'fusion_stream') return FusionTag;
  return null;
}

function sourceModelName(type) {
  if (type === 'video' || type === 'video_stream') return 'VideoHistory';
  if (type === 'audio' || type === 'audio_stream') return 'AudioHistory';
  if (type === 'fusion' || type === 'fusion_stream') return 'FusionHistory';
  return 'VideoHistory';
}

function sourceCollectionName(type) {
  if (type === 'video' || type === 'video_stream') return 'video_history';
  if (type === 'audio' || type === 'audio_stream') return 'audio_history';
  if (type === 'fusion' || type === 'fusion_stream') return 'fusion_history';
  return 'video_history';
}

function deriveType(doc, collection) {
  const isStream = doc.source === 'stream';
  if (collection === 'video') return isStream ? 'video_stream' : 'video';
  if (collection === 'audio') return isStream ? 'audio_stream' : 'audio';
  if (collection === 'fusion') return isStream ? 'fusion_stream' : 'fusion';
  return 'video';
}

function transform(p, type) {
  const cls = (p.predictedClass || '').trim() || null;
  const meta = p.metadata || {};
  return {
    id: p._id.toString(),
    _id: p._id,
    type,
    fileName: p.fileName || null,
    filePath: p.filePath || null,
    prediction: cls,
    predictedClass: cls,
    confidence: p.confidence,
    topPredictions: p.topPredictions || [],
    processingTime: p.processingTime,
    modelVersion: p.modelVersion,
    source: p.source,
    streamUrl: p.streamUrl,
    deviceName: p.deviceName,
    streamDuration: p.streamDuration,
    fusionMethod: p.fusionMethod,
    multiScene: p.multiScene,
    isMultilabel: !!meta.isMultilabel,
    detectedClasses: meta.detectedClasses || null,
    result: meta.rawResult || null,
    eventType: meta.eventType || null,
    eventDetectionEnabled: !!meta.eventDetectionEnabled,
    timestamp: p.createdAt,
    createdAt: p.createdAt,
    updatedAt: p.updatedAt
  };
}

function transformPrediction(p) {
  const meta = p.metadata || {};
  return {
    id: p._id.toString(),
    _id: p._id,
    type: p.type,
    predictedClass: p.predictedClass,
    prediction: p.predictedClass,
    confidence: p.confidence,
    fileName: p.fileName,
    source: p.source,
    processingTime: p.processingTime,
    modelVersion: p.modelVersion,
    status: p.status,
    deviceName: p.deviceName,
    deviceId: p.deviceId,
    streamUrl: p.streamUrl,
    tagCount: p.tagCount,
    sourceCollection: p.sourceCollection,
    sourceModel: p.sourceModel,
    historyRef: p.historyRef,
    metadata: p.metadata,
    isMultilabel: !!meta.isMultilabel,
    detectedClasses: meta.detectedClasses || null,
    result: meta.rawResult || null,
    eventType: meta.eventType || null,
    eventDetectionEnabled: !!meta.eventDetectionEnabled,
    createdAt: p.createdAt,
    updatedAt: p.updatedAt,
    timestamp: p.createdAt
  };
}

// get all records
router.get('/', async (req, res) => {
  try {
    const { type, limit = 50, skip = 0, view } = req.query;
    const lim = parseInt(limit);
    const sk  = parseInt(skip);

    const validTypes = ['video', 'audio', 'fusion', 'video_stream', 'audio_stream', 'fusion_stream'];


    if (view === 'unified') {
      const query = {};
      if (type && validTypes.includes(type)) query.type = type;

      const [docs, total] = await Promise.all([
        Prediction.find(query).sort('-createdAt').skip(sk).limit(lim).lean(),
        Prediction.countDocuments(query)
      ]);

      const data = docs.map(d => transformPrediction(d));
      return res.json({ success: true, count: data.length, total, data });
    }


    if (type && validTypes.includes(type)) {
      const Model = historyModelForType(type);
      const sourceFilter = type.includes('stream') ? 'stream' : 'file';
      const query = { source: sourceFilter };

      const [docs, total] = await Promise.all([
        Model.find(query).sort('-createdAt').skip(sk).limit(lim).lean(),
        Model.countDocuments(query)
      ]);

      const data = docs.map(d => transform(d, type));
      return res.json({ success: true, count: data.length, total, data });
    }


    const [vDocs, aDocs, fDocs, vTotal, aTotal, fTotal] = await Promise.all([
      VideoHistory.find().sort('-createdAt').lean(),
      AudioHistory.find().sort('-createdAt').lean(),
      FusionHistory.find().sort('-createdAt').lean(),
      VideoHistory.countDocuments(),
      AudioHistory.countDocuments(),
      FusionHistory.countDocuments()
    ]);

    const merged = [
      ...vDocs.map(d => transform(d, deriveType(d, 'video'))),
      ...aDocs.map(d => transform(d, deriveType(d, 'audio'))),
      ...fDocs.map(d => transform(d, deriveType(d, 'fusion')))
    ];

    merged.sort((a, b) => new Date(b.createdAt) - new Date(a.createdAt));
    const data = merged.slice(sk, sk + lim);
    const total = vTotal + aTotal + fTotal;

    res.json({ success: true, count: data.length, total, data });
  } catch (error) {
    console.error('Error fetching predictions:', error);
    res.status(500).json({ success: false, error: error.message });
  }
});

// get statistics
router.get('/stats', async (req, res) => {
  try {
    const [
      vFileCount, vStreamCount,
      aFileCount, aStreamCount,
      fFileCount, fStreamCount,
      predictionTotal
    ] = await Promise.all([
      VideoHistory.countDocuments({ source: 'file' }),
      VideoHistory.countDocuments({ source: 'stream' }),
      AudioHistory.countDocuments({ source: 'file' }),
      AudioHistory.countDocuments({ source: 'stream' }),
      FusionHistory.countDocuments({ source: 'file' }),
      FusionHistory.countDocuments({ source: 'stream' }),
      Prediction.countDocuments()
    ]);

    const total = vFileCount + vStreamCount + aFileCount + aStreamCount + fFileCount + fStreamCount;
    const streamTotal = vStreamCount + aStreamCount + fStreamCount;


    const classFilter = { $match: { predictedClass: { $type: 'string', $ne: '' } } };
    const groupStage = { $group: { _id: '$predictedClass', count: { $sum: 1 } } };
    const [vDist, aDist, fDist, pDist] = await Promise.all([
      VideoHistory.aggregate([classFilter, groupStage]),
      AudioHistory.aggregate([classFilter, groupStage]),
      FusionHistory.aggregate([classFilter, groupStage]),
      Prediction.aggregate([classFilter, groupStage])
    ]);


    const historyDistMap = {};
    [...vDist, ...aDist, ...fDist].forEach(d => {
      if (d._id) historyDistMap[d._id] = (historyDistMap[d._id] || 0) + d.count;
    });

    const useHistory = Object.keys(historyDistMap).length > 0;
    const distMap = useHistory ? historyDistMap : {};
    if (!useHistory) {
      pDist.forEach(d => {
        if (d._id) distMap[d._id] = (distMap[d._id] || 0) + d.count;
      });
    }

    const distribution = Object.entries(distMap)
      .map(([cls, count]) => ({ class: cls, count }))
      .sort((a, b) => b.count - a.count);


    const [videoTagCount, audioTagCount, fusionTagCount] = await Promise.all([
      VideoTag.countDocuments(),
      AudioTag.countDocuments(),
      FusionTag.countDocuments()
    ]);

    res.json({
      success: true,
      stats: {
        total,
        predictionTableTotal: predictionTotal,
        video: vFileCount,
        audio: aFileCount,
        fusion: fFileCount,
        videoStream: vStreamCount,
        audioStream: aStreamCount,
        fusionStream: fStreamCount,
        streamTotal,
        tags: {
          video: videoTagCount,
          audio: audioTagCount,
          fusion: fusionTagCount,
          total: videoTagCount + audioTagCount + fusionTagCount
        },
        distribution
      }
    });
  } catch (error) {
    console.error('Error fetching stats:', error);
    res.status(500).json({ success: false, error: error.message });
  }
});

router.get('/distribution', async (req, res) => {
  try {
    const classFilter = { $match: { predictedClass: { $type: 'string', $ne: '' } } };
    const groupStage = { $group: { _id: '$predictedClass', count: { $sum: 1 } } };


    const [vDist, aDist, fDist, pDist] = await Promise.all([
      VideoHistory.aggregate([classFilter, groupStage]),
      AudioHistory.aggregate([classFilter, groupStage]),
      FusionHistory.aggregate([classFilter, groupStage]),
      Prediction.aggregate([classFilter, groupStage])
    ]);


    const historyDistMap = {};
    [...vDist, ...aDist, ...fDist].forEach(d => {
      if (d._id) historyDistMap[d._id] = (historyDistMap[d._id] || 0) + d.count;
    });


    const useHistory = Object.keys(historyDistMap).length > 0;
    const distMap = useHistory ? historyDistMap : {};

    if (!useHistory) {
      pDist.forEach(d => {
        if (d._id) distMap[d._id] = (distMap[d._id] || 0) + d.count;
      });
    }

    const data = Object.entries(distMap)
      .map(([className, count]) => ({ className, count }))
      .sort((a, b) => b.count - a.count);

    res.json({ success: true, data });
  } catch (error) {
    console.error('Error fetching distribution:', error);
    res.status(500).json({ success: false, error: error.message });
  }
});

// get one by id
router.get('/:id', async (req, res) => {
  try {
    const id = req.params.id;


    const prediction = await Prediction.findById(id).lean();
    if (prediction) {
      const HistoryModel = historyModelForType(prediction.type);
      const TagModel = tagModelForType(prediction.type);

      const [historyDoc, tags] = await Promise.all([
        HistoryModel ? HistoryModel.findById(prediction.historyRef).lean() : null,
        TagModel ? TagModel.find({ predictionRef: id }).sort('rank').lean() : []
      ]);

      return res.json({
        success: true,
        data: {
          ...transformPrediction(prediction),
          history: historyDoc,
          tags: tags.map(t => ({
            id: t._id.toString(),
            className: t.className,
            confidence: t.confidence,
            rank: t.rank,
            isPrimary: t.isPrimary
          }))
        }
      });
    }


    let doc = await VideoHistory.findById(id).lean();
    let collection = 'video';
    if (!doc) { doc = await AudioHistory.findById(id).lean(); collection = 'audio'; }
    if (!doc) { doc = await FusionHistory.findById(id).lean(); collection = 'fusion'; }

    if (!doc) {
      return res.status(404).json({ success: false, error: 'Prediction not found' });
    }

    res.json({
      success: true,
      data: { id: doc._id.toString(), type: deriveType(doc, collection), ...doc }
    });
  } catch (error) {
    console.error('Error fetching prediction:', error);
    res.status(500).json({ success: false, error: error.message });
  }
});

// create new record
router.post('/', async (req, res) => {
  try {
    const {
      type,
      fileName,
      filePath,
      predictedClass,
      confidence,
      topPredictions,
      result,
      processingTime,
      modelVersion,
      source,
      isDemo,
      isMultilabel,
      detectedClasses,
      streamUrl,
      deviceName,
      deviceId,
      streamDuration,
      fusionMethod,
      multiScene,
      eventType,
      eventDetectionEnabled
    } = req.body;


    if (!type || !fileName || !predictedClass) {
      return res.status(400).json({
        success: false,
        error: 'type, fileName, and predictedClass are required'
      });
    }

    const HistoryModel = historyModelForType(type);
    if (!HistoryModel) {
      return res.status(400).json({
        success: false,
        error: `Invalid type "${type}". Must be one of: video, audio, fusion, video_stream, audio_stream, fusion_stream`
      });
    }


    let finalTopPredictions = topPredictions;
    if (!finalTopPredictions || finalTopPredictions.length === 0) {
      if (result?.topPredictions) {
        finalTopPredictions = result.topPredictions;
      } else if (result?.top_predictions) {
        finalTopPredictions = result.top_predictions;
      } else if (result?.probabilities) {
        finalTopPredictions = Object.entries(result.probabilities)
          .map(([className, conf]) => ({ class: className, confidence: conf }))
          .sort((a, b) => b.confidence - a.confidence)
          .slice(0, 5);
      } else {
        finalTopPredictions = [{ class: predictedClass, confidence: confidence || 0 }];
      }
    }


    finalTopPredictions = finalTopPredictions.map(p => ({
      class: p.class || p.className || p.label || 'unknown',
      confidence: parseFloat(p.confidence || p.probability || 0)
    }));

    const resolvedSource = source || (type.includes('stream') ? 'stream' : 'file');


    const historyData = {
      fileName,
      filePath,
      predictedClass,
      confidence: parseFloat(confidence) || 0,
      topPredictions: finalTopPredictions,
      processingTime: processingTime || 0,
      modelVersion: modelVersion || '1.0',
      source: resolvedSource,
      streamUrl: streamUrl || undefined,
      deviceName: deviceName || undefined,
      deviceId: deviceId || undefined,
      streamDuration: streamDuration ? parseInt(streamDuration) : undefined,
      metadata: { isDemo, isMultilabel, detectedClasses, rawResult: result, eventType: eventType || null, eventDetectionEnabled: !!eventDetectionEnabled }
    };

    // Resolve deviceRef from deviceId string
    let deviceRef;
    if (deviceId) {
      try {
        const deviceDoc = await Device.findOne({ deviceId });
        if (deviceDoc) deviceRef = deviceDoc._id;
      } catch (_) { /* non-critical */ }
    }
    if (deviceRef) historyData.deviceRef = deviceRef;

    if (type === 'fusion' || type === 'fusion_stream') {
      historyData.fusionMethod = fusionMethod || undefined;
      historyData.multiScene = multiScene || false;
    }

    const historyDoc = new HistoryModel(historyData);
    await historyDoc.save();


    const predictionDoc = new Prediction({
      historyRef: historyDoc._id,
      sourceModel: sourceModelName(type),
      sourceCollection: sourceCollectionName(type),
      type,
      predictedClass,
      confidence: parseFloat(confidence) || 0,
      fileName,
      source: resolvedSource,
      processingTime: processingTime || 0,
      modelVersion: modelVersion || '1.0',
      status: 'completed',
      deviceName: deviceName || undefined,
      deviceId: deviceId || undefined,
      deviceRef: deviceRef || undefined,
      streamUrl: streamUrl || undefined,
      tagCount: finalTopPredictions.length,
      metadata: { isDemo, isMultilabel, detectedClasses, eventType: eventType || null, eventDetectionEnabled: !!eventDetectionEnabled }
    });
    await predictionDoc.save();


    const TagModel = tagModelForType(type);
    if (TagModel && finalTopPredictions.length > 0) {
      const tagDocs = finalTopPredictions.map((tp, idx) => ({
        historyRef: historyDoc._id,
        predictionRef: predictionDoc._id,
        className: tp.class,
        confidence: tp.confidence,
        rank: idx + 1,
        isPrimary: idx === 0,
        fileName,
        source: resolvedSource,
        deviceName: deviceName || undefined,
        ...(type.includes('fusion') ? { fusionMethod: fusionMethod || undefined } : {})
      }));

      await TagModel.insertMany(tagDocs);
    }

    res.status(201).json({
      success: true,
      message: 'Prediction saved successfully',
      data: {
        id: predictionDoc._id.toString(),
        historyId: historyDoc._id.toString(),
        type,
        fileName: historyDoc.fileName,
        predictedClass: historyDoc.predictedClass,
        confidence: historyDoc.confidence,
        topPredictions: historyDoc.topPredictions,
        tagCount: finalTopPredictions.length,
        createdAt: historyDoc.createdAt
      }
    });
  } catch (error) {
    console.error('Error saving prediction:', error);
    res.status(500).json({ success: false, error: error.message });
  }
});

// delete by id
router.delete('/:id', async (req, res) => {
  try {
    const id = req.params.id;


    const prediction = await Prediction.findById(id);
    if (prediction) {
      const TagModel = tagModelForType(prediction.type);
      if (TagModel) await TagModel.deleteMany({ predictionRef: id });

      const HistoryModel = historyModelForType(prediction.type);
      if (HistoryModel && prediction.historyRef) {
        await HistoryModel.findByIdAndDelete(prediction.historyRef);
      }

      await Prediction.findByIdAndDelete(id);


      await Event.deleteMany({ predictionId: id });

      return res.json({ success: true, message: 'Prediction, history, tags, and linked events deleted successfully' });
    }


    let result = await VideoHistory.findByIdAndDelete(id);
    if (!result) result = await AudioHistory.findByIdAndDelete(id);
    if (!result) result = await FusionHistory.findByIdAndDelete(id);

    if (!result) {
      return res.status(404).json({ success: false, error: 'Prediction not found' });
    }


    const pred = await Prediction.findOneAndDelete({ historyRef: id });
    if (pred) {
      const TagModel = tagModelForType(pred.type);
      if (TagModel) await TagModel.deleteMany({ predictionRef: pred._id });

      await Event.deleteMany({ predictionId: pred._id });
    }

    res.json({ success: true, message: 'Prediction and linked events deleted successfully' });
  } catch (error) {
    console.error('Error deleting prediction:', error);
    res.status(500).json({ success: false, error: error.message });
  }
});

// clear all records
router.delete('/', async (req, res) => {
  try {
    const { type } = req.query;
    const validTypes = ['video', 'audio', 'fusion', 'video_stream', 'audio_stream', 'fusion_stream'];

    if (type && validTypes.includes(type)) {
      const HistoryModel = historyModelForType(type);
      const TagModel = tagModelForType(type);
      const sourceFilter = type.includes('stream') ? 'stream' : 'file';

      const [histResult, predResult, tagResult, eventResult] = await Promise.all([
        HistoryModel.deleteMany({ source: sourceFilter }),
        Prediction.deleteMany({ type }),
        TagModel.deleteMany({ source: sourceFilter }),
        Event.deleteMany({ sourceType: type })
      ]);

      return res.json({
        success: true,
        message: `Deleted ${histResult.deletedCount} ${type} history, ${predResult.deletedCount} predictions, ${tagResult.deletedCount} tags, ${eventResult.deletedCount} events`,
        deletedCount: histResult.deletedCount
      });
    }


    const [v, a, f, p, vt, at, ft, ev] = await Promise.all([
      VideoHistory.deleteMany({}),
      AudioHistory.deleteMany({}),
      FusionHistory.deleteMany({}),
      Prediction.deleteMany({}),
      VideoTag.deleteMany({}),
      AudioTag.deleteMany({}),
      FusionTag.deleteMany({}),
      Event.deleteMany({})
    ]);

    const histTotal = v.deletedCount + a.deletedCount + f.deletedCount;
    const tagTotal = vt.deletedCount + at.deletedCount + ft.deletedCount;

    res.json({
      success: true,
      message: `Deleted ${histTotal} history (video: ${v.deletedCount}, audio: ${a.deletedCount}, fusion: ${f.deletedCount}), ${p.deletedCount} predictions, ${tagTotal} tags, ${ev.deletedCount} events`,
      deletedCount: histTotal
    });
  } catch (error) {
    console.error('Error clearing predictions:', error);
    res.status(500).json({ success: false, error: error.message });
  }
});

// bulk sync from client
router.post('/sync', async (req, res) => {
  try {
    let synced = 0;
    let tagsCreated = 0;

    const existingRefs = new Set(
      (await Prediction.find({}, 'historyRef').lean()).map(p => p.historyRef.toString())
    );

    const collections = [
      { model: VideoHistory, tagModel: VideoTag, colName: 'video' },
      { model: AudioHistory, tagModel: AudioTag, colName: 'audio' },
      { model: FusionHistory, tagModel: FusionTag, colName: 'fusion' }
    ];

    for (const { model: HistModel, tagModel: TagModel, colName } of collections) {
      const docs = await HistModel.find().lean();

      for (const doc of docs) {
        if (existingRefs.has(doc._id.toString())) continue;

        const isStream = doc.source === 'stream';
        const type = isStream ? `${colName}_stream` : colName;

        const predDoc = new Prediction({
          historyRef: doc._id,
          sourceModel: sourceModelName(type),
          sourceCollection: sourceCollectionName(type),
          type,
          predictedClass: doc.predictedClass,
          confidence: doc.confidence,
          fileName: doc.fileName,
          source: doc.source || 'file',
          processingTime: doc.processingTime || 0,
          modelVersion: doc.modelVersion || '1.0',
          status: 'completed',
          deviceName: doc.deviceName,
          deviceId: doc.deviceId,
          streamUrl: doc.streamUrl,
          tagCount: (doc.topPredictions || []).length,
          metadata: doc.metadata || {}
        });
        await predDoc.save();
        synced++;

        if (doc.topPredictions && doc.topPredictions.length > 0) {
          const tagDocs = doc.topPredictions.map((tp, idx) => ({
            historyRef: doc._id,
            predictionRef: predDoc._id,
            className: tp.class,
            confidence: tp.confidence,
            rank: idx + 1,
            isPrimary: idx === 0,
            fileName: doc.fileName,
            source: doc.source || 'file',
            deviceName: doc.deviceName,
            ...(colName === 'fusion' ? { fusionMethod: doc.fusionMethod } : {})
          }));
          await TagModel.insertMany(tagDocs);
          tagsCreated += tagDocs.length;
        }
      }
    }

    res.json({
      success: true,
      message: `Synced ${synced} predictions and created ${tagsCreated} tags`,
      synced,
      tagsCreated
    });
  } catch (error) {
    console.error('Error syncing predictions:', error);
    res.status(500).json({ success: false, error: error.message });
  }
});

export default router;
