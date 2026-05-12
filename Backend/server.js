// Express server setup and route mounting
import express from 'express';
import cors from 'cors';
import morgan from 'morgan';
import helmet from 'helmet';
import dotenv from 'dotenv';
import path from 'path';
import { fileURLToPath } from 'url';
import connectDB from './config/database.js';
import videoRoutes from './routes/video.js';
import mediaRoutes from './routes/media.js';
import tagRoutes from './routes/tags.js';
import historyRoutes from './routes/history.js';
import audioHistoryRoutes from './routes/audioHistory.js';
import videoHistoryRoutes from './routes/videoHistory.js';
import fusionHistoryRoutes from './routes/fusionHistory.js';
import unifiedPredictionRoutes from './routes/unifiedPredictions.js';
import audiosRoutes from './routes/audios.js';
import audioTagsRoutes from './routes/audioTags.js';
import fusionTagsRoutes from './routes/fusionTags.js';
import devicesRoutes from './routes/devices.js';
import eventsRoutes from './routes/events.js';
import locationsRoutes from './routes/locations.js';
import authRoutes from './routes/auth.js';

dotenv.config();

const app = express();

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);

connectDB();

app.use(helmet());
app.use(cors());

app.use(morgan((tokens, req, res) => {
  const status = parseInt(tokens.status(req, res), 10);
  const method = tokens.method(req, res);

  if (status < 400 && method === 'GET') return null;
  const color = status >= 500 ? '\x1b[31m' : status >= 400 ? '\x1b[33m' : '\x1b[32m';
  return `${color}${method}\x1b[0m ${tokens.url(req, res)} ${color}${status}\x1b[0m ${tokens['response-time'](req, res)}ms`;
}));
app.use(express.json());
app.use(express.urlencoded({ extended: true }));

app.use('/uploads', express.static(path.join(__dirname, 'uploads')));

// api info endpoint
app.get('/api', (req, res) => {
  res.status(200).json({
    message: 'Digital Twin (Multi-Video & Audio Tagging System) API',
    version: '2.0.0',
    endpoints: {
      health: 'GET /health',
      video: {
        upload: 'POST /video/upload — Upload video, run ML model, save tags',
        list: 'GET /video — List all videos with tags',
        getById: 'GET /video/:video_id — Get video details with tags',
        getTags: 'GET /video/:video_id/tags — Get tags for a video',
      },
      media: {
        upload: 'POST /media/upload — Upload media file',
        list: 'GET /media — List all media',
        getById: 'GET /media/:id — Get media by ID',
      },
      videoTags: {
        list: 'GET /tags — List all video tags (query: className, isPrimary, limit, skip)',
        classes: 'GET /tags/classes — Distinct video classes with counts',
        stats: 'GET /tags/stats — Video tag statistics',
        byHistory: 'GET /tags/by-history/:historyId — Tags for a video history entry',
        getById: 'GET /tags/:id — Get video tag by ID (includes history)',
        delete: 'DELETE /tags/:id — Delete a video tag',
        clear: 'DELETE /tags — Clear video tags (query: className)',
      },
      audioTags: {
        list: 'GET /audio-tags — List all audio tags',
        classes: 'GET /audio-tags/classes — Distinct audio classes with counts',
        stats: 'GET /audio-tags/stats — Audio tag statistics',
        byHistory: 'GET /audio-tags/by-history/:historyId — Tags for an audio history entry',
        getById: 'GET /audio-tags/:id — Get audio tag by ID',
        delete: 'DELETE /audio-tags/:id — Delete an audio tag',
        clear: 'DELETE /audio-tags — Clear audio tags',
      },
      fusionTags: {
        list: 'GET /fusion-tags — List all fusion tags (query: fusionMethod)',
        classes: 'GET /fusion-tags/classes — Distinct fusion classes with counts',
        stats: 'GET /fusion-tags/stats — Fusion tag statistics',
        byHistory: 'GET /fusion-tags/by-history/:historyId — Tags for a fusion history entry',
        getById: 'GET /fusion-tags/:id — Get fusion tag by ID',
        delete: 'DELETE /fusion-tags/:id — Delete a fusion tag',
        clear: 'DELETE /fusion-tags — Clear fusion tags',
      },
      history: {
        all: 'GET /history — Get all history',
        byMedia: 'GET /history/:mediaId — Get history by media ID',
        audio: 'GET/POST /history/audio — Audio history',
        video: 'GET/POST /history/video — Video history',
        fusion: 'GET/POST /history/fusion — Fusion history',
      },
      predictions: {
        list: 'GET /predictions — Get all predictions (query: type, limit, skip, view=unified)',
        stats: 'GET /predictions/stats — Prediction + tag statistics',
        distribution: 'GET /predictions/distribution — Class distribution',
        getById: 'GET /predictions/:id — Get prediction by ID (includes history & tags)',
        create: 'POST /predictions — Create prediction (auto-creates history + tags)',
        sync: 'POST /predictions/sync — Sync existing history into predictions & tags',
        delete: 'DELETE /predictions/:id — Delete prediction + history + tags',
        clear: 'DELETE /predictions — Clear all (query: type)',
      },
      devices: {
        list: 'GET /devices — List all saved devices',
        getById: 'GET /devices/:id — Get device by ID',
        create: 'POST /devices — Add a new device',
        update: 'PUT /devices/:id — Update a device',
        delete: 'DELETE /devices/:id — Delete a device',
        clear: 'DELETE /devices — Clear all devices',
        sync: 'POST /devices/sync — Bulk sync devices from client',
      },
      events: {
        list: 'GET /events — List events (query: eventType, severity, status, sourceType, limit)',
        types: 'GET /events/types — List distinct event types with counts',
        stats: 'GET /events/stats — Aggregate event statistics',
        getById: 'GET /events/:id — Get event by ID',
        create: 'POST /events — Create a new event (auto-creates Location doc)',
        update: 'PUT /events/:id — Update event (status, notes, severity)',
        delete: 'DELETE /events/:id — Delete event',
        clear: 'DELETE /events — Clear events (query: eventType)',
        nearby: 'GET /events/nearby — Find events near lat/lng',
      },
      locations: {
        list: 'GET /locations — List all locations (query: city, country, source)',
        nearby: 'GET /locations/nearby — Find locations near lat/lng',
        byIp: 'GET /locations/by-ip/:ip — Look up location by IP',
        getById: 'GET /locations/:id — Get location by ID',
        create: 'POST /locations — Create/upsert location',
        update: 'PUT /locations/:id — Update location',
        delete: 'DELETE /locations/:id — Delete location',
        clear: 'DELETE /locations — Clear all locations',
      }
    },
    timestamp: new Date().toISOString()
  });
});

// health check endpoint
app.get('/health', (req, res) => {
  res.status(200).json({
    status: 'OK',
    message: 'Server is running',
    timestamp: new Date().toISOString()
  });
});

app.use('/video', videoRoutes);
app.use('/media', mediaRoutes);
app.use('/tags', tagRoutes);
app.use('/history/audio', audioHistoryRoutes);
app.use('/history/video', videoHistoryRoutes);
app.use('/history/fusion', fusionHistoryRoutes);
app.use('/history', historyRoutes);
app.use('/predictions', unifiedPredictionRoutes);
app.use('/audios', audiosRoutes);
app.use('/audio-tags', audioTagsRoutes);
app.use('/fusion-tags', fusionTagsRoutes);
app.use('/devices', devicesRoutes);
app.use('/events', eventsRoutes);
app.use('/locations', locationsRoutes);
app.use('/auth', authRoutes);

// 404 handler
app.use((req, res) => {
  res.status(404).json({
    error: 'Route not found',
    path: req.originalUrl
  });
});

// error handler
app.use((err, req, res, next) => {
  console.error(err.stack);
  res.status(err.status || 500).json({
    error: err.message || 'Internal Server Error',
    ...(process.env.NODE_ENV === 'development' && { stack: err.stack })
  });
});

const PORT = process.env.PORT || 3000;
const HOST = process.env.HOST || '0.0.0.0';
//localhost
const server = app.listen(PORT, HOST, () => {
  console.log('\x1b[36m╔══════════════════════════════════════╗\x1b[0m');
  console.log('\x1b[36m║   Digital Twin Backend – Ready        ║\x1b[0m');
  console.log(`\x1b[36m║   http://${HOST}:${PORT}                   ║\x1b[0m`);
  console.log(`\x1b[36m║   Env: ${(process.env.NODE_ENV || 'development').padEnd(29)}║\x1b[0m`);
  console.log('\x1b[36m╚══════════════════════════════════════╝\x1b[0m');
});

server.on('error', (err) => {
  if (err.code === 'EADDRINUSE') {
    console.error(`Port ${PORT} is already in use. Please stop the other process or use a different port.`);
    process.exit(1);
  } else {
    throw err;
  }
});

export default app;
