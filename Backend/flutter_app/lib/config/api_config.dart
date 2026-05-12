// file header note




class ApiConfig {
  
  
  static const String baseUrl = 'http://localhost:3000';

  
  

  
  
  

  
  static const String inferenceUrl = 'http://localhost:5000';

  
  static String get health => '$baseUrl/health';
  static String get api => '$baseUrl/api';

  
  static String get mediaUpload => '$baseUrl/media/upload';
  static String get mediaList => '$baseUrl/media';
  static String mediaById(String id) => '$baseUrl/media/$id';

  
  static String get videoUpload => '$baseUrl/video/upload';
  static String get videoList => '$baseUrl/video';
  static String videoById(String id) => '$baseUrl/video/$id';
  static String videoTags(String id) => '$baseUrl/video/$id/tags';

  
  static String get tagsList => '$baseUrl/tags';
  static String tagById(String id) => '$baseUrl/tags/$id';
  static String get tagsCreate => '$baseUrl/tags';

  
  static String get historyAll => '$baseUrl/history';
  static String historyByMedia(String mediaId) => '$baseUrl/history/$mediaId';
  static String get historyAudio => '$baseUrl/history/audio';
  static String get historyVideo => '$baseUrl/history/video';
  static String get historyFusion => '$baseUrl/history/fusion';

  
  static String get predictVideo => '$inferenceUrl/predict/video';
  static String get predictAudio => '$inferenceUrl/predict/audio';
  static String get predictMultimodal => '$inferenceUrl/predict/multimodal';

  
  static const Duration connectionTimeout = Duration(seconds: 30);
  static const Duration receiveTimeout = Duration(seconds: 120);
}
