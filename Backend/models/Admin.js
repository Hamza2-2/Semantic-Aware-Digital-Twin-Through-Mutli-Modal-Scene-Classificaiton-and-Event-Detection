// Admin user model with password hashing
import mongoose from 'mongoose';
import crypto from 'crypto';

const adminSchema = new mongoose.Schema({
  username: {
    type: String,
    required: [true, 'Username is required'],
    unique: true,
    trim: true,
    minlength: 3
  },
  password: {
    type: String,
    required: [true, 'Password is required']
  },
  role: {
    type: String,
    enum: ['admin', 'first_responder'],
    default: 'first_responder'                                              
  },
  adminKey: {
    type: String,
    default: null
  }
}, {
  timestamps: true,
  collection: 'admins'
});

// hash password before save
adminSchema.pre('save', function (next) {
  if (!this.isModified('password')) return next();
  const salt = crypto.randomBytes(16).toString('hex');
  const hash = crypto.pbkdf2Sync(this.password, salt, 100000, 64, 'sha512').toString('hex');
  this.password = `${salt}:${hash}`;
  next();
});

// check password match
adminSchema.methods.comparePassword = function (candidatePassword) {
  const [salt, hash] = this.password.split(':');
  const candidateHash = crypto.pbkdf2Sync(candidatePassword, salt, 100000, 64, 'sha512').toString('hex');
  return hash === candidateHash;
};

const Admin = mongoose.model('Admin', adminSchema);

// create default admin if missing
Admin.seedAdmin = async function () {
  const existing = await this.findOne({ username: 'admin' });
  if (!existing) {
    const salt = crypto.randomBytes(16).toString('hex');
    const keyHash = crypto.pbkdf2Sync('1212', salt, 100000, 64, 'sha512').toString('hex');
    await this.create({
      username: 'admin',
      password: '1234',
      role: 'admin',
      adminKey: `${salt}:${keyHash}`
    });
    console.log('Default admin seeded (admin / 1234)');
  }
};

export default Admin;
