// MongoDB connection setup
import mongoose from 'mongoose';

// connect to mongodb
const connectDB = async () => {
  try {

    if (!process.env.MONGODB_URI) {
      throw new Error('MONGODB_URI is not defined in .env file');
    }


    const options = {};



    if (process.env.MONGODB_URI.includes('mongodb+srv://')) {

      options.serverSelectionTimeoutMS = 5000;
    }

    const conn = await mongoose.connect(process.env.MONGODB_URI, options);

    console.log(`\x1b[32m✔ MongoDB:\x1b[0m ${conn.connection.host}/${conn.connection.name}`);
  } catch (error) {
    console.error(`\x1b[31m✖ MongoDB connection failed:\x1b[0m ${error.message}`);
    console.error('  → Is mongod running?  MONGODB_URI set in .env?');
  }
};

export default connectDB;
