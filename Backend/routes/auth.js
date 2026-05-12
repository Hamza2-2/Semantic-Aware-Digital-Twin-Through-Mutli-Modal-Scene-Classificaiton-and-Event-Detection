// Login and password reset routes
import express from 'express';
import jwt from 'jsonwebtoken';
import crypto from 'crypto';
import Admin from '../models/Admin.js';
import { authenticate } from '../middleware/auth.js';

const router = express.Router();

const JWT_SECRET = process.env.JWT_SECRET || 'mvats-secret-key';

// create default admin if missing
Admin.seedAdmin().catch(err => console.error('Admin seed error:', err.message));

router.post('/login', async (req, res) => {
  try {
    const { username, password } = req.body;
    if (!username || !password) {
      return res.status(400).json({ error: 'Username and password are required' });
    }

    const admin = await Admin.findOne({ username: username.trim().toLowerCase() });
    if (!admin || !admin.comparePassword(password)) {
      return res.status(401).json({ error: 'Invalid credentials' });
    }

    const token = jwt.sign(
      { id: admin._id, username: admin.username, role: admin.role },
      JWT_SECRET,
      { expiresIn: '24h' }
    );

    res.json({
      token,
      user: { id: admin._id, username: admin.username, role: admin.role }
    });
  } catch (error) {
    res.status(500).json({ error: 'Login failed' });
  }
});

// reset password with admin key
router.put('/reset-password', async (req, res) => {
  try {
    const { username, newPassword, adminKey } = req.body;
    if (!username || !newPassword || !adminKey) {
      return res.status(400).json({ error: 'Username, new password, and admin key are required' });
    }

    const admin = await Admin.findOne({ username: username.trim().toLowerCase() });
    if (!admin) {
      return res.status(404).json({ error: 'User not found' });
    }

    if (!admin.adminKey) {
      return res.status(403).json({ error: 'Admin key not configured' });
    }

    const [salt, hash] = admin.adminKey.split(':');
    const candidateHash = crypto.pbkdf2Sync(adminKey, salt, 100000, 64, 'sha512').toString('hex');
    if (hash !== candidateHash) {
      return res.status(403).json({ error: 'Invalid admin key' });
    }

    admin.password = newPassword;
    await admin.save();
    res.json({ message: 'Password reset successfully' });
  } catch (error) {
    res.status(500).json({ error: 'Password reset failed' });
  }
});

router.get('/me', authenticate, async (req, res) => {
  try {
    const admin = await Admin.findById(req.user.id).select('-password');
    if (!admin) {
      return res.status(404).json({ error: 'User not found' });
    }
    res.json(admin);
  } catch (error) {
    res.status(500).json({ error: 'Failed to fetch user' });
  }
});

export default router;
