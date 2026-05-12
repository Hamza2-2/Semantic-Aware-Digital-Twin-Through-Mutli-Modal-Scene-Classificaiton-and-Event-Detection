// IP geolocation lookup helper

import axios from 'axios';

// extract client ip from request
export const getClientIp = (req) => {

  const forwardedFor = req.headers['x-forwarded-for'];
  if (forwardedFor) {

    return forwardedFor.split(',')[0].trim();
  }


  const realIp = req.headers['x-real-ip'];
  if (realIp) {
    return realIp.trim();
  }


  return req.connection?.remoteAddress ||
         req.socket?.remoteAddress ||
         req.ip ||
         '127.0.0.1';
};

// lookup location from ip address
export const getLocationFromIp = async (ipAddress) => {

  if (isPrivateIp(ipAddress)) {
    return {
      ip: ipAddress,
      latitude: 0,
      longitude: 0,
      city: 'Local',
      region: 'Local Network',
      country: 'Local',
      accuracy: 'unknown',
      source: 'ip',
      isLocal: true
    };
  }


  try {
    const response = await axios.get(
      `http://ipapi.co/${ipAddress}/json/`,
      { timeout: 5000 }
    );
    const data = response.data;

    if (data.latitude && data.longitude) {
      return {
        ip: ipAddress,
        latitude: parseFloat(data.latitude),
        longitude: parseFloat(data.longitude),
        city: data.city || 'Unknown',
        region: data.region || 'Unknown',
        country: data.country_name || 'Unknown',
        accuracy: 'city_level',
        source: 'ip',
        service: 'ipapi.co'
      };
    }
  } catch (error) {
    console.log(`[Geolocation] ipapi.co failed: ${error.message}`);
  }


  try {
    const response = await axios.get(
      `http://ip-api.com/json/${ipAddress}`,
      { timeout: 5000 }
    );
    const data = response.data;

    if (data.status === 'success') {
      return {
        ip: ipAddress,
        latitude: parseFloat(data.lat),
        longitude: parseFloat(data.lon),
        city: data.city || 'Unknown',
        region: data.regionName || 'Unknown',
        country: data.country || 'Unknown',
        accuracy: 'city_level',
        source: 'ip',
        service: 'ip-api.com'
      };
    }
  } catch (error) {
    console.log(`[Geolocation] ip-api.com failed: ${error.message}`);
  }


  try {
    const response = await axios.get(
      `https://ipinfo.io/${ipAddress}/json`,
      { timeout: 5000 }
    );
    const data = response.data;

    if (data.loc) {
      const [lat, lon] = data.loc.split(',').map(parseFloat);
      return {
        ip: ipAddress,
        latitude: lat,
        longitude: lon,
        city: data.city || 'Unknown',
        region: data.region || 'Unknown',
        country: data.country || 'Unknown',
        accuracy: 'city_level',
        source: 'ip',
        service: 'ipinfo.io'
      };
    }
  } catch (error) {
    console.log(`[Geolocation] ipinfo.io failed: ${error.message}`);
  }


  return null;
};

// check if ip is local
export const isPrivateIp = (ip) => {
  if (!ip) return true;


  if (ip.startsWith('::ffff:')) {
    ip = ip.substring(7);
  }


  if (ip === '127.0.0.1' || ip === 'localhost' || ip === '::1') {
    return true;
  }


  const parts = ip.split('.').map(Number);
  if (parts.length === 4) {

    if (parts[0] === 10) return true;

    if (parts[0] === 172 && parts[1] >= 16 && parts[1] <= 31) return true;

    if (parts[0] === 192 && parts[1] === 168) return true;
  }

  return false;
};

// format location for saving
export const formatLocationForDb = (location) => {
  if (!location) {
    return {
      type: 'Point',
      coordinates: [0, 0],
      accuracy: 'unknown',
      city: 'Unknown',
      region: 'Unknown',
      country: 'Unknown',
      ipAddress: null,
      source: 'ip'
    };
  }

  return {
    type: 'Point',
    coordinates: [location.longitude, location.latitude],
    accuracy: location.accuracy || 'city_level',
    city: location.city || 'Unknown',
    region: location.region || 'Unknown',
    country: location.country || 'Unknown',
    ipAddress: location.ip || null,
    source: location.source || 'ip'
  };
};

export const getLocationFromRequest = async (req) => {
  const clientIp = getClientIp(req);
  console.log(`[Geolocation] Getting location for IP: ${clientIp}`);

  const location = await getLocationFromIp(clientIp);
  return formatLocationForDb(location);
};

export default {
  getClientIp,
  getLocationFromIp,
  isPrivateIp,
  formatLocationForDb,
  getLocationFromRequest
};
