# file header note
import os
import json
import subprocess
import torch
import torch.nn as nn
import torchvision.models.video as video_models
import numpy as np
import cv2
from flask import Flask, request, jsonify
from flask_cors import CORS
import tempfile
import librosa
from pathlib import Path
import requests
from urllib.parse import urlparse, urlunparse

try:
    import sounddevice as sd
    import soundfile as sf
    SOUNDDEVICE_AVAILABLE = True
except ImportError:
    SOUNDDEVICE_AVAILABLE = False
    print("[Hardware] sounddevice not installed - local mic recording disabled. "
          "Install with: pip install sounddevice")

                                
try:
    from event_taxonomy import (
        SCENE_EVENT_MAP, 
        get_events_for_scene, 
        filter_events_by_scene,
        get_event_severity,
        get_highest_severity_event,
        detect_audio_events,
        ALL_EVENT_TYPES
    )
    EVENT_TAXONOMY_AVAILABLE = True
    print("[EventDetection] Event taxonomy loaded successfully")
except ImportError as e:
    print(f"[EventDetection] Event taxonomy not available: {e}")
    EVENT_TAXONOMY_AVAILABLE = False
                                                                              
    SCENE_EVENT_MAP = {
        "airport": ["explosion", "riot", "fire_alarm", "evacuation"],
        "bus": ["accident", "fire", "explosion", "riot"],
        "metro": ["explosion", "fire_alarm", "evacuation", "riot"],
        "metro_station": ["explosion", "fire_alarm", "riot", "evacuation"],
        "park": ["riot", "fire", "accident", "fight"],
        "public_square": ["riot", "explosion", "fight", "fire"],
        "shopping_mall": ["riot", "fire_alarm", "explosion", "fight"],
        "street_pedestrian": ["accident", "fight", "riot", "explosion"],
        "street_traffic": ["accident", "explosion", "fire", "vehicle_crash"],
        "tram": ["accident", "fire", "explosion", "sudden_brake"]
    }
                               
    _FALLBACK_EVENT_SEVERITY = {
        "explosion": 5, "fire": 5, "fire_alarm": 4, "riot": 4,
        "accident": 4, "vehicle_crash": 4, "evacuation": 3, "fight": 3, "sudden_brake": 2
    }
    def get_events_for_scene(sc):
        return SCENE_EVENT_MAP.get(sc.lower().strip(), [])
    def get_event_severity(ev):
        return _FALLBACK_EVENT_SEVERITY.get(ev, 3)

try:
    from avslowfast_event_detector import create_event_detector, AVSlowFastEventDetector
    AVSLOWFAST_AVAILABLE = True
    print("[EventDetection] AVSlowFast detector available")
except ImportError as e:
    print(f"[EventDetection] AVSlowFast not available: {e}")
    AVSLOWFAST_AVAILABLE = False

                                                              
try:
    import imageio_ffmpeg
    FFMPEG_PATH = imageio_ffmpeg.get_ffmpeg_exe()
    print(f"Using ffmpeg: {FFMPEG_PATH}")
except ImportError:
    FFMPEG_PATH = 'ffmpeg'                           
    print("imageio_ffmpeg not found, using system ffmpeg")

app = Flask(__name__)
CORS(app)

BASE_DIR = Path(__file__).resolve().parent
MODEL_PATH = BASE_DIR / "assets" / "models" / "best_model_94pct.pth"
AUDIO_MODEL_PATH = BASE_DIR / "assets" / "models" / "best_model_audio.pth"
PASST_MODEL_PATH = BASE_DIR / "assets" / "models" / "best_model_passt.pth"

# 'cnn14' or 'passt'
current_audio_model_type = 'cnn14'
passt_model = None

#   PaSST
try:
    from hear21passt.base import get_basic_model, get_model_passt
    PASST_AVAILABLE = True
    print("[AudioModel] PaSST (hear21passt) available")
except ImportError as e:
    PASST_AVAILABLE = False
    print(f"[AudioModel] PaSST not available: {e}")

class VideoClassifier(nn.Module):
    def __init__(self, num_classes=10, model_type='r2plus1d_18', dropout=0.5):
        super(VideoClassifier, self).__init__()
        
        if model_type == 'r2plus1d_18':
            self.base = video_models.r2plus1d_18(pretrained=False)
        
        num_features = self.base.fc.in_features
        self.base.fc = nn.Sequential(
            nn.Dropout(dropout),
            nn.Linear(num_features, num_classes)
        )
    
    def forward(self, x):
        return self.base(x)
 
class CNN14(nn.Module):
    #CNN14 model  
    def __init__(self, num_classes=10, dropout=0.5):
        super(CNN14, self).__init__()
        
        self.conv_block1 = nn.Sequential(
            nn.Conv2d(1, 64, kernel_size=3, padding=1),
            nn.BatchNorm2d(64),
            nn.ReLU(),
            nn.Conv2d(64, 64, kernel_size=3, padding=1),
            nn.BatchNorm2d(64),
            nn.ReLU(),
            nn.MaxPool2d(2, 2),
            nn.Dropout2d(0.1)
        )
        
        self.conv_block2 = nn.Sequential(
            nn.Conv2d(64, 128, kernel_size=3, padding=1),
            nn.BatchNorm2d(128),
            nn.ReLU(),
            nn.Conv2d(128, 128, kernel_size=3, padding=1),
            nn.BatchNorm2d(128),
            nn.ReLU(),
            nn.MaxPool2d(2, 2),
            nn.Dropout2d(0.2)
        )
        
        self.conv_block3 = nn.Sequential(
            nn.Conv2d(128, 256, kernel_size=3, padding=1),
            nn.BatchNorm2d(256),
            nn.ReLU(),
            nn.Conv2d(256, 256, kernel_size=3, padding=1),
            nn.BatchNorm2d(256),
            nn.ReLU(),
            nn.MaxPool2d(2, 2),
            nn.Dropout2d(0.3)
        )
        
        self.conv_block4 = nn.Sequential(
            nn.Conv2d(256, 512, kernel_size=3, padding=1),
            nn.BatchNorm2d(512),
            nn.ReLU(),
            nn.Conv2d(512, 512, kernel_size=3, padding=1),
            nn.BatchNorm2d(512),
            nn.ReLU(),
            nn.MaxPool2d(2, 2),
            nn.Dropout2d(0.4)
        )
        
        self.global_pool = nn.AdaptiveAvgPool2d((1, 1))
        
        self.fc = nn.Sequential(
            nn.Dropout(dropout),
            nn.Linear(512, 512),
            nn.ReLU(),
            nn.Dropout(dropout),
            nn.Linear(512, num_classes)
        )
    
    def forward(self, x):
        x = self.conv_block1(x)
        x = self.conv_block2(x)
        x = self.conv_block3(x)
        x = self.conv_block4(x)
        x = self.global_pool(x)
        x = x.flatten(1)
        x = self.fc(x)
        return x
 
class PaSSTClassifier(nn.Module):
 
    def __init__(self, num_classes=10, s_patchout_t=0, s_patchout_f=0):
        super().__init__()
        if not PASST_AVAILABLE:
            raise ImportError("hear21passt is not installed. Install with: pip install hear21passt")
        self.passt = get_basic_model(mode="logits")
 
        self.passt.net = get_model_passt(
            arch="passt_s_kd_p16_128_ap486",
            n_classes=num_classes,
            s_patchout_t=s_patchout_t,
            s_patchout_f=s_patchout_f,
        )

    def forward(self, x):
        return self.passt(x)
 
class AudioVideoSeparator:
 
    def __init__(
        self,
        num_frames=16,
        frame_size=224,
        sample_rate=44100,
        n_mels=128,
        hop_length=512,
        audio_duration=10.0,
        device='cpu'
    ):
        self.num_frames = num_frames
        self.frame_size = frame_size
        self.sample_rate = sample_rate
        self.n_mels = n_mels
        self.hop_length = hop_length
        self.audio_duration = audio_duration
        self.device = device
    
    def extract_from_file(self, video_path):
 
        video_path = Path(video_path)
        
                              
        video_tensor = self.extract_video(video_path)
        
                       
        audio_tensor = self.extract_audio(video_path)
        
        return video_tensor, audio_tensor
    
    def extract_video(self, video_path):

        frames = extract_frames_from_video(str(video_path), num_frames=self.num_frames)
        frames = frames.astype(np.float32) / 255.0
        video_tensor = torch.from_numpy(frames).permute(3, 0, 1, 2).float()
        video_tensor = video_tensor.unsqueeze(0)
        return video_tensor.to(self.device)
    
    def extract_audio(self, video_path):
        """
        Extract and preprocess audio from video file
        
        Returns:
            audio_tensor: [1, 1, n_mels, time] mel-spectrogram tensor
        """
                                     
        with tempfile.NamedTemporaryFile(suffix='.wav', delete=False) as tmp_audio:
            tmp_audio_path = tmp_audio.name
        
        try:
                                                                     
            cmd = [
                FFMPEG_PATH,
                '-y',             
                '-i', str(video_path),
                '-vn',            
                '-acodec', 'pcm_s16le',
                '-ar', str(self.sample_rate),
                '-ac', '1',        
                tmp_audio_path
            ]
            
            result = subprocess.run(cmd, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
            
            if result.returncode != 0:
                print(f"FFmpeg warning: {result.stderr.decode()}")
            
                                             
            if not os.path.exists(tmp_audio_path) or os.path.getsize(tmp_audio_path) == 0:
                print("No audio track found, returning silent audio tensor")
                                            
                return self._get_silent_audio_tensor()
            
                                      
            audio, sr = librosa.load(tmp_audio_path, sr=self.sample_rate, duration=self.audio_duration)
            
                                   
            target_length = int(self.sample_rate * self.audio_duration)
            if len(audio) < target_length:
                audio = np.pad(audio, (0, target_length - len(audio)))
            else:
                audio = audio[:target_length]
            
                                        
            mel_spec = librosa.feature.melspectrogram(
                y=audio,
                sr=self.sample_rate,
                n_mels=self.n_mels,
                n_fft=2048,
                hop_length=self.hop_length,
                fmax=self.sample_rate // 2
            )
            
                                 
            mel_spec_db = librosa.power_to_db(mel_spec, ref=np.max)
            
                                          
            mean = mel_spec_db.mean()
            std = mel_spec_db.std()
            mel_spec_norm = (mel_spec_db - mean) / (std + 1e-8)
            
                                                     
            audio_tensor = torch.from_numpy(mel_spec_norm).unsqueeze(0).unsqueeze(0).float()
            
            return audio_tensor.to(self.device)
            
        finally:
                                     
            if os.path.exists(tmp_audio_path):
                os.remove(tmp_audio_path)
    
    def _get_silent_audio_tensor(self):
       
                                                              
        time_frames = int((self.sample_rate * self.audio_duration) / self.hop_length) + 1
        silent_spec = np.zeros((self.n_mels, time_frames), dtype=np.float32)
        audio_tensor = torch.from_numpy(silent_spec).unsqueeze(0).unsqueeze(0).float()
        return audio_tensor.to(self.device)


    def extract_audio_raw_for_passt(self, video_path, target_sr=32000, duration=10.0):
        """
        Extract audio from video file as raw waveform at 32kHz for PaSST.

        Returns:
            torch.Tensor: [1, T] raw waveform at 32kHz (T = target_sr * duration)
        """
        with tempfile.NamedTemporaryFile(suffix='.wav', delete=False) as tmp_audio:
            tmp_audio_path = tmp_audio.name

        try:
            cmd = [
                FFMPEG_PATH,
                '-y',
                '-i', str(video_path),
                '-vn',
                '-acodec', 'pcm_s16le',
                '-ar', str(target_sr),
                '-ac', '1',
                tmp_audio_path
            ]
            result = subprocess.run(cmd, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
            if result.returncode != 0:
                print(f'[PaSST] FFmpeg warning: {result.stderr.decode()}')

            if not os.path.exists(tmp_audio_path) or os.path.getsize(tmp_audio_path) == 0:
                print('[PaSST] No audio track found, returning silent waveform')
                target_length = int(target_sr * duration)
                silent = np.zeros(target_length, dtype=np.float32)
                return torch.from_numpy(silent).unsqueeze(0).float().to(self.device)

            audio = load_and_preprocess_audio_passt(tmp_audio_path, sr=target_sr, duration=duration)
            return torch.from_numpy(audio).unsqueeze(0).float().to(self.device)

        finally:
            if os.path.exists(tmp_audio_path):
                os.remove(tmp_audio_path)


def weighted_fusion(video_logits, audio_logits, video_weight=0.5, audio_weight=0.5):
 
    video_probs = torch.softmax(video_logits, dim=1)
    audio_probs = torch.softmax(audio_logits, dim=1)
    fused_probs = video_weight * video_probs + audio_weight * audio_probs
    print(f"  [Fusion] Weighted: video_w={video_weight}, audio_w={audio_weight}")
    return torch.log(fused_probs + 1e-8)


def confidence_based_fusion(video_logits, audio_logits):
 
    video_probs = torch.softmax(video_logits, dim=1)
    audio_probs = torch.softmax(audio_logits, dim=1)
    
    video_conf = video_probs.max(dim=1, keepdim=True)[0]
    audio_conf = audio_probs.max(dim=1, keepdim=True)[0]
    
    total_conf = video_conf + audio_conf
    v_weight = video_conf / (total_conf + 1e-8)
    a_weight = audio_conf / (total_conf + 1e-8)
    
                                                                  
                                                     
    fused_probs = v_weight * video_probs + a_weight * audio_probs
    
    print(f"  [Fusion] Video weight: {v_weight.item():.4f}, Audio weight: {a_weight.item():.4f}")
    print(f"  [Fusion] Video conf: {video_conf.item():.4f}, Audio conf: {audio_conf.item():.4f}")
    
                                                             
    return torch.log(fused_probs + 1e-8)


def max_confidence_fusion(video_logits, audio_logits):
 
    video_probs = torch.softmax(video_logits, dim=1)
    audio_probs = torch.softmax(audio_logits, dim=1)
    
    video_conf = video_probs.max(dim=1, keepdim=True)[0]
    audio_conf = audio_probs.max(dim=1, keepdim=True)[0]
    
    winner = 'video' if video_conf.item() > audio_conf.item() else 'audio'
    print(f"  [Fusion] Max-confidence winner: {winner} (video={video_conf.item():.4f}, audio={audio_conf.item():.4f})")
    
    mask = (video_conf > audio_conf).float()
    fused_probs = mask * video_probs + (1 - mask) * audio_probs
    return torch.log(fused_probs + 1e-8)


def average_probs_fusion(video_logits, audio_logits):
    """Average the probability distributions"""
    video_probs = torch.softmax(video_logits, dim=1)
    audio_probs = torch.softmax(audio_logits, dim=1)
    
    avg_probs = (video_probs + audio_probs) / 2
    print(f"  [Fusion] Average probs fusion applied")
    return avg_probs


def predict_fusion(video_path, fusion_method='confidence', audio_model_type=None):
 
    global model, audio_model, passt_model, device, current_audio_model_type

    separator = AudioVideoSeparator(
        num_frames=16,
        frame_size=224,
        sample_rate=44100,
        n_mels=128,
        audio_duration=10.0,
        device=device
    )

 
    video_tensor = separator.extract_video(video_path)
 
    resolved_model_type = (audio_model_type or current_audio_model_type or 'cnn14').lower()
    if resolved_model_type == 'passt':
        if passt_model is None:
            load_passt_model()
        use_passt = PASST_AVAILABLE and passt_model is not None
    else:
        if audio_model is None:
            load_audio_model()
        use_passt = False

    if use_passt:
        audio_tensor = separator.extract_audio_raw_for_passt(video_path, target_sr=32000, duration=10.0)
        active_audio_model = passt_model
        audio_model_name = 'passt'
    else:
        audio_tensor = separator.extract_audio(video_path)
        active_audio_model = audio_model
        audio_model_name = 'cnn14'

    model.eval()
    active_audio_model.eval()

    with torch.no_grad():
        video_logits = model(video_tensor)
        audio_logits = active_audio_model(audio_tensor)
        
                                           
        print(f"\n{'='*60}")
        print(f"[Fusion Debug] Method: {fusion_method}")
        print(f"[Fusion Debug] Video logits range: [{video_logits.min().item():.4f}, {video_logits.max().item():.4f}]")
        print(f"[Fusion Debug] Audio logits range: [{audio_logits.min().item():.4f}, {audio_logits.max().item():.4f}]")
        v_probs_dbg = torch.softmax(video_logits, dim=1)
        a_probs_dbg = torch.softmax(audio_logits, dim=1)
        v_top_conf, v_top_idx = v_probs_dbg.max(1)
        a_top_conf, a_top_idx = a_probs_dbg.max(1)
        print(f"[Fusion Debug] Video top prediction: {CLASS_NAMES[v_top_idx.item()]} ({v_top_conf.item():.4f})")
        print(f"[Fusion Debug] Audio top prediction: {CLASS_NAMES[a_top_idx.item()]} ({a_top_conf.item():.4f})")


        FUSION_AUDIO_THRESHOLD = 0.90 if use_passt else 0.10
        _a_soft_check = torch.softmax(audio_logits, dim=1)
        _a_peak_conf = _a_soft_check.max().item()
        if _a_peak_conf < FUSION_AUDIO_THRESHOLD:
            _scale = _a_peak_conf / FUSION_AUDIO_THRESHOLD
            _n_cls = len(CLASS_NAMES)
            _uniform = torch.ones_like(_a_soft_check) / _n_cls
            _audio_attenuated = _scale * _a_soft_check + (1.0 - _scale) * _uniform
            audio_logits = torch.log(_audio_attenuated + 1e-8)
            print(f"[Fusion Debug] Audio attenuation ({('passt' if use_passt else 'cnn14')}): "
                  f"peak {_a_peak_conf:.4f} < {FUSION_AUDIO_THRESHOLD} → scaled by {_scale:.4f}")


        video_logits_for_fusion = video_logits  # default: no boost
        _bus_idx = CLASS_NAMES.index('bus') if 'bus' in CLASS_NAMES else -1
        _metro_indices = [i for i, n in enumerate(CLASS_NAMES)
                          if 'metro' in n.lower()]
        _tram_idx = CLASS_NAMES.index('tram') if 'tram' in CLASS_NAMES else -1

        if _bus_idx >= 0:
            _v_soft = torch.softmax(video_logits, dim=1)
            _a_soft = torch.softmax(audio_logits, dim=1)
            _v_bus = _v_soft[0][_bus_idx].item()

            _boost = 0.0
            if _v_bus >= 0.30:  
                if any(_a_soft[0][mi].item() > 0.05 for mi in _metro_indices):
                    _boost += 0.05
                if _tram_idx >= 0 and _a_soft[0][_tram_idx].item() > 0.05:
                    _boost += 0.02

            if _boost > 0:
                _vp = _v_soft[0].cpu().numpy().copy()
                _vp[_bus_idx] = min(1.0, _vp[_bus_idx] + _boost)
                _vp /= _vp.sum()          # renormalise to sum=1
 
                video_logits_for_fusion = torch.log(
                    torch.tensor(_vp, dtype=torch.float32).unsqueeze(0).to(device) + 1e-8
                )
                print(f"[Fusion Debug] Bus boost applied: {_v_bus:.4f} → {_vp[_bus_idx]:.4f}")

        if fusion_method == 'weighted':
            fused_logits = weighted_fusion(video_logits_for_fusion, audio_logits)
            fused_probs = torch.softmax(fused_logits, dim=1)
        elif fusion_method == 'confidence':
            fused_logits = confidence_based_fusion(video_logits_for_fusion, audio_logits)
            fused_probs = torch.softmax(fused_logits, dim=1)
        elif fusion_method == 'max':
            fused_logits = max_confidence_fusion(video_logits_for_fusion, audio_logits)
            fused_probs = torch.softmax(fused_logits, dim=1)
        elif fusion_method == 'average':
            fused_probs = average_probs_fusion(video_logits_for_fusion, audio_logits)
        else:
            fused_logits = confidence_based_fusion(video_logits_for_fusion, audio_logits)
            fused_probs = torch.softmax(fused_logits, dim=1)
        
                                      

        video_probs = torch.softmax(video_logits_for_fusion, dim=1)
        audio_probs = torch.softmax(audio_logits, dim=1)

        fused_confidence, fused_pred_idx = fused_probs.max(1)
        video_confidence, video_pred_idx = video_probs.max(1)
        audio_confidence, audio_pred_idx = audio_probs.max(1)

        fused_class = CLASS_NAMES[fused_pred_idx.item()]
        video_class = CLASS_NAMES[video_pred_idx.item()]
        audio_class = CLASS_NAMES[audio_pred_idx.item()]

        print(f"[Fusion Summary] Video(boosted): {video_class} ({video_confidence.item():.4f}) | "
              f"Audio(attenuated): {audio_class} ({audio_confidence.item():.4f}) | "
              f"Fused: {fused_class} ({fused_confidence.item():.4f})")

 
        top_probs, top_indices = torch.topk(fused_probs, 5)
        top_predictions = [
            {
                'class': CLASS_NAMES[idx.item()],
                'confidence': prob.item()
            }
            for prob, idx in zip(top_probs[0], top_indices[0])
        ]
        
                             
        video_top_probs, video_top_indices = torch.topk(video_probs, 5)
        video_top_predictions = [
            {
                'class': CLASS_NAMES[idx.item()],
                'confidence': prob.item()
            }
            for prob, idx in zip(video_top_probs[0], video_top_indices[0])
        ]
        
                             
        audio_top_probs, audio_top_indices = torch.topk(audio_probs, 5)
        audio_top_predictions = [
            {
                'class': CLASS_NAMES[idx.item()],
                'confidence': prob.item()
            }
            for prob, idx in zip(audio_top_probs[0], audio_top_indices[0])
        ]
        
                                                                    
        agreement_score = (video_probs[0] * audio_probs[0]).sum().item()
        modality_agreement = video_class == audio_class
        
        result = {
            'type': 'fusion',
            'fusionMethod': fusion_method,
                                               
            'predictedClass': fused_class,
            'confidence': fused_confidence.item(),
            'topPredictions': top_predictions,
                                
            'videoResult': {
                'predictedClass': video_class,
                'confidence': video_confidence.item(),
                'topPredictions': video_top_predictions
            },
                                  
            'audioResult': {
                'predictedClass': audio_class,
                'confidence': audio_confidence.item(),
                'topPredictions': audio_top_predictions,
                'modelType': audio_model_name
            },
                             
            'fusionAnalysis': {
                'modalityAgreement': modality_agreement,
                'agreementScore': round(agreement_score, 4),
                'videoWeight': round(video_confidence.item() / (video_confidence.item() + audio_confidence.item() + 1e-8), 4),
                'audioWeight': round(audio_confidence.item() / (video_confidence.item() + audio_confidence.item() + 1e-8), 4),
            },
                                     
            'allProbabilities': {
                'fused': {CLASS_NAMES[i]: round(fused_probs[0][i].item(), 4) for i in range(len(CLASS_NAMES))},
                'video': {CLASS_NAMES[i]: round(video_probs[0][i].item(), 4) for i in range(len(CLASS_NAMES))},
                'audio': {CLASS_NAMES[i]: round(audio_probs[0][i].item(), 4) for i in range(len(CLASS_NAMES))}
            }
        }
        
        return result


CLASS_NAMES = [
    'airport',
    'bus',
    'metro(underground)',
    'metro_station(underground)',
    'park',
    'public_square',
    'shopping_mall',
    'street_pedestrian',
    'street_traffic',
    'tram'
]

model = None
audio_model = None
device = None
event_detector = None


def get_event_detector(confidence_threshold=0.005):
 
    global event_detector

    if not AVSLOWFAST_AVAILABLE:
        return None

    if event_detector is None:
        try:
            event_detector = AVSlowFastEventDetector(
                device='cuda' if torch.cuda.is_available() else 'cpu',
                confidence_threshold=confidence_threshold,
            )
        except Exception as e:
            print(f"[EventDetection] Failed to initialize AVSlowFast detector: {e}")
            event_detector = None
    else:
                                                            
        event_detector.confidence_threshold = confidence_threshold

    return event_detector

def load_model():
    global model, device
    
    device = torch.device('cpu')
    print(f"Using device: {device}")
    
    model = VideoClassifier(
        num_classes=10,
        model_type='r2plus1d_18',
        dropout=0.5
    )
    
    if os.path.exists(MODEL_PATH):
        try:
            checkpoint = torch.load(MODEL_PATH, map_location=device)
            
            if 'model_state_dict' in checkpoint:
                model.load_state_dict(checkpoint['model_state_dict'])
            else:
                model.load_state_dict(checkpoint)
            
            print(f"Model loaded from {MODEL_PATH}")
        except Exception as e:
            print(f"WARNING: Failed to load model: {e}")
            print("Using randomly initialized model for demo purposes.")
    else:
        print(f"WARNING: Model file not found at {MODEL_PATH}")
        print("Using randomly initialized model for demo purposes.")
    
    model.to(device)
    model.eval()
    return model


def load_audio_model():
 
    global audio_model, device
    
    if device is None:
        device = torch.device('cpu')
    
    audio_model = CNN14(num_classes=10, dropout=0.5)
    
    if os.path.exists(AUDIO_MODEL_PATH):
        try:
            checkpoint = torch.load(AUDIO_MODEL_PATH, map_location=device, weights_only=False)
            
            if 'model_state_dict' in checkpoint:
                audio_model.load_state_dict(checkpoint['model_state_dict'])
                print(f"Audio model loaded from {AUDIO_MODEL_PATH}")
                if 'val_acc' in checkpoint:
                    print(f"  - Validation accuracy: {checkpoint['val_acc']:.2f}%")
                if 'epoch' in checkpoint:
                    print(f"  - Trained epochs: {checkpoint['epoch']+1}")
            else:
                audio_model.load_state_dict(checkpoint)
                print(f"Audio model loaded from {AUDIO_MODEL_PATH}")
        except Exception as e:
            print(f"WARNING: Failed to load audio model: {e}")
            print("Using randomly initialized audio model for demo purposes.")
    else:
        print(f"WARNING: Audio model file not found at {AUDIO_MODEL_PATH}")
        print("Using randomly initialized audio model for demo purposes.")
    
    audio_model.to(device)
    audio_model.eval()
    return audio_model


def load_passt_model():
 
    global passt_model, device

    if not PASST_AVAILABLE:
        print("ERROR: PaSST is not available. Install with: pip install hear21passt")
        return None

    if device is None:
        device = torch.device('cpu')

    try:
        passt_model = PaSSTClassifier(num_classes=10, s_patchout_t=0, s_patchout_f=0)

        if os.path.exists(PASST_MODEL_PATH):
            checkpoint = torch.load(PASST_MODEL_PATH, map_location=device, weights_only=False)

            if 'model_state_dict' in checkpoint:
                passt_model.load_state_dict(checkpoint['model_state_dict'])
                print(f"PaSST model loaded from {PASST_MODEL_PATH}")
                if 'val_acc' in checkpoint:
                    print(f"  - Validation accuracy: {checkpoint['val_acc']:.2f}%")
                if 'epoch' in checkpoint:
                    print(f"  - Trained epochs: {checkpoint['epoch']+1}")
            else:
                passt_model.load_state_dict(checkpoint)
                print(f"PaSST model loaded from {PASST_MODEL_PATH}")
        else:
            print(f"WARNING: PaSST model file not found at {PASST_MODEL_PATH}")
            return None

        passt_model.to(device)
        passt_model.eval()
        return passt_model
    except Exception as e:
        print(f"ERROR: Failed to load PaSST model: {e}")
        import traceback
        traceback.print_exc()
        return None


def switch_audio_model(model_type):
 
    global current_audio_model_type, audio_model, passt_model

    model_type = model_type.lower().strip()

    if model_type not in ['cnn14', 'passt']:
        return {'success': False, 'error': f"Invalid model type: {model_type}. Use 'cnn14' or 'passt'"}

    if model_type == 'passt' and not PASST_AVAILABLE:
        return {'success': False, 'error': "PaSST is not available. Install with: pip install hear21passt"}

    # Load the requested model if not already loaded
    if model_type == 'cnn14':
        if audio_model is None:
            load_audio_model()
    else:  # passt
        if passt_model is None:
            result = load_passt_model()
            if result is None:
                return {'success': False, 'error': "Failed to load PaSST model"}

    current_audio_model_type = model_type
    print(f"[AudioModel] Switched to {model_type.upper()}")

    return {
        'success': True,
        'currentModel': current_audio_model_type,
        'message': f"Audio model switched to {model_type.upper()}"
    }


def load_and_preprocess_audio_passt(audio_path, sr=32000, duration=10.0):

    print(f"  Loading audio for PaSST: {audio_path}")
    audio, _ = librosa.load(audio_path, sr=sr, duration=duration, mono=True)
    target_length = int(sr * duration)

    if len(audio) < target_length:
        audio = np.pad(audio, (0, target_length - len(audio)))
    elif len(audio) > target_length:
        audio = audio[:target_length]

    print(f"  Waveform: {audio.shape} @ {sr} Hz")
    return audio.astype(np.float32)


def normalize_stream_url(stream_url):
 
    normalized = (stream_url or '').strip()
    if not normalized:
        return normalized

    if not normalized.startswith(('http://', 'https://', 'rtsp://')):
        normalized = f'http://{normalized}'

    parsed = urlparse(normalized)
    path = parsed.path or ''
    if (not path or path == '/') and parsed.scheme != 'rtsp' and parsed.port in (4747, 8080):
        path = '/video'

    return urlunparse(parsed._replace(path=path))


def open_stream_capture(stream_url):
    """Open a stream with a small backend fallback matrix."""
    normalized_stream_url = normalize_stream_url(stream_url)
    attempted = []

    backend_candidates = []
    ffmpeg_backend = getattr(cv2, 'CAP_FFMPEG', None)
    if ffmpeg_backend is not None:
        backend_candidates.append(ffmpeg_backend)
    backend_candidates.append(None)

    for backend in backend_candidates:
        try:
            cap = (
                cv2.VideoCapture(normalized_stream_url, backend)
                if backend is not None
                else cv2.VideoCapture(normalized_stream_url)
            )
        except Exception as exc:
            attempted.append(f'{backend}: {exc}')
            continue

        if cap is not None and cap.isOpened():
            return cap, normalized_stream_url

        attempted.append(str(backend))
        if cap is not None:
            cap.release()

    raise ValueError(
        f"Cannot connect to stream: {normalized_stream_url}. Attempted backends: {', '.join(attempted)}"
    )


def capture_stream_to_temp_video(stream_url, duration_seconds, suffix='.mp4'):
 
    cap, normalized_stream_url = open_stream_capture(stream_url)

    fps = cap.get(cv2.CAP_PROP_FPS)
    if fps <= 0 or np.isnan(fps):
        fps = 15

    first_ok, first_frame = cap.read()
    if not first_ok or first_frame is None:
        cap.release()
        raise ValueError(f'Failed to read from stream: {normalized_stream_url}')

    height, width = first_frame.shape[:2]
    if width <= 0 or height <= 0:
        cap.release()
        raise ValueError(f'Invalid frame size from stream: {normalized_stream_url}')

    with tempfile.NamedTemporaryFile(delete=False, suffix=suffix) as tmp:
        tmp_path = tmp.name

    fourcc = cv2.VideoWriter_fourcc(*'mp4v')
    out = cv2.VideoWriter(tmp_path, fourcc, fps, (width, height))

    frames_to_capture = max(1, int(round(max(duration_seconds, 1) * fps)))
    captured = 0

    try:
        out.write(first_frame)
        captured = 1

        while captured < frames_to_capture:
            ret, frame = cap.read()
            if not ret or frame is None:
                break
            out.write(frame)
            captured += 1
    finally:
        cap.release()
        out.release()

    if captured == 0:
        if os.path.exists(tmp_path):
            os.remove(tmp_path)
        raise ValueError(f'No frames captured from stream: {normalized_stream_url}')

    return tmp_path, normalized_stream_url, captured, fps


                                                                              
                               
                                                                              

def load_and_preprocess_audio(audio_path, sr=44100, duration=10.0, n_mels=128):

    print(f"Loading audio file: {audio_path}")
    
                     
    audio, loaded_sr = librosa.load(audio_path, sr=sr, duration=duration)
    print(f"  Loaded: {len(audio)} samples at {loaded_sr} Hz")
    
                                          
    target_length = int(sr * duration)
    if len(audio) < target_length:
                                     
        audio = np.pad(audio, (0, target_length - len(audio)))
        print(f"  Padded to {target_length} samples ({duration}s)")
    else:
                              
        audio = audio[:target_length]
        print(f"  Truncated to {target_length} samples ({duration}s)")
    
                                
    mel_spec = librosa.feature.melspectrogram(
        y=audio,
        sr=sr,
        n_mels=n_mels,
        n_fft=2048,
        hop_length=512,
        fmax=sr // 2
    )
    
                         
    mel_spec_db = librosa.power_to_db(mel_spec, ref=np.max)
    
    print(f"  Mel-spectrogram shape: {mel_spec_db.shape}")
    
    return mel_spec_db


def normalize_spectrogram(mel_spec):
    """Normalize mel-spectrogram (same as training)"""
    mean = mel_spec.mean()
    std = mel_spec.std()
    mel_spec_norm = (mel_spec - mean) / (std + 1e-8)
    return mel_spec_norm


def predict_audio(audio_path):

    global audio_model, passt_model, device, current_audio_model_type

    # Use PaSST model 
    if current_audio_model_type == 'passt' and PASST_AVAILABLE:
        return predict_audio_passt(audio_path)

    # Otherwise use CNN14
    return predict_audio_cnn14(audio_path)


def predict_audio_cnn14(audio_path):
    
    global audio_model, device

 
    if audio_model is None:
        load_audio_model()

    if audio_model is None:
        raise RuntimeError("Failed to load CNN14 audio model")

     
    mel_spec = load_and_preprocess_audio(
        audio_path,
        sr=44100,
        duration=10.0,
        n_mels=128
    )

    
    mel_spec = normalize_spectrogram(mel_spec)

    # Convert to tensor [1, 1, 128, T]
    mel_spec_tensor = torch.from_numpy(mel_spec).unsqueeze(0).unsqueeze(0).float()
    mel_spec_tensor = mel_spec_tensor.to(device)

    # predict
    audio_model.eval()
    with torch.no_grad():
        outputs = audio_model(mel_spec_tensor)
        probs = torch.softmax(outputs, dim=1)
        confidence, pred_idx = probs.max(1)

    predicted_class = CLASS_NAMES[pred_idx.item()]
    confidence_value = confidence.item()

    #  top-5 predictions
    top_probs, top_indices = torch.topk(probs, 5)
    top_predictions = [
        {
            'class': CLASS_NAMES[idx.item()],
            'confidence': prob.item()
        }
        for prob, idx in zip(top_probs[0], top_indices[0])
    ]

    return {
        'predictedClass': predicted_class,
        'confidence': confidence_value,
        'topPredictions': top_predictions,
        'type': 'audio',
        'modelType': 'cnn14'
    }


def predict_audio_passt(audio_path):
 
    global passt_model, device

    if not PASST_AVAILABLE:
        raise RuntimeError("PaSST is not available. Install with: pip install hear21passt")

    # Ensure model is loaded
    if passt_model is None:
        result = load_passt_model()
        if result is None:
            raise RuntimeError("Failed to load PaSST model")

 
    waveform = load_and_preprocess_audio_passt(audio_path, sr=32000, duration=10.0)

    # Convert to tensor [1, samples]
    x = torch.from_numpy(waveform).unsqueeze(0).float().to(device)

    # Predict
    passt_model.eval()
    with torch.no_grad():
        logits = passt_model(x)
        probs = torch.softmax(logits, dim=1)
        confidence, pred_idx = probs.max(1)

    predicted_class = CLASS_NAMES[pred_idx.item()]
    confidence_value = confidence.item()

    # Get top-5 predictions
    top_probs, top_indices = torch.topk(probs, 5)
    top_predictions = [
        {
            'class': CLASS_NAMES[idx.item()],
            'confidence': prob.item()
        }
        for prob, idx in zip(top_probs[0], top_indices[0])
    ]

    return {
        'predictedClass': predicted_class,
        'confidence': confidence_value,
        'topPredictions': top_predictions,
        'type': 'audio',
        'modelType': 'passt'
    }


def get_reliable_frame_count(video_path):

    try:

        candidates = [
            FFMPEG_PATH.replace('ffmpeg.exe', 'ffprobe.exe'),
            FFMPEG_PATH.replace('ffmpeg', 'ffprobe'),
            os.path.join(os.path.dirname(FFMPEG_PATH), 'ffprobe.exe'),
            os.path.join(os.path.dirname(FFMPEG_PATH), 'ffprobe'),
            'ffprobe',   # system PATH
        ]
        ffprobe = next((p for p in candidates if os.path.exists(p)), None)

        if ffprobe:
            cmd = [
                ffprobe, '-v', 'error', '-select_streams', 'v:0',
                '-show_entries', 'stream=nb_frames,r_frame_rate,duration',
                '-print_format', 'json', str(video_path)
            ]
            result = subprocess.run(cmd, capture_output=True, text=True, timeout=15)
            data = json.loads(result.stdout)
            streams = data.get('streams', [])
            if streams:
                stream = streams[0]
                raw = stream.get('nb_frames', 'N/A')
                if raw not in ('N/A', '', None):
                    n = int(raw)
                    if n > 0:
                        return n
                fps_str = stream.get('r_frame_rate', '0/1')
                duration_s = float(stream.get('duration', 0) or 0)
                num, den = fps_str.split('/')
                fps = float(num) / float(den) if float(den) > 0 else 0
                if fps > 0 and duration_s > 0:
                    return int(fps * duration_s)
    except Exception:
        pass


    try:
        cap_tmp = cv2.VideoCapture(str(video_path))
        fps = cap_tmp.get(cv2.CAP_PROP_FPS)
        if fps > 0:
            cap_tmp.set(cv2.CAP_PROP_POS_AVI_RATIO, 1.0)
            duration_ms = cap_tmp.get(cv2.CAP_PROP_POS_MSEC)
            cap_tmp.release()
            if duration_ms > 0:
                return int((duration_ms / 1000.0) * fps)
        cap_tmp.release()
    except Exception:
        pass

    return None  



def extract_frames_from_video(video_path, num_frames=16):
    cap = cv2.VideoCapture(video_path)
    
    if not cap.isOpened():
        raise ValueError(f"Cannot open video: {video_path}")


    total_frames = get_reliable_frame_count(video_path)
    if not total_frames or total_frames <= 0:
        total_frames = int(cap.get(cv2.CAP_PROP_FRAME_COUNT))

    frame_indices = np.linspace(0, max(0, total_frames - 1), num_frames).astype(int)
    
    frames = []
    for idx in frame_indices:
        cap.set(cv2.CAP_PROP_POS_FRAMES, idx)
        ret, frame = cap.read()
        
        if ret:
            rgb = cv2.cvtColor(frame, cv2.COLOR_BGR2RGB)
            rgb = cv2.resize(rgb, (224, 224))
            frames.append(rgb)
        else:
            if len(frames) > 0:
                frames.append(frames[-1].copy())
    
    cap.release()
    
    while len(frames) < num_frames:
        frames.append(frames[-1].copy() if frames else np.zeros((224, 224, 3), dtype=np.uint8))
    
    return np.array(frames[:num_frames])

def predict_video(video_path, multi_label=False):
    global model, device
    
    if multi_label:
        return predict_video_multilabel(video_path)
    
    frames = extract_frames_from_video(video_path)
    
    frames = frames.astype(np.float32) / 255.0
    frames = torch.from_numpy(frames).permute(3, 0, 1, 2).float()
    frames = frames.unsqueeze(0).to(device)
    
    with torch.no_grad():
        outputs = model(frames)
        probs = torch.softmax(outputs, dim=1)
        confidence, pred_idx = probs.max(1)
    
    predicted_class = CLASS_NAMES[pred_idx.item()]
    confidence_value = confidence.item()
    
    top_probs, top_indices = torch.topk(probs, 5)
    top_predictions = [
        {
            'class': CLASS_NAMES[idx.item()],
            'confidence': prob.item()
        }
        for prob, idx in zip(top_probs[0], top_indices[0])
    ]
    
    return {
        'predictedClass': predicted_class,
        'confidence': confidence_value,
        'topPredictions': top_predictions,
        'type': 'video'
    }


def predict_video_multilabel(video_path, segment_duration_sec=None, min_confidence=0.85):
    global model, device
    
    cap = cv2.VideoCapture(video_path)
    if not cap.isOpened():
        raise ValueError(f"Cannot open video: {video_path}")
    
    fps = cap.get(cv2.CAP_PROP_FPS)
    total_frames = int(cap.get(cv2.CAP_PROP_FRAME_COUNT))
    duration_sec = total_frames / fps if fps > 0 else 0
    
    if segment_duration_sec is None:
        if duration_sec <= 2:
            segment_duration_sec = 0.5
        elif duration_sec <= 5:
            segment_duration_sec = 1.0
        elif duration_sec <= 30:
            segment_duration_sec = 2.0
        else:
            segment_duration_sec = 3.0
    
    frames_per_segment = max(8, int(segment_duration_sec * fps)) if fps > 0 else 16
    overlap_ratio = 0.0
    step_frames = max(1, int(frames_per_segment * (1 - overlap_ratio)))
    
    segment_results = []
    detected_classes = {}
    class_occurrences = {}
    class_first_detected = {}
    class_last_detected = {}
    all_segment_classes = {}
    
    start_frame = 0
    segment_idx = 0
    
    print(f"Analyzing video: {duration_sec:.1f}s, {total_frames} frames, {fps:.1f} fps")
    print(f"Segment size: {segment_duration_sec}s ({frames_per_segment} frames), step: {step_frames} frames")
    
    while start_frame < total_frames:
        end_frame = min(start_frame + frames_per_segment, total_frames)
        
        if end_frame - start_frame < 8:
            break
        
        frame_indices = np.linspace(start_frame, end_frame - 1, 16).astype(int)
        
        frames = []
        for idx in frame_indices:
            cap.set(cv2.CAP_PROP_POS_FRAMES, idx)
            ret, frame = cap.read()
            if ret:
                rgb = cv2.cvtColor(frame, cv2.COLOR_BGR2RGB)
                rgb = cv2.resize(rgb, (224, 224))
                frames.append(rgb)
            elif len(frames) > 0:
                frames.append(frames[-1].copy())
        
        while len(frames) < 16:
            if frames:
                frames.append(frames[-1].copy())
            else:
                frames.append(np.zeros((224, 224, 3), dtype=np.uint8))
        
        frames_array = np.array(frames[:16]).astype(np.float32) / 255.0
        tensor = torch.from_numpy(frames_array).permute(3, 0, 1, 2).float()
        tensor = tensor.unsqueeze(0).to(device)
        
        with torch.no_grad():
            outputs = model(tensor)
            probs = torch.softmax(outputs, dim=1)
            confidence, pred_idx = probs.max(1)
        
        predicted_class = CLASS_NAMES[pred_idx.item()]
        conf_value = confidence.item()
        
        top_probs, top_indices = torch.topk(probs, 3)
        top_3 = [
            {'class': CLASS_NAMES[i.item()], 'confidence': round(p.item(), 4)}
            for p, i in zip(top_probs[0], top_indices[0])
        ]
        
        start_time = start_frame / fps if fps > 0 else 0
        end_time = end_frame / fps if fps > 0 else 0
        
        segment_results.append({
            'segment': segment_idx,
            'startTime': round(start_time, 2),
            'endTime': round(end_time, 2),
            'predictedClass': predicted_class,
            'confidence': round(conf_value, 4),
            'top3': top_3
        })
        
        print(f"  Segment {segment_idx}: {start_time:.1f}s - {end_time:.1f}s => {predicted_class} ({conf_value*100:.1f}%)")
        
        if predicted_class not in detected_classes or conf_value > detected_classes[predicted_class]:
            detected_classes[predicted_class] = conf_value
        
        if predicted_class not in class_first_detected:
            class_first_detected[predicted_class] = start_time
        class_last_detected[predicted_class] = end_time
        
        class_occurrences[predicted_class] = class_occurrences.get(predicted_class, 0) + 1
        
        for item in top_3:
            cls_name = item['class']
            cls_conf = item['confidence']
            if cls_conf >= 0.85 or cls_name == predicted_class:
                if cls_name not in all_segment_classes or cls_conf > all_segment_classes[cls_name]['confidence']:
                    all_segment_classes[cls_name] = {
                        'confidence': cls_conf,
                        'firstDetectedAt': start_time
                    }
                                                                                                     
                                                                                                                 
                if cls_name == predicted_class:
                    if cls_name not in class_first_detected:
                        class_first_detected[cls_name] = start_time
                if cls_name not in class_last_detected or end_time > class_last_detected[cls_name]:
                    class_last_detected[cls_name] = end_time
                if cls_name not in class_occurrences:
                    class_occurrences[cls_name] = 0
        
        start_frame += step_frames
        segment_idx += 1
    
    cap.release()
    
    for cls_name, info in all_segment_classes.items():
        if cls_name not in detected_classes:
            detected_classes[cls_name] = info['confidence']
    
    sorted_classes = sorted(detected_classes.items(), key=lambda x: x[1], reverse=True)
    
    significant_classes = [(cls, conf) for cls, conf in sorted_classes if conf >= min_confidence]
    
    print(f"Total segments analyzed: {len(segment_results)}")
    print(f"All detected classes: {sorted_classes}")
    print(f"Significant classes (>= {min_confidence*100}%): {significant_classes}")
    
    detected_classes_list = [
        {
            'class': cls,
            'maxConfidence': round(conf, 4),
            'occurrences': class_occurrences.get(cls, 0),
            'percentageOfVideo': round(class_occurrences.get(cls, 0) / max(1, len(segment_results)) * 100, 1),
                                                               
                                                                             
            'firstDetectedAt': round(
                class_first_detected.get(
                    cls,
                    all_segment_classes.get(cls, {}).get('firstDetectedAt', 0)
                ), 2),
            'lastDetectedAt': round(class_last_detected.get(cls, 0), 2)
        }
        for cls, conf in sorted_classes
    ]
    
    primary_class = sorted_classes[0][0] if sorted_classes else 'unknown'
    primary_confidence = sorted_classes[0][1] if sorted_classes else 0
    
    secondary_classes = [
        {'class': cls, 'maxConfidence': round(conf, 4)}
        for cls, conf in significant_classes[1:4]
    ]
    
    return {
        'type': 'video_multilabel',
        'isMultilabel': len(significant_classes) > 1,
        'durationSeconds': round(duration_sec, 2),
        'totalSegments': len(segment_results),
        'segmentDuration': segment_duration_sec,
        'predictedClass': primary_class,
        'confidence': round(primary_confidence, 4),
        'detectedClasses': detected_classes_list,
        'secondaryClasses': secondary_classes,
        'topPredictions': [
            {'class': cls, 'confidence': round(conf, 4)}
            for cls, conf in sorted_classes[:5]
        ],
        'segmentPredictions': segment_results,
        'summary': f"Detected {len(significant_classes)} scene(s): {', '.join([c[0] for c in significant_classes])}"
    }


@app.route('/health', methods=['GET'])
def health_check():
    return jsonify({
        'status': 'healthy',
        'model_loaded': model is not None,
        'device': str(device)
    })


@app.route('/audio/model', methods=['GET'])
def get_audio_model_status():
 
    return jsonify({
        'currentModel': current_audio_model_type,
        'cnn14Available': True,
        'passtAvailable': PASST_AVAILABLE,
        'cnn14Loaded': audio_model is not None,
        'passtLoaded': passt_model is not None
    })


@app.route('/audio/model/switch', methods=['POST'])
def switch_audio_model_endpoint():
 
    data = request.get_json() or {}
    model_type = data.get('model_type', data.get('modelType', 'cnn14'))

    result = switch_audio_model(model_type)

    if result['success']:
        return jsonify(result)
    else:
        return jsonify(result), 400

@app.route('/predict/video', methods=['POST'])
def predict_video_endpoint():
    if 'video' not in request.files:
        return jsonify({'error': 'No video file provided'}), 400
    
    video_file = request.files['video']
    
    multi_label = request.form.get('multi_label', 'false').lower() == 'true'
    
    with tempfile.NamedTemporaryFile(delete=False, suffix='.mp4') as tmp:
        video_file.save(tmp.name)
        tmp_path = tmp.name
    
    try:
        result = predict_video(tmp_path, multi_label=multi_label)
        return jsonify(result)
    except Exception as e:
        import traceback
        traceback.print_exc()
        return jsonify({'error': str(e)}), 500
    finally:
        if os.path.exists(tmp_path):
            os.remove(tmp_path)

@app.route('/predict/audio', methods=['POST'])
def predict_audio_endpoint():
    global audio_model, passt_model, current_audio_model_type

    if 'audio' not in request.files:
        return jsonify({'error': 'No audio file provided'}), 400

 
    req_audio_model = request.form.get('audio_model', '').lower().strip()
    if req_audio_model not in ('cnn14', 'passt'):
        req_audio_model = current_audio_model_type   

    print(f"[Audio Predict] Using model: {req_audio_model} (requested: {request.form.get('audio_model', 'none')})")

 
    if req_audio_model == 'passt':
        if not PASST_AVAILABLE:
            return jsonify({'error': 'PaSST model not available'}), 400
        if passt_model is None:
            load_passt_model()
    else:
        if audio_model is None:
            load_audio_model()

    audio_file = request.files['audio']

    ext = os.path.splitext(audio_file.filename)[1] if audio_file.filename else '.wav'
    if not ext:
        ext = '.wav'

    with tempfile.NamedTemporaryFile(delete=False, suffix=ext) as tmp:
        audio_file.save(tmp.name)
        tmp_path = tmp.name

    try:
 
        if req_audio_model == 'passt' and PASST_AVAILABLE:
            result = predict_audio_passt(tmp_path)
        else:
            result = predict_audio_cnn14(tmp_path)
        return jsonify(result)
    except Exception as e:
        import traceback
        traceback.print_exc()
        return jsonify({'error': str(e)}), 500
    finally:
        if os.path.exists(tmp_path):
            os.remove(tmp_path)

@app.route('/predict/multimodal', methods=['POST'])
def predict_multimodal_endpoint():
    global audio_model
    
    video_result = None
    audio_result = None
    
                               
    if 'video' in request.files:
        video_file = request.files['video']
        with tempfile.NamedTemporaryFile(delete=False, suffix='.mp4') as tmp:
            video_file.save(tmp.name)
            try:
                video_result = predict_video(tmp.name)
            finally:
                if os.path.exists(tmp.name):
                    os.remove(tmp.name)
    
                               
    if 'audio' in request.files:
                                        
        if audio_model is None:
            load_audio_model()
        
        audio_file = request.files['audio']
        ext = os.path.splitext(audio_file.filename)[1] if audio_file.filename else '.wav'
        if not ext:
            ext = '.wav'
        
        with tempfile.NamedTemporaryFile(delete=False, suffix=ext) as tmp:
            audio_file.save(tmp.name)
            try:
                audio_result = predict_audio(tmp.name)
            finally:
                if os.path.exists(tmp.name):
                    os.remove(tmp.name)
    
                                                   
    if video_result and audio_result:
                                                                      
        video_confidence = video_result.get('confidence', 0)
        audio_confidence = audio_result.get('confidence', 0)
        
                              
        total_weight = video_confidence + audio_confidence
        if total_weight > 0:
            video_weight = video_confidence / total_weight
            audio_weight = audio_confidence / total_weight
        else:
            video_weight = audio_weight = 0.5
        
                                                           
        if video_confidence >= audio_confidence:
            predicted_class = video_result.get('predictedClass')
            final_confidence = video_confidence * 0.6 + audio_confidence * 0.4
        else:
            predicted_class = audio_result.get('predictedClass')
            final_confidence = audio_confidence * 0.6 + video_confidence * 0.4
        
                                 
        video_preds = {p['class']: p['confidence'] for p in video_result.get('topPredictions', [])}
        audio_preds = {p['class']: p['confidence'] for p in audio_result.get('topPredictions', [])}
        
        fused_preds = {}
        all_classes = set(video_preds.keys()) | set(audio_preds.keys())
        for cls in all_classes:
            v_conf = video_preds.get(cls, 0)
            a_conf = audio_preds.get(cls, 0)
            fused_preds[cls] = v_conf * video_weight + a_conf * audio_weight
        
                            
        sorted_preds = sorted(fused_preds.items(), key=lambda x: x[1], reverse=True)[:5]
        top_predictions = [{'class': cls, 'confidence': conf} for cls, conf in sorted_preds]
        
        return jsonify({
            'predictedClass': predicted_class,
            'confidence': final_confidence,
            'topPredictions': top_predictions,
            'type': 'multimodal',
            'videoResult': video_result,
            'audioResult': audio_result,
            'fusionMethod': 'late_fusion_weighted'
        })
    
                              
    if video_result:
        video_result['type'] = 'multimodal'
        return jsonify(video_result)
    
                              
    if audio_result:
        audio_result['type'] = 'multimodal'
        return jsonify(audio_result)
    
    return jsonify({
        'error': 'No video or audio file provided',
        'type': 'multimodal'
    }), 400


@app.route('/predict/fusion', methods=['POST'])
def predict_fusion_endpoint():
 
    global audio_model, passt_model, current_audio_model_type

    if 'video' not in request.files:
        return jsonify({'error': 'No video file provided'}), 400

    video_file = request.files['video']

    fusion_method = request.form.get('fusion_method', 'confidence').lower()
    valid_methods = ['weighted', 'confidence', 'max', 'average']
    if fusion_method not in valid_methods:
        fusion_method = 'confidence'

 
    req_audio_model = request.form.get('audio_model', '').lower().strip()
    if req_audio_model not in ('cnn14', 'passt'):
        req_audio_model = None  # fall back to server global

    # Load the appropriate audio model
    _effective_audio = req_audio_model or current_audio_model_type
    if _effective_audio == 'passt' and PASST_AVAILABLE:
        if passt_model is None:
            load_passt_model()
    else:
        if audio_model is None:
            load_audio_model()
    
                            
    with tempfile.NamedTemporaryFile(delete=False, suffix='.mp4') as tmp:
        video_file.save(tmp.name)
        tmp_path = tmp.name
    
    try:
        print(f"\n{'='*50}")
        print(f"FUSION PREDICTION: {video_file.filename}")
        print(f"Fusion Method: {fusion_method}")
        print(f"{'='*50}")
        
        result = predict_fusion(tmp_path, fusion_method=fusion_method, audio_model_type=req_audio_model)
        
        print(f"\n🎯 Fused Prediction: {result['predictedClass']} ({result['confidence']*100:.1f}%)")
        print(f"📹 Video Prediction: {result['videoResult']['predictedClass']} ({result['videoResult']['confidence']*100:.1f}%)")
        print(f"🔊 Audio Prediction: {result['audioResult']['predictedClass']} ({result['audioResult']['confidence']*100:.1f}%)")
        print(f"Agreement: {'Yes' if result['fusionAnalysis']['modalityAgreement'] else 'No'}")
        print(f"{'='*50}\n")
        
        return jsonify(result)
        
    except Exception as e:
        import traceback
        traceback.print_exc()
        return jsonify({'error': str(e)}), 500
    finally:
        if os.path.exists(tmp_path):
            os.remove(tmp_path)


@app.route('/predict/fusion/stream', methods=['POST'])
def predict_fusion_stream_endpoint():
 
    global model, audio_model, passt_model, device, current_audio_model_type

    data = request.get_json()
    if not data or 'video_url' not in data:
        return jsonify({'error': 'No video_url provided'}), 400

    video_url = data['video_url']
    audio_url = data.get('audio_url') or normalize_audio_stream_url(video_url)
    duration = int(data.get('duration', 10))
    duration = min(max(5, duration), 30)
    fusion_method = data.get('fusion_method', 'confidence').lower()
    valid_methods = ['weighted', 'confidence', 'max', 'average']
    if fusion_method not in valid_methods:
        fusion_method = 'confidence'

    req_audio_model = (data.get('audio_model', '') or '').lower().strip()
    if req_audio_model not in ('cnn14', 'passt'):
        req_audio_model = None

    if model is None:
        load_model()
    _effective_audio_stream = req_audio_model or current_audio_model_type
    if _effective_audio_stream == 'passt' and PASST_AVAILABLE:
        if passt_model is None:
            load_passt_model()
    else:
        if audio_model is None:
            load_audio_model()

    audio_path = None
    try:
        print(f"\n{'='*50}")
        print(f"FUSION STREAM PREDICTION")
        print(f"Video URL: {video_url}")
        print(f"Audio URL: {audio_url}")
        print(f"Duration: {duration}s, Method: {fusion_method}")
        print(f"{'='*50}")

                                                
        frames, total_captured = extract_frames_from_stream(video_url, duration)
        frames = frames.astype(np.float32) / 255.0
        video_tensor = torch.from_numpy(frames).permute(3, 0, 1, 2).float()
        video_tensor = video_tensor.unsqueeze(0).to(device)

                                         
        audio_path = extract_audio_from_stream(audio_url, duration)

                                                    
 
        use_passt_stream = (
            (_effective_audio_stream == 'passt')
            and PASST_AVAILABLE and passt_model is not None
        )
        if use_passt_stream:
            raw_waveform = load_and_preprocess_audio_passt(audio_path, sr=32000, duration=10.0)
            audio_tensor = torch.from_numpy(raw_waveform).unsqueeze(0).float().to(device)
            active_audio_model = passt_model
            stream_audio_model_name = 'passt'
        else:
            mel_spec = load_and_preprocess_audio(audio_path, sr=44100, duration=10.0, n_mels=128)
            mel_spec = normalize_spectrogram(mel_spec)
            audio_tensor = torch.from_numpy(mel_spec).unsqueeze(0).unsqueeze(0).float().to(device)
            active_audio_model = audio_model
            stream_audio_model_name = 'cnn14'

        model.eval()
        active_audio_model.eval()

        with torch.no_grad():
            video_logits = model(video_tensor)
            audio_logits = active_audio_model(audio_tensor)

 
            FUSION_AUDIO_THRESHOLD_STREAM = 0.90 if use_passt_stream else 0.10
            _a_soft_chk = torch.softmax(audio_logits, dim=1)
            _a_peak = _a_soft_chk.max().item()
            if _a_peak < FUSION_AUDIO_THRESHOLD_STREAM:
                _scale = _a_peak / FUSION_AUDIO_THRESHOLD_STREAM
                _n_cls = len(CLASS_NAMES)
                _uniform = torch.ones_like(_a_soft_chk) / _n_cls
                _a_att = _scale * _a_soft_chk + (1.0 - _scale) * _uniform
                audio_logits = torch.log(_a_att + 1e-8)
                print(f"[FusionStream] Audio attenuation ({('passt' if use_passt_stream else 'cnn14')}): "
                      f"peak {_a_peak:.4f} < {FUSION_AUDIO_THRESHOLD_STREAM}")


            video_logits_for_fusion = video_logits
            _bus_idx = CLASS_NAMES.index('bus') if 'bus' in CLASS_NAMES else -1
            _metro_indices = [i for i, n in enumerate(CLASS_NAMES) if 'metro' in n.lower()]
            _tram_idx = CLASS_NAMES.index('tram') if 'tram' in CLASS_NAMES else -1
            if _bus_idx >= 0:
                _v_soft = torch.softmax(video_logits, dim=1)
                _a_soft = torch.softmax(audio_logits, dim=1)
                _v_bus = _v_soft[0][_bus_idx].item()
                _boost = 0.0
                if _v_bus >= 0.30:
                    if any(_a_soft[0][mi].item() > 0.05 for mi in _metro_indices):
                        _boost += 0.05
                    if _tram_idx >= 0 and _a_soft[0][_tram_idx].item() > 0.05:
                        _boost += 0.02
                if _boost > 0:
                    _vp = _v_soft[0].cpu().numpy().copy()
                    _vp[_bus_idx] = min(1.0, _vp[_bus_idx] + _boost)
                    _vp /= _vp.sum()
                    video_logits_for_fusion = torch.log(
                        torch.tensor(_vp, dtype=torch.float32).unsqueeze(0).to(device) + 1e-8
                    )
                    print(f"[FusionStream] Bus boost applied: {_v_bus:.4f} → {_vp[_bus_idx]:.4f}")

            if fusion_method == 'weighted':
                fused_logits = weighted_fusion(video_logits_for_fusion, audio_logits)
                fused_probs = torch.softmax(fused_logits, dim=1)
            elif fusion_method == 'max':
                fused_logits = max_confidence_fusion(video_logits_for_fusion, audio_logits)
                fused_probs = torch.softmax(fused_logits, dim=1)
            elif fusion_method == 'average':
                fused_probs = average_probs_fusion(video_logits_for_fusion, audio_logits)
            else:
                fused_logits = confidence_based_fusion(video_logits_for_fusion, audio_logits)
                fused_probs = torch.softmax(fused_logits, dim=1)

            video_probs = torch.softmax(video_logits_for_fusion, dim=1)
            audio_probs = torch.softmax(audio_logits, dim=1)

            fused_confidence, fused_pred_idx = fused_probs.max(1)
            video_confidence, video_pred_idx = video_probs.max(1)
            audio_confidence, audio_pred_idx = audio_probs.max(1)

            fused_class = CLASS_NAMES[fused_pred_idx.item()]
            video_class = CLASS_NAMES[video_pred_idx.item()]
            audio_class = CLASS_NAMES[audio_pred_idx.item()]

            top_probs, top_indices = torch.topk(fused_probs, 5)
            top_predictions = [
                {'class': CLASS_NAMES[idx.item()], 'confidence': prob.item()}
                for prob, idx in zip(top_probs[0], top_indices[0])
            ]

            video_top_probs, video_top_indices = torch.topk(video_probs, 5)
            video_top_predictions = [
                {'class': CLASS_NAMES[idx.item()], 'confidence': prob.item()}
                for prob, idx in zip(video_top_probs[0], video_top_indices[0])
            ]

            audio_top_probs, audio_top_indices = torch.topk(audio_probs, 5)
            audio_top_predictions = [
                {'class': CLASS_NAMES[idx.item()], 'confidence': prob.item()}
                for prob, idx in zip(audio_top_probs[0], audio_top_indices[0])
            ]

            agreement_score = (video_probs[0] * audio_probs[0]).sum().item()

            result = {
                'type': 'fusion_stream',
                'fusionMethod': fusion_method,
                'predictedClass': fused_class,
                'confidence': fused_confidence.item(),
                'topPredictions': top_predictions,
                'videoResult': {
                    'predictedClass': video_class,
                    'confidence': video_confidence.item(),
                    'topPredictions': video_top_predictions,
                    'streamUrl': video_url,
                },
                'audioResult': {
                    'predictedClass': audio_class,
                    'confidence': audio_confidence.item(),
                    'topPredictions': audio_top_predictions,
                    'streamUrl': audio_url,
                    'modelType': stream_audio_model_name,
                },
                'fusionAnalysis': {
                    'modalityAgreement': video_class == audio_class,
                    'agreementScore': round(agreement_score, 4),
                    'videoWeight': round(video_confidence.item() / (video_confidence.item() + audio_confidence.item() + 1e-8), 4),
                    'audioWeight': round(audio_confidence.item() / (video_confidence.item() + audio_confidence.item() + 1e-8), 4),
                },
                'streamInfo': {
                    'videoUrl': video_url,
                    'audioUrl': audio_url,
                    'duration': duration,
                    'framesAnalyzed': total_captured,
                },
            }

        print(f"\n  Fused: {fused_class} ({fused_confidence.item()*100:.1f}%)")
        print(f"  Video: {video_class} ({video_confidence.item()*100:.1f}%)")
        print(f"  Audio: {audio_class} ({audio_confidence.item()*100:.1f}%)")
        print(f"  Agreement: {video_class == audio_class}")
        print(f"{'='*50}\n")

        return jsonify(result)

    except Exception as e:
        import traceback
        traceback.print_exc()
        return jsonify({'error': str(e)}), 500
    finally:
        if audio_path and os.path.exists(audio_path):
            os.remove(audio_path)


@app.route('/classes', methods=['GET'])
def get_classes():
    return jsonify({'classes': CLASS_NAMES})


def extract_frames_from_stream(stream_url, duration_seconds=5, num_frames=16):
    cap, stream_url = open_stream_capture(stream_url)
    
    fps = cap.get(cv2.CAP_PROP_FPS)
    if fps <= 0:
        fps = 30
    
    total_frames_to_capture = int(duration_seconds * fps)
    frame_indices = np.linspace(0, total_frames_to_capture - 1, num_frames).astype(int)
    
    frames = []
    captured_frames = []
    frame_count = 0
    
    print(f"Capturing {duration_seconds}s from stream {stream_url} at ~{fps} fps...")
    
    while frame_count < total_frames_to_capture:
        ret, frame = cap.read()
        
        if not ret:
            print(f"Warning: Stream read failed at frame {frame_count}")
            if frame_count > 0:
                break
            else:
                raise ValueError("Failed to read from stream")
        
        captured_frames.append(frame)
        frame_count += 1
    
    cap.release()
    
    print(f"Captured {len(captured_frames)} frames")
    
    for idx in frame_indices:
        if idx < len(captured_frames):
            frame = captured_frames[idx]
            rgb = cv2.cvtColor(frame, cv2.COLOR_BGR2RGB)
            rgb = cv2.resize(rgb, (224, 224))
            frames.append(rgb)
        elif len(frames) > 0:
            frames.append(frames[-1].copy())
    
    while len(frames) < num_frames:
        if frames:
            frames.append(frames[-1].copy())
        else:
            frames.append(np.zeros((224, 224, 3), dtype=np.uint8))
    
    return np.array(frames[:num_frames]), len(captured_frames)


def predict_stream(stream_url, duration_seconds=5, multi_label=False):
    global model, device
    
    if multi_label:
        return predict_stream_multilabel(stream_url, duration_seconds)
    
    frames, total_captured = extract_frames_from_stream(stream_url, duration_seconds)
    
    frames = frames.astype(np.float32) / 255.0
    frames = torch.from_numpy(frames).permute(3, 0, 1, 2).float()
    frames = frames.unsqueeze(0).to(device)
    
    with torch.no_grad():
        outputs = model(frames)
        probs = torch.softmax(outputs, dim=1)
        confidence, pred_idx = probs.max(1)
    
    predicted_class = CLASS_NAMES[pred_idx.item()]
    confidence_value = confidence.item()
    
    top_probs, top_indices = torch.topk(probs, 5)
    top_predictions = [
        {
            'class': CLASS_NAMES[idx.item()],
            'confidence': prob.item()
        }
        for prob, idx in zip(top_probs[0], top_indices[0])
    ]
    
    return {
        'predictedClass': predicted_class,
        'confidence': confidence_value,
        'topPredictions': top_predictions,
        'type': 'stream',
        'streamUrl': stream_url,
        'capturedSeconds': duration_seconds,
        'framesAnalyzed': total_captured
    }


def predict_stream_multilabel(stream_url, duration_seconds=5, min_confidence=0.85):
    global model, device
    
    cap = cv2.VideoCapture(stream_url)
    if not cap.isOpened():
        raise ValueError(f"Cannot connect to stream: {stream_url}")
    
    fps = cap.get(cv2.CAP_PROP_FPS)
    if fps <= 0:
        fps = 30
    
    total_frames_to_capture = int(duration_seconds * fps)
    
    segment_duration_sec = 1.0 if duration_seconds <= 5 else 2.0
    frames_per_segment = max(8, int(segment_duration_sec * fps))
    
    all_frames = []
    frame_count = 0
    
    print(f"Capturing {duration_seconds}s from stream for multi-label analysis...")
    
    while frame_count < total_frames_to_capture:
        ret, frame = cap.read()
        if not ret:
            if frame_count > 0:
                break
            raise ValueError("Failed to read from stream")
        
        all_frames.append(frame)
        frame_count += 1
    
    cap.release()
    
    print(f"Captured {len(all_frames)} frames, analyzing in segments...")
    
    segment_results = []
    detected_classes = {}
    class_occurrences = {}
    class_first_detected = {}
    class_last_detected = {}
    
    start_frame = 0
    segment_idx = 0
    
    while start_frame < len(all_frames):
        end_frame = min(start_frame + frames_per_segment, len(all_frames))
        
        if end_frame - start_frame < 8:
            break
        
        frame_indices = np.linspace(start_frame, end_frame - 1, 16).astype(int)
        
        frames = []
        for idx in frame_indices:
            frame = all_frames[idx]
            rgb = cv2.cvtColor(frame, cv2.COLOR_BGR2RGB)
            rgb = cv2.resize(rgb, (224, 224))
            frames.append(rgb)
        
        while len(frames) < 16:
            frames.append(frames[-1].copy() if frames else np.zeros((224, 224, 3), dtype=np.uint8))
        
        frames_array = np.array(frames[:16]).astype(np.float32) / 255.0
        tensor = torch.from_numpy(frames_array).permute(3, 0, 1, 2).float()
        tensor = tensor.unsqueeze(0).to(device)
        
        with torch.no_grad():
            outputs = model(tensor)
            probs = torch.softmax(outputs, dim=1)
            confidence, pred_idx = probs.max(1)
        
        predicted_class = CLASS_NAMES[pred_idx.item()]
        conf_value = confidence.item()
        
        start_time = start_frame / fps
        end_time = end_frame / fps
        
        segment_results.append({
            'segment': segment_idx,
            'startTime': round(start_time, 2),
            'endTime': round(end_time, 2),
            'predictedClass': predicted_class,
            'confidence': round(conf_value, 4)
        })
        
        if predicted_class not in detected_classes or conf_value > detected_classes[predicted_class]:
            detected_classes[predicted_class] = conf_value
        
        if predicted_class not in class_first_detected:
            class_first_detected[predicted_class] = start_time
        class_last_detected[predicted_class] = end_time
        class_occurrences[predicted_class] = class_occurrences.get(predicted_class, 0) + 1
        
        start_frame = end_frame
        segment_idx += 1
    
    sorted_classes = sorted(detected_classes.items(), key=lambda x: x[1], reverse=True)
    significant_classes = [(cls, conf) for cls, conf in sorted_classes if conf >= min_confidence]
    
    detected_classes_list = [
        {
            'class': cls,
            'maxConfidence': round(conf, 4),
            'occurrences': class_occurrences.get(cls, 0),
            'percentageOfVideo': round(class_occurrences.get(cls, 0) / max(1, len(segment_results)) * 100, 1),
            'firstDetectedAt': round(class_first_detected.get(cls, 0), 2),
            'lastDetectedAt': round(class_last_detected.get(cls, 0), 2)
        }
        for cls, conf in sorted_classes
    ]
    
    primary_class = sorted_classes[0][0] if sorted_classes else 'unknown'
    primary_confidence = sorted_classes[0][1] if sorted_classes else 0
    
    return {
        'type': 'stream_multilabel',
        'isMultilabel': len(significant_classes) > 1,
        'streamUrl': stream_url,
        'capturedSeconds': round(len(all_frames) / fps, 2),
        'totalSegments': len(segment_results),
        'predictedClass': primary_class,
        'confidence': round(primary_confidence, 4),
        'detectedClasses': detected_classes_list,
        'topPredictions': [
            {'class': cls, 'confidence': round(conf, 4)}
            for cls, conf in sorted_classes[:5]
        ],
        'segmentPredictions': segment_results,
        'summary': f"Detected {len(significant_classes)} scene(s): {', '.join([c[0] for c in significant_classes])}"
    }


@app.route('/predict/stream', methods=['POST'])
def predict_stream_endpoint():
    data = request.get_json()
    
    if not data or 'stream_url' not in data:
        return jsonify({'error': 'No stream_url provided'}), 400
    
    stream_url = data['stream_url']
    duration_seconds = data.get('duration_seconds', 5)
    multi_label = data.get('multi_label', False)
    
    duration_seconds = min(max(1, duration_seconds), 60)
    
    try:
        result = predict_stream(stream_url, duration_seconds, multi_label)
        return jsonify(result)
    except Exception as e:
        import traceback
        traceback.print_exc()
        return jsonify({'error': str(e)}), 500


                                                                              
                        
                                                                              

def normalize_audio_stream_url(stream_url):
 
    normalized = (stream_url or '').strip()
    if not normalized:
        return normalized

    if not normalized.startswith(('http://', 'https://', 'rtsp://')):
        normalized = f'http://{normalized}'

    parsed = urlparse(normalized)
    
                                                                          
                                                                  
    if parsed.port == 4747:
        return f'http://{parsed.hostname}:{parsed.port}/audio.wav'
    
                                                                            
    if parsed.port == 8080:
        path = parsed.path or ''
        if not path or path == '/' or path == '/video':
            path = '/audio.wav'
        return urlunparse(parsed._replace(path=path))
    
                                                               
    if parsed.scheme == 'rtsp':
        return normalized
    
                                                          
    path = parsed.path or ''
    if not path or path == '/':
        path = '/video'
    return urlunparse(parsed._replace(path=path))


def get_audio_stream_candidates(stream_url):
 
    primary = normalize_audio_stream_url(stream_url)
    normalized = (stream_url or '').strip()
    if not normalized:
        return []

    if not normalized.startswith(('http://', 'https://', 'rtsp://')):
        normalized = f'http://{normalized}'

    parsed = urlparse(normalized)
    if not parsed.hostname:
        return [primary] if primary else []

    candidates = []

    def _add(url):
        if url and url not in candidates:
            candidates.append(url)

                                   
    _add(primary)

    if parsed.port == 4747:
        base_http = f'http://{parsed.hostname}:{parsed.port}'
        _add(f'{base_http}/audio.wav')
        _add(f'{base_http}/audio')
        _add(f'{base_http}/audio.opus')
        _add(f'{base_http}/video')
        _add(f'rtsp://{parsed.hostname}:{parsed.port}/video')
        return candidates

    if parsed.port == 8080:
                                                                 
        base_http = f'http://{parsed.hostname}:{parsed.port}'
        _add(f'{base_http}/audio.wav')
        _add(f'{base_http}/audio')
                                                                                              
        return candidates

    if parsed.scheme == 'rtsp':
        _add(normalized)
        return candidates

    _add(normalized)
    return candidates


def extract_audio_from_stream_once(stream_url, duration_seconds=10):
    """Extract audio from a single candidate URL."""
    import subprocess

    with tempfile.NamedTemporaryFile(delete=False, suffix='.wav') as tmp:
        audio_path = tmp.name

    ffmpeg_cmd = [
        FFMPEG_PATH,
        '-y',
    ]
    if stream_url.startswith('rtsp://'):
        ffmpeg_cmd += ['-rtsp_transport', 'tcp']
    ffmpeg_cmd += [
        '-t', str(duration_seconds),
        '-i', stream_url,
        '-vn',
        '-ar', '44100',
        '-ac', '1',
        '-acodec', 'pcm_s16le',
        audio_path
    ]

    print(f"Capturing {duration_seconds}s audio from stream: {stream_url}")

    try:
        result = subprocess.run(
            ffmpeg_cmd,
            capture_output=True,
            timeout=duration_seconds + 30,
            text=True
        )

        if not os.path.exists(audio_path) or os.path.getsize(audio_path) < 1000:
            stderr = result.stderr or ''
            if 'Error' in stderr or 'Invalid' in stderr or 'No such' in stderr or 'Connection refused' in stderr:
                raise RuntimeError(stderr[-500:] if len(stderr) > 500 else stderr)
            elif result.returncode != 0:
                raise RuntimeError(f"FFmpeg exited with code {result.returncode}. Stream may be unavailable.")
            else:
                raise RuntimeError('Audio capture produced no output. Check stream URL.')

        print(f"Audio captured to: {audio_path} ({os.path.getsize(audio_path)} bytes)")
        return audio_path
    except subprocess.TimeoutExpired:
        raise RuntimeError('Stream capture timed out')
    except FileNotFoundError:
        raise RuntimeError('FFmpeg not found. Please install FFmpeg and add to PATH.')
    except Exception:
        if os.path.exists(audio_path):
            os.remove(audio_path)
        raise


def extract_audio_from_stream(stream_url, duration_seconds=10):
 
    candidates = get_audio_stream_candidates(stream_url)
    
                                 
    parsed = urlparse(stream_url or '')
    camera_type = 'IP Webcam' if parsed.port == 8080 else ('DroidCam' if parsed.port == 4747 else 'RTSP/Custom')
    print(f"[Audio] Camera type detected: {camera_type}, trying {len(candidates)} candidate URL(s)")
    
    errors = []

    for i, candidate in enumerate(candidates):
        try:
            print(f"[Audio] Trying candidate {i+1}/{len(candidates)}: {candidate}")
            return extract_audio_from_stream_once(candidate, duration_seconds)
        except Exception as exc:
            short_err = str(exc)[:200] if len(str(exc)) > 200 else str(exc)
            errors.append(f'{candidate} -> {short_err}')
            print(f"[Audio] Candidate {i+1} failed: {short_err[:100]}")

                           
    print(f"[Audio] All {len(candidates)} candidates failed!")
    if camera_type == 'DroidCam':
        print("[Audio] TIP: DroidCam has unreliable audio. Try IP Webcam app (port 8080) instead.")
    
    summary = '; '.join(errors[-3:]) if errors else 'No candidate URLs generated.'
    raise RuntimeError(f'FFmpeg failed for all audio URL candidates ({camera_type}). Tried: {summary}')


def predict_audio_stream(stream_url, duration_seconds=10):
 
    global audio_model
    
                                    
    if audio_model is None:
        load_audio_model()
    
    audio_path = None
    try:
                                   
        audio_path = extract_audio_from_stream(stream_url, duration_seconds)
        
                        
        result = predict_audio(audio_path)
        result['streamInfo'] = {
            'url': stream_url,
            'capturedDuration': duration_seconds
        }
        return result
        
    finally:
                            
        if audio_path and os.path.exists(audio_path):
            os.remove(audio_path)


@app.route('/predict/audio/stream', methods=['POST'])
def predict_audio_stream_endpoint():
 
    global audio_model
    
    data = request.get_json()
    
    if not data or 'stream_url' not in data:
        return jsonify({'error': 'No stream_url provided'}), 400
    
    stream_url = data['stream_url']
    duration_seconds = data.get('duration_seconds', 10)
    
                                             
    duration_seconds = min(max(5, duration_seconds), 30)
    
                                    
    if audio_model is None:
        load_audio_model()
    
    try:
        result = predict_audio_stream(stream_url, duration_seconds)
        return jsonify(result)
    except Exception as e:
        import traceback
        traceback.print_exc()
        return jsonify({'error': str(e)}), 500


@app.route('/detect/events/audio/stream', methods=['POST'])
def detect_events_audio_stream_endpoint():
 
    global audio_model

    data = request.get_json()
    if not data:
        return jsonify({'error': 'No JSON data provided'}), 400

    stream_url = data.get('stream_url')
    if not stream_url:
        return jsonify({'error': 'No stream_url provided'}), 400

    duration = int(data.get('duration', 10))
    duration = min(max(5, duration), 30)
                                                                                     
                                                                         
    confidence_threshold = float(data.get('confidence_threshold', 0.50))

    audio_path = None

    try:
                                       
        client_ip = get_client_ip()
        location = get_location_from_ip(client_ip)

                          
        if audio_model is None:
            load_audio_model()

                                                                  
        audio_path = extract_audio_from_stream(stream_url, duration)

                                    
        audio_result = predict_audio(audio_path)
        scene_class = (audio_result.get('predictedClass') or 'unknown').lower().strip()
        import re as _re
        scene_class = _re.sub(r'\s*\(.*\)', '', scene_class).strip()
        scene_confidence = audio_result.get('confidence', 0)
        print(f"[EventDetection/AudioStream] Scene: {scene_class} ({scene_confidence*100:.1f}%)")

                                                   
        relevant_events = get_events_for_scene(scene_class)
        detected_events = {}
        for event in relevant_events:
                                                                             
            severity = get_event_severity(event)
            event_conf = scene_confidence * 0.55 + (severity / 10.0) * 0.1
            event_conf = min(round(event_conf, 4), scene_confidence)
            if event_conf >= confidence_threshold:
                detected_events[event] = event_conf

                                          
        sorted_events = sorted(
            detected_events.items(),
            key=lambda x: (x[1], get_event_severity(x[0])),
            reverse=True
        ) if detected_events else []

        highest_severity = None
        if sorted_events:
            highest_severity = {
                'type': sorted_events[0][0],
                'confidence': sorted_events[0][1],
                'severity': get_event_severity(sorted_events[0][0])
            }

        print(f"[EventDetection/AudioStream] Events: {detected_events}")

        return jsonify({
            'success': True,
            'sceneClassification': {
                'predictedClass': scene_class,
                'confidence': scene_confidence,
                'topPredictions': audio_result.get('topPredictions', [])
            },
            'eventDetection': {
                'eventsDetected': len(detected_events) > 0,
                'events': [event for event, _ in sorted_events],
                'eventConfidences': detected_events,
                'relevantEventsForScene': relevant_events,
                'highestSeverityEvent': highest_severity,
                'alertLevel': 'CRITICAL' if highest_severity else 'NORMAL',
                'confidenceThreshold': confidence_threshold,
            },
            'streamInfo': {
                'url': stream_url,
                'capturedDuration': duration
            },
            'location': location
        })

    except Exception as e:
        import traceback
        traceback.print_exc()
        return jsonify({'error': str(e)}), 500
    finally:
        if audio_path and os.path.exists(audio_path):
            os.remove(audio_path)


def detect_visual_anomalies(video_path, brightness_threshold=200, min_area=500):
    cap = cv2.VideoCapture(video_path)
    
    if not cap.isOpened():
        raise ValueError(f"Cannot open video: {video_path}")
    
    fps = cap.get(cv2.CAP_PROP_FPS)
    total_frames = int(cap.get(cv2.CAP_PROP_FRAME_COUNT))
    width = int(cap.get(cv2.CAP_PROP_FRAME_WIDTH))
    height = int(cap.get(cv2.CAP_PROP_FRAME_HEIGHT))
    duration = total_frames / fps if fps > 0 else 0
    
    detections = []
    prev_frame_gray = None
    prev_brightness = 0
    frame_idx = 0
    large_spike_frames = 0
    
    print(f"Analyzing video for event detection: {total_frames} frames, {duration:.1f}s")
    
    while True:
        ret, frame = cap.read()
        if not ret:
            break
        
        frame_rgb = cv2.cvtColor(frame, cv2.COLOR_BGR2RGB)
        frame_gray = cv2.cvtColor(frame, cv2.COLOR_BGR2GRAY)
        
        avg_brightness = np.mean(frame_gray)
        
        brightness_spike = avg_brightness - prev_brightness if prev_brightness > 0 else 0
        
        _, bright_mask = cv2.threshold(frame_gray, brightness_threshold, 255, cv2.THRESH_BINARY)
        
        contours, _ = cv2.findContours(bright_mask, cv2.RETR_EXTERNAL, cv2.CHAIN_APPROX_SIMPLE)
        
        motion_score = 0
        if prev_frame_gray is not None:
            frame_diff = cv2.absdiff(prev_frame_gray, frame_gray)
            motion_score = np.mean(frame_diff)
        
        is_blast_frame = False
        frame_boxes = []
        
        for contour in contours:
            area = cv2.contourArea(contour)
            if area > min_area:
                x, y, w, h = cv2.boundingRect(contour)
                
                roi = frame_gray[y:y+h, x:x+w]
                region_brightness = np.mean(roi) if roi.size > 0 else 0
                
                event_confidence = 0
                
                if area > min_area * 2:
                    event_confidence += 0.3
                if brightness_spike > 20:
                    event_confidence += 0.3
                if motion_score > 15:
                    event_confidence += 0.2
                if region_brightness > brightness_threshold:
                    event_confidence += 0.2
                
                if event_confidence >= 0.5:
                    is_blast_frame = True
                    frame_boxes.append({
                        'x': int(x),
                        'y': int(y),
                        'width': int(w),
                        'height': int(h),
                        'confidence': round(min(event_confidence, 1.0), 2),
                        'area': int(area),
                        'brightness': round(region_brightness, 1)
                    })
        
        if is_blast_frame and frame_boxes:
            if brightness_spike > 30:
                large_spike_frames += 1
            timestamp = frame_idx / fps if fps > 0 else 0

            # Skip first 1.5 seconds to avoid video start artifacts (logos, encoding, initial brightness)
            if timestamp >= 1.5:
                detections.append({
                    'frameIndex': frame_idx,
                    'timestamp': round(timestamp, 2),
                    'avgBrightness': round(avg_brightness, 1),
                    'brightnessSpikeScore': round(brightness_spike, 1),
                    'motionScore': round(motion_score, 1),
                    'boundingBoxes': frame_boxes
                })
                print(f"  Event detected at {timestamp:.2f}s - {len(frame_boxes)} region(s)")
            else:
                print(f"  [Skipped] Detection at {timestamp:.2f}s (too early, likely video start artifact)")
        
        prev_frame_gray = frame_gray.copy()
        prev_brightness = avg_brightness
        frame_idx += 1
    
    cap.release()
    
    event_detected = len(detections) > 0
    max_confidence = max([max([b['confidence'] for b in d['boundingBoxes']]) for d in detections]) if detections else 0
    
    primary_detection = None
    if detections:
        best_detection = max(detections, key=lambda d: max([b['confidence'] for b in d['boundingBoxes']]))
        primary_detection = {
            'timestamp': best_detection['timestamp'],
            'boundingBoxes': best_detection['boundingBoxes']
        }
    
    return {
        'eventDetected': event_detected,
        'alertLevel': 'CRITICAL' if event_detected else 'NORMAL',
        'maxConfidence': round(max_confidence, 2),
        'totalDetections': len(detections),
        'largeSpikeFrames': large_spike_frames,
        'videoInfo': {
            'width': width,
            'height': height,
            'fps': round(fps, 1),
            'durationSeconds': round(duration, 2),
            'totalFrames': total_frames
        },
        'primaryDetection': primary_detection,
        'allDetections': detections,
        'emergencyAction': {
            'recommended': event_detected,
            'action': 'CALL_911',
            'message': 'Event detected! Emergency response recommended.' if event_detected else 'No threat detected.'
        }
    }


@app.route('/detect/anomalies', methods=['POST'])
def detect_anomalies_endpoint():
    if 'video' not in request.files:
        return jsonify({'error': 'No video file provided'}), 400
    
    video_file = request.files['video']
    
    brightness_threshold = int(request.form.get('brightness_threshold', 200))
    min_area = int(request.form.get('min_area', 500))
    
    with tempfile.NamedTemporaryFile(delete=False, suffix='.mp4') as tmp:
        video_file.save(tmp.name)
        tmp_path = tmp.name
    
    try:
        scene_result = None
        try:
            scene_result = predict_video(tmp_path)
        except Exception as e:
            print(f"Scene classification failed: {e}")
        
        result = detect_visual_anomalies(tmp_path, brightness_threshold, min_area)
        
        if scene_result:
            result['sceneClassification'] = {
                'predictedClass': scene_result.get('predicted_class', 'unknown'),
                'confidence': scene_result.get('confidence', 0),
                'probabilities': scene_result.get('probabilities', {})
            }
        else:
            result['sceneClassification'] = {
                'predictedClass': 'unknown',
                'confidence': 0,
                'probabilities': {}
            }
        
        return jsonify(result)
    except Exception as e:
        import traceback
        traceback.print_exc()
        return jsonify({'error': str(e)}), 500
    finally:
        if os.path.exists(tmp_path):
            os.remove(tmp_path)


@app.route('/detect/anomalies/stream', methods=['POST'])
def detect_anomalies_stream_endpoint():
    data = request.get_json()
    if not data:
        return jsonify({'error': 'No JSON data provided'}), 400
    
    stream_url = data.get('stream_url')
    if not stream_url:
        return jsonify({'error': 'No stream_url provided'}), 400
    
    duration = int(data.get('duration', 5))
    brightness_threshold = int(data.get('brightness_threshold', 200))
    min_area = int(data.get('min_area', 500))
    
    tmp_path = None
    
    try:
        print(f"Capturing stream for blast detection: {stream_url} ({duration}s)")
        tmp_path, stream_url, captured, fps = capture_stream_to_temp_video(stream_url, duration)
        
        if captured < 10:
            return jsonify({'error': 'Failed to capture enough frames from stream'}), 400
        
        print(f"Stream capture complete: {captured} frames")
        
        scene_result = None
        try:
            scene_result = predict_video(tmp_path)
        except Exception as e:
            print(f"Scene classification failed: {e}")
        
        result = detect_visual_anomalies(tmp_path, brightness_threshold, min_area)
        
        if scene_result:
            result['sceneClassification'] = {
                'predictedClass': scene_result.get('predicted_class', 'unknown'),
                'confidence': scene_result.get('confidence', 0),
                'probabilities': scene_result.get('probabilities', {})
            }
        else:
            result['sceneClassification'] = {
                'predictedClass': 'unknown',
                'confidence': 0,
                'probabilities': {}
            }
        
        result['streamInfo'] = {
            'url': stream_url,
            'capturedFrames': captured,
            'capturedDuration': round(captured / fps, 2)
        }
        
        return jsonify(result)
        
    except Exception as e:
        import traceback
        traceback.print_exc()
        return jsonify({'error': str(e)}), 500
    finally:
        if tmp_path and os.path.exists(tmp_path):
            os.remove(tmp_path)


                                                                              
                     
                                                                              

def get_client_ip():
 
    if request.environ.get('HTTP_X_FORWARDED_FOR') is None:
        return request.environ.get('REMOTE_ADDR', '127.0.0.1')
    else:
        return request.environ['HTTP_X_FORWARDED_FOR'].split(',')[0].strip()

def is_private_ip(ip):
 
    if not ip or ip in ('127.0.0.1', 'localhost', '::1'):
        return True
    if ip.startswith('::ffff:'):
        ip = ip[7:]
    parts = ip.split('.')
    if len(parts) == 4:
        try:
            parts = [int(p) for p in parts]
            if parts[0] == 10:
                return True
            if parts[0] == 172 and 16 <= parts[1] <= 31:
                return True
            if parts[0] == 192 and parts[1] == 168:
                return True
        except ValueError:
            pass
    return False

def get_location_from_ip(ip_address):
 
    if is_private_ip(ip_address):
        return {
            'ip': ip_address,
            'latitude': 0,
            'longitude': 0,
            'city': 'Local',
            'region': 'Local Network',
            'country': 'Local',
            'accuracy': 'unknown',
            'isLocal': True
        }
    
                        
    try:
        response = requests.get(f'http://ipapi.co/{ip_address}/json/', timeout=5)
        data = response.json()
        if 'latitude' in data and 'longitude' in data:
            return {
                'ip': ip_address,
                'latitude': float(data['latitude']),
                'longitude': float(data['longitude']),
                'city': data.get('city', 'Unknown'),
                'region': data.get('region', 'Unknown'),
                'country': data.get('country_name', 'Unknown'),
                'accuracy': 'city_level',
                'service': 'ipapi.co'
            }
    except Exception as e:
        print(f"[Geolocation] ipapi.co failed: {e}")
    
                          
    try:
        response = requests.get(f'http://ip-api.com/json/{ip_address}', timeout=5)
        data = response.json()
        if data.get('status') == 'success':
            return {
                'ip': ip_address,
                'latitude': float(data['lat']),
                'longitude': float(data['lon']),
                'city': data.get('city', 'Unknown'),
                'region': data.get('regionName', 'Unknown'),
                'country': data.get('country', 'Unknown'),
                'accuracy': 'city_level',
                'service': 'ip-api.com'
            }
    except Exception as e:
        print(f"[Geolocation] ip-api.com failed: {e}")
    
    return None


                                                                              
                                         
                                                                              

@app.route('/detect/events', methods=['POST'])
def detect_events_endpoint():
 
    if 'video' not in request.files:
        return jsonify({'error': 'No video file provided'}), 400
    
    video_file = request.files['video']
    enable_avslowfast = request.form.get('enable_avslowfast', 'true').lower() == 'true'
    confidence_threshold = float(request.form.get('confidence_threshold', 0.005))
    enable_motion_fallback = request.form.get('enable_motion_fallback', 'false').lower() == 'true'
    
    with tempfile.NamedTemporaryFile(delete=False, suffix='.mp4') as tmp:
        video_file.save(tmp.name)
        tmp_path = tmp.name
    
    try:
                             
        client_ip = get_client_ip()
        location = get_location_from_ip(client_ip)
        
                              
        scene_result = predict_video(tmp_path)
                                                                     
        scene_class = scene_result.get('predictedClass') or scene_result.get('predicted_class') or 'unknown'
        scene_class = scene_class.lower().strip()
                                                                            
        import re as _re
        scene_class = _re.sub(r'\s*\(.*\)', '', scene_class).strip()
        scene_confidence = scene_result.get('confidence', 0)
        print(f"[EventDetection] Scene: {scene_class} ({scene_confidence*100:.1f}%)")
        
                                            
        relevant_events = get_events_for_scene(scene_class)
        print(f"[EventDetection] Relevant events for '{scene_class}': {relevant_events}")
        
                                                                                                     
        avslowfast_result = None
        if enable_avslowfast and AVSLOWFAST_AVAILABLE:
            try:
                avdetector = get_event_detector(confidence_threshold)
                if avdetector is not None and avdetector._model_loaded:
                    frames = load_video_frames_for_event_detection(tmp_path)
                    if frames is not None:
                        avslowfast_result = avdetector.detect(
                            frames,
                            scene_class,
                            scene_confidence
                        )
                        print(f"[EventDetection] AVSlowFast events: {avslowfast_result.get('events', [])}")
                else:
                    print("[EventDetection] AVSlowFast model did not load; skipping (no fallback)")
            except Exception as e:
                print(f"[EventDetection] AVSlowFast failed: {e}")
        
                                                                                              
        visual_result = None
        try:
            visual_result = detect_visual_anomalies(tmp_path)
        except Exception as e:
            print(f"[EventDetection] Visual anomaly analysis failed: {e}")

        visual_event = None
        if visual_result:
            visual_event = determine_event_type_from_visual(visual_result, scene_class)
            if visual_event:
                print(f"[EventDetection] Visual analysis detected: {visual_event}")

                                                      
        filtered_events = {}

 
        event_min_thresholds = {
            'riot': 0.03,      
            'fight': 0.025,    
            'evacuation': 0.02  
        }

        if avslowfast_result:
            event_confidences = avslowfast_result.get('event_confidences', {})
            for e, c in event_confidences.items():
                if e in relevant_events:
                    # Use event-specific threshold if available, otherwise use global
                    min_threshold = event_min_thresholds.get(e, confidence_threshold)
                    if c >= min_threshold:
                        filtered_events[e] = c
                        print(f"[EventDetection] {e} passed threshold (conf={c:.4f}, min={min_threshold})")
                    else:
                        print(f"[EventDetection] {e} filtered out (conf={c:.4f} < min={min_threshold})")
                                                                                                      
        if visual_event:
            vis_conf = visual_result.get('maxConfidence', 0.75) if visual_result else 0.75
            if visual_event not in filtered_events or vis_conf > filtered_events[visual_event]:
                filtered_events[visual_event] = vis_conf
                                                                                      
        if enable_motion_fallback and not filtered_events:
            motion_events = analyze_motion_for_events(
                tmp_path, scene_class, scene_confidence, confidence_threshold
            )
            if motion_events:
                filtered_events.update(motion_events)
                print(f"[EventDetection] Motion fallback used: {motion_events}")
        print(f"[EventDetection] Events after fusion ({confidence_threshold}): {filtered_events}")
        
                                                                             
        highest_severity = None
        sorted_events = []
        if filtered_events:
            sorted_events = sorted(
                filtered_events.items(),
                key=lambda x: (x[1], get_event_severity(x[0])),
                reverse=True
            )
            highest_severity = {
                'type': sorted_events[0][0],
                'confidence': sorted_events[0][1],
                'severity': get_event_severity(sorted_events[0][0])
            }
        
        return jsonify({
            'success': True,
            'sceneClassification': {
                'predictedClass': scene_class,
                'confidence': scene_confidence,
                'probabilities': scene_result.get('probabilities', {})
            },
            'eventDetection': {
                'eventsDetected': len(filtered_events) > 0,
                'events': [event for event, _ in sorted_events],
                'eventConfidences': filtered_events,
                'relevantEventsForScene': relevant_events,
                'highestSeverityEvent': highest_severity,
                'alertLevel': 'CRITICAL' if highest_severity else 'NORMAL',
                'confidenceThreshold': confidence_threshold,
            },
            'visualAnalysis': {
                'eventDetected': visual_result.get('eventDetected', False) if visual_result else False,
                'detectedEvent': visual_event,
                'totalDetections': visual_result.get('totalDetections', 0) if visual_result else 0,
                'maxConfidence': visual_result.get('maxConfidence', 0) if visual_result else 0,
            },
            'location': location,
            'emergencyAction': {
                'recommended': len(filtered_events) > 0,
                'action': 'ALERT_AUTHORITIES' if highest_severity else 'MONITOR',
                'message': f"{highest_severity['type'].replace('_', ' ').title()} detected!" if highest_severity else 'No emergency detected'
            }
        })
        
    except Exception as e:
        import traceback
        traceback.print_exc()
        return jsonify({'error': str(e)}), 500
    finally:
        if os.path.exists(tmp_path):
            os.remove(tmp_path)


@app.route('/detect/events/audio', methods=['POST'])
def detect_events_audio_file_endpoint():
 
    global audio_model, passt_model, current_audio_model_type

    if 'audio' not in request.files:
        return jsonify({'error': 'No audio file provided'}), 400

    audio_file = request.files['audio']
    confidence_threshold = float(request.form.get('confidence_threshold', 0.50))

    ext = os.path.splitext(audio_file.filename)[1] if audio_file.filename else '.wav'
    if not ext:
        ext = '.wav'

    with tempfile.NamedTemporaryFile(delete=False, suffix=ext) as tmp:
        audio_file.save(tmp.name)
        tmp_path = tmp.name

    try:
 
        client_ip = get_client_ip()
        location = get_location_from_ip(client_ip)

        # Ensure audio model is loaded
        if current_audio_model_type == 'passt' and PASST_AVAILABLE:
            if passt_model is None:
                load_passt_model()
        else:
            if audio_model is None:
                load_audio_model()

 
        audio_result = predict_audio(tmp_path)
        scene_class = (audio_result.get('predictedClass') or 'unknown').lower().strip()
        import re as _re
        scene_class = _re.sub(r'\s*\(.*\)', '', scene_class).strip()
        scene_confidence = audio_result.get('confidence', 0)
        print(f"[EventDetection/AudioFile] Scene: {scene_class} ({scene_confidence*100:.1f}%)")

 
        relevant_events = get_events_for_scene(scene_class)
        detected_events = {}
        for event in relevant_events:
 
            severity = get_event_severity(event)
            event_conf = scene_confidence * 0.55 + (severity / 10.0) * 0.1
            event_conf = min(round(event_conf, 4), scene_confidence)
            if event_conf >= confidence_threshold:
                detected_events[event] = event_conf

 
        sorted_events = sorted(
            detected_events.items(),
            key=lambda x: (x[1], get_event_severity(x[0])),
            reverse=True
        ) if detected_events else []

        highest_severity = None
        if sorted_events:
            highest_severity = {
                'type': sorted_events[0][0],
                'confidence': sorted_events[0][1],
                'severity': get_event_severity(sorted_events[0][0])
            }

        print(f"[EventDetection/AudioFile] Events: {detected_events}")

        return jsonify({
            'success': True,
            'sceneClassification': {
                'predictedClass': scene_class,
                'confidence': scene_confidence,
                'topPredictions': audio_result.get('topPredictions', [])
            },
            'eventDetection': {
                'eventsDetected': len(detected_events) > 0,
                'events': [event for event, _ in sorted_events],
                'eventConfidences': detected_events,
                'relevantEventsForScene': relevant_events,
                'highestSeverityEvent': highest_severity,
                'alertLevel': 'CRITICAL' if highest_severity else 'NORMAL',
                'confidenceThreshold': confidence_threshold,
            },
            'audioInfo': {
                'modelType': current_audio_model_type
            },
            'location': location
        })

    except Exception as e:
        import traceback
        traceback.print_exc()
        return jsonify({'error': str(e)}), 500
    finally:
        if os.path.exists(tmp_path):
            os.remove(tmp_path)


def load_video_frames_for_event_detection(video_path, num_frames=64):
 
    try:
        cap = cv2.VideoCapture(video_path)
        if not cap.isOpened():
            return None
        
        total_frames = int(cap.get(cv2.CAP_PROP_FRAME_COUNT))
        if total_frames <= 0:
            total_frames = 100
        
        indices = np.linspace(0, total_frames - 1, num_frames, dtype=int)
        frames = []
        
        for idx in indices:
            cap.set(cv2.CAP_PROP_POS_FRAMES, idx)
            ret, frame = cap.read()
            if ret:
                frame = cv2.resize(frame, (224, 224))
                frame = cv2.cvtColor(frame, cv2.COLOR_BGR2RGB)
                frame = frame.astype(np.float32) / 255.0
                frames.append(frame)
        
        cap.release()
        
        if len(frames) < num_frames:
                                 
            while len(frames) < num_frames:
                frames.append(frames[-1] if frames else np.zeros((224, 224, 3), dtype=np.float32))
        
                                           
        frames_array = np.array(frames)                
        frames_array = frames_array.transpose(3, 0, 1, 2)                
        frames_tensor = torch.from_numpy(frames_array).unsqueeze(0)                   
        
        return frames_tensor
        
    except Exception as e:
        print(f"[EventDetection] Failed to load frames: {e}")
        return None


def analyze_motion_for_events(video_path, scene_class, scene_confidence, confidence_threshold=0.005):

    scene_key = scene_class.lower().strip()
    relevant = get_events_for_scene(scene_key)
    if not relevant:
        return {}

    cap = cv2.VideoCapture(video_path)
    if not cap.isOpened():
        return {}

    prev_gray = None
    motion_scores = []

    try:
        while True:
            ret, frame = cap.read()
            if not ret:
                break
            small = cv2.resize(frame, (160, 120))
            gray = cv2.cvtColor(small, cv2.COLOR_BGR2GRAY)
            if prev_gray is not None:
                diff = cv2.absdiff(prev_gray, gray)
                motion_scores.append(float(np.mean(diff)))
            prev_gray = gray
    finally:
        cap.release()

    if not motion_scores:
        return {}

    avg_motion = float(np.mean(motion_scores))
    max_motion = float(np.max(motion_scores))

    if avg_motion < 2.0:
        return {}                                         

                                                                                    
                                                                             
    base_conf = min(avg_motion / 35.0, 0.85) * max(scene_confidence, 0.3)

    if base_conf < confidence_threshold:
        return {}

    events = {}
    spike_ratio = max_motion / max(avg_motion, 0.1)

    if max_motion > 25 or spike_ratio > 4.0:
                                                                  
        high_sev = [e for e in relevant if get_event_severity(e) >= 4]
        for e in high_sev:
            events[e] = round(min(base_conf * 1.2, 0.9), 4)

    if avg_motion > 5:
                                                                    
        for e in relevant:
            if e not in events:
                events[e] = round(base_conf, 4)
    else:
                                                                                
        if relevant and relevant[0] not in events:
            events[relevant[0]] = round(base_conf, 4)

                                                    
    events = {e: c for e, c in events.items() if c >= confidence_threshold}
    print(f"[MotionFallback] avg={avg_motion:.1f} max={max_motion:.1f} → {events}")
    return events


def determine_event_type_from_visual(visual_result, scene_class):
 
    if not visual_result or not isinstance(visual_result, dict):
        return None

    scene_key = scene_class.lower().strip()

    event_detected   = visual_result.get('eventDetected', False)
    max_confidence   = visual_result.get('maxConfidence', 0)
    total_detections = visual_result.get('totalDetections', 0)

    all_detections = visual_result.get('allDetections', [])
    max_brightness_spike = 0
    for det in all_detections:
        spike = det.get('brightnessSpikeScore', 0)
        if spike > max_brightness_spike:
            max_brightness_spike = spike

    transit_scenes = {'bus', 'tram', 'metro', 'metro_station'}
    is_transit_scene = scene_key in transit_scenes
    required_detections = 4 if is_transit_scene else 3
    required_spike = 80 if is_transit_scene else 60
    required_confidence = 0.8 if is_transit_scene else 0.7

    if (event_detected
            and total_detections >= required_detections
            and max_brightness_spike >= required_spike
            and max_confidence >= required_confidence):
                                                                    
                                                                              
                                                                                         
        if scene_key in {'metro', 'metro_station'}:
            return 'explosion' if max_brightness_spike >= 100 else None
        if scene_key in {'bus', 'tram'}:
            return 'explosion' if max_brightness_spike >= 95 else 'fire'

        fire_scenes = {'park', 'street_traffic', 'street_pedestrian', 'public_square'}
        return 'fire' if scene_key in fire_scenes else 'explosion'

    return None


@app.route('/detect/events/stream', methods=['POST'])
def detect_events_stream_endpoint():
 
    data = request.get_json()
    if not data:
        return jsonify({'error': 'No JSON data provided'}), 400
    
    stream_url = data.get('stream_url')
    if not stream_url:
        return jsonify({'error': 'No stream_url provided'}), 400
    
    duration = int(data.get('duration', 5))
    confidence_threshold = float(data.get('confidence_threshold', 0.005))
    enable_motion_fallback_raw = data.get('enable_motion_fallback', True)
    if isinstance(enable_motion_fallback_raw, str):
        enable_motion_fallback = enable_motion_fallback_raw.strip().lower() in {
            '1', 'true', 'yes', 'on'
        }
    else:
        enable_motion_fallback = bool(enable_motion_fallback_raw)
    
    tmp_path = None
    
    try:
                             
        client_ip = get_client_ip()
        location = get_location_from_ip(client_ip)
        
        tmp_path, stream_url, captured, fps = capture_stream_to_temp_video(stream_url, duration)
        
        if captured == 0:
            return jsonify({'error': 'No frames captured from stream'}), 400
        
                              
        scene_result = predict_video(tmp_path)
                                                                     
        scene_class = scene_result.get('predictedClass') or scene_result.get('predicted_class') or 'unknown'
        scene_class = scene_class.lower().strip()
        import re as _re
        scene_class = _re.sub(r'\s*\(.*\)', '', scene_class).strip()
        scene_confidence = scene_result.get('confidence', 0)
        print(f"[EventDetection/Stream] Scene: {scene_class} ({scene_confidence*100:.1f}%)")
        
                             
        relevant_events = get_events_for_scene(scene_class)
        detected_events = {}
        
                                                                        
        avslowfast_result = None
        if AVSLOWFAST_AVAILABLE:
            try:
                avdetector_stream = get_event_detector(confidence_threshold)
                detector = avdetector_stream                            
                frames = load_video_frames_for_event_detection(tmp_path)
                if detector is not None and frames is not None:
                    avslowfast_result = detector.detect(frames, scene_class, scene_confidence)
            except Exception as e:
                print(f"[EventDetection] AVSlowFast failed on stream: {e}")
        
        if avslowfast_result:
            all_event_confidences = dict(avslowfast_result.get('event_confidences', {}))
            detected_events = {
                e: c for e, c in all_event_confidences.items()
                if e in relevant_events and c >= confidence_threshold
            }

                                                                                         
            if not detected_events:
                all_candidates = {
                    e: c for e, c in all_event_confidences.items()
                    if c >= confidence_threshold
                }
                if all_candidates:
                    best_event, best_conf = max(
                        all_candidates.items(),
                        key=lambda x: (x[1], get_event_severity(x[0]))
                    )
                    detected_events[best_event] = best_conf
        print(f"[EventDetection/Stream] Events after gate ({confidence_threshold}): {detected_events}")

                                            
        visual_result_stream = None
        try:
            visual_result_stream = detect_visual_anomalies(tmp_path)
        except Exception as e:
            print(f"[EventDetection/Stream] Visual anomaly failed: {e}")
        visual_event_stream = None
        if visual_result_stream:
            visual_event_stream = determine_event_type_from_visual(visual_result_stream, scene_class)
            if visual_event_stream:
                print(f"[EventDetection/Stream] Visual detected: {visual_event_stream}")
                                                                                                
        if visual_event_stream:
            vis_conf = visual_result_stream.get('maxConfidence', 0.75) if visual_result_stream else 0.75
            if visual_event_stream not in detected_events or vis_conf > detected_events[visual_event_stream]:
                detected_events[visual_event_stream] = vis_conf

                                                                                   
        if enable_motion_fallback and not detected_events:
            motion_events = analyze_motion_for_events(
                tmp_path, scene_class, scene_confidence, confidence_threshold
            )
            if motion_events:
                detected_events.update(motion_events)
                print(f"[EventDetection/Stream] Motion fallback used: {motion_events}")
        
                                                            
        highest_severity = None
        sorted_events = []
        if detected_events:
            sorted_events = sorted(
                detected_events.items(),
                key=lambda x: (x[1], get_event_severity(x[0])),
                reverse=True
            )
            highest_severity = {
                'type': sorted_events[0][0],
                'confidence': sorted_events[0][1],
                'severity': get_event_severity(sorted_events[0][0])
            }
        
        return jsonify({
            'success': True,
            'sceneClassification': {
                'predictedClass': scene_class,
                'confidence': scene_confidence,
                'topPredictions': scene_result.get('topPredictions', [])
            },
            'eventDetection': {
                'eventsDetected': len(detected_events) > 0,
                'events': [event for event, _ in sorted_events],
                'eventConfidences': detected_events,
                'relevantEventsForScene': relevant_events,
                'highestSeverityEvent': highest_severity,
                'alertLevel': 'CRITICAL' if highest_severity else 'NORMAL',
                'confidenceThreshold': confidence_threshold,
            },
            'streamInfo': {
                'url': stream_url,
                'capturedFrames': captured,
                'capturedDuration': round(captured / fps, 2)
            },
            'location': location
        })
        
    except Exception as e:
        import traceback
        traceback.print_exc()
        return jsonify({'error': str(e)}), 500
    finally:
        if tmp_path and os.path.exists(tmp_path):
            os.remove(tmp_path)


                                                                             
                                                        
                                                                             

def record_from_mic(duration_seconds, samplerate=44100):
 
    if not SOUNDDEVICE_AVAILABLE:
        raise RuntimeError(
            "sounddevice is not installed. Run: pip install sounddevice"
        )
    duration_seconds = min(max(3, int(duration_seconds)), 60)
    print(f"[Hardware/Mic] Recording {duration_seconds}s from default microphone...")
    recording = sd.rec(
        int(duration_seconds * samplerate),
        samplerate=samplerate,
        channels=1,
        dtype='float32',
    )
    sd.wait()
    with tempfile.NamedTemporaryFile(delete=False, suffix='.wav') as tmp:
        tmp_path = tmp.name
    sf.write(tmp_path, recording, samplerate)
    print(f"[Hardware/Mic] Saved {duration_seconds}s recording to {tmp_path}")
    return tmp_path


@app.route('/predict/audio/local', methods=['POST'])
def predict_audio_local():
 
    global audio_model
    data = request.get_json() or {}
    duration_seconds = min(max(5, int(data.get('duration_seconds', 10))), 60)

    if audio_model is None:
        load_audio_model()

    audio_path = None
    try:
        audio_path = record_from_mic(duration_seconds)
        result = predict_audio(audio_path)
        result['type'] = 'audio_local'
        result['source'] = 'laptop_microphone'
        result['durationSeconds'] = duration_seconds
        return jsonify(result)
    except Exception as e:
        import traceback
        traceback.print_exc()
        return jsonify({'error': str(e)}), 500
    finally:
        if audio_path and os.path.exists(audio_path):
            os.remove(audio_path)


@app.route('/predict/video/local', methods=['POST'])
def predict_video_local():
 
    data = request.get_json() or {}
    duration_seconds = min(max(3, int(data.get('duration_seconds', 5))), 30)

    cap = None
    tmp_path = None
    try:
        print(f"[Hardware/Camera] Opening local camera device 0...")
        cap = cv2.VideoCapture(0)
        if not cap.isOpened():
            return jsonify({
                'error': 'Cannot open local camera (device 0). '
                         'Make sure a webcam is connected and not in use by another app.'
            }), 400

        fps = cap.get(cv2.CAP_PROP_FPS)
        if fps <= 0 or np.isnan(fps) or fps > 120:
            fps = 15
        width = int(cap.get(cv2.CAP_PROP_FRAME_WIDTH))
        height = int(cap.get(cv2.CAP_PROP_FRAME_HEIGHT))
        if width <= 0 or height <= 0:
            return jsonify({'error': 'Invalid frame size from local camera'}), 400

        with tempfile.NamedTemporaryFile(delete=False, suffix='.mp4') as tmp:
            tmp_path = tmp.name

        fourcc = cv2.VideoWriter_fourcc(*'mp4v')
        out = cv2.VideoWriter(tmp_path, fourcc, fps, (width, height))
        frames_target = int(fps * duration_seconds)
        frames_captured = 0
        print(f"[Hardware/Camera] Capturing {frames_target} frames ({duration_seconds}s @ {fps:.1f}fps)...")
        while frames_captured < frames_target:
            ok, frame = cap.read()
            if not ok:
                break
            out.write(frame)
            frames_captured += 1
        out.release()
        cap.release()
        cap = None

        if frames_captured == 0:
            return jsonify({'error': 'No frames captured from local camera'}), 400

        result = predict_video(tmp_path)
        result['type'] = 'video_local'
        result['source'] = 'laptop_camera'
        result['durationSeconds'] = duration_seconds
        return jsonify(result)
    except Exception as e:
        import traceback
        traceback.print_exc()
        return jsonify({'error': str(e)}), 500
    finally:
        if cap is not None:
            cap.release()
        if tmp_path and os.path.exists(tmp_path):
            os.remove(tmp_path)


@app.route('/detect/events/audio/local', methods=['POST'])
def detect_events_audio_local():
 
    global audio_model
    data = request.get_json() or {}
    duration = min(max(5, int(data.get('duration', 10))), 60)
    confidence_threshold = float(data.get('confidence_threshold', 0.50))

    audio_path = None
    try:
        client_ip = get_client_ip()
        location = get_location_from_ip(client_ip)

        if audio_model is None:
            load_audio_model()

        audio_path = record_from_mic(duration)

        audio_result = predict_audio(audio_path)
        scene_class = (audio_result.get('predictedClass') or 'unknown').lower().strip()
        import re as _re
        scene_class = _re.sub(r'\s*\(.*\)', '', scene_class).strip()
        scene_confidence = audio_result.get('confidence', 0)
        print(f"[EventDetection/AudioLocal] Scene: {scene_class} ({scene_confidence*100:.1f}%)")

        relevant_events = get_events_for_scene(scene_class)
        detected_events = {}
        for event in relevant_events:
            severity = get_event_severity(event)
            event_conf = scene_confidence * 0.55 + (severity / 10.0) * 0.1
            event_conf = min(round(event_conf, 4), scene_confidence)
            if event_conf >= confidence_threshold:
                detected_events[event] = event_conf

        sorted_events = sorted(
            detected_events.items(),
            key=lambda x: (x[1], get_event_severity(x[0])),
            reverse=True
        ) if detected_events else []

        highest_severity = None
        if sorted_events:
            highest_severity = {
                'type': sorted_events[0][0],
                'confidence': sorted_events[0][1],
                'severity': get_event_severity(sorted_events[0][0])
            }

        return jsonify({
            'success': True,
            'sceneClassification': {
                'predictedClass': scene_class,
                'confidence': scene_confidence,
                'topPredictions': audio_result.get('topPredictions', [])
            },
            'eventDetection': {
                'eventsDetected': len(detected_events) > 0,
                'events': [event for event, _ in sorted_events],
                'eventConfidences': detected_events,
                'relevantEventsForScene': relevant_events,
                'highestSeverityEvent': highest_severity,
                'alertLevel': 'CRITICAL' if highest_severity else 'NORMAL',
                'confidenceThreshold': confidence_threshold,
            },
            'sourceInfo': {
                'source': 'laptop_microphone',
                'capturedDuration': duration
            },
            'location': location
        })
    except Exception as e:
        import traceback
        traceback.print_exc()
        return jsonify({'error': str(e)}), 500
    finally:
        if audio_path and os.path.exists(audio_path):
            os.remove(audio_path)


@app.route('/detect/events/video/local', methods=['POST'])
def detect_events_video_local():
 
    data = request.get_json() or {}
    duration = min(max(3, int(data.get('duration', 5))), 30)
    confidence_threshold = float(data.get('confidence_threshold', 0.005))
    enable_motion_fallback_raw = data.get('enable_motion_fallback', True)
    if isinstance(enable_motion_fallback_raw, str):
        enable_motion_fallback = enable_motion_fallback_raw.strip().lower() in {
            '1', 'true', 'yes', 'on'
        }
    else:
        enable_motion_fallback = bool(enable_motion_fallback_raw)

    cap = None
    tmp_path = None
    try:
        client_ip = get_client_ip()
        location = get_location_from_ip(client_ip)

        print(f"[EventDetection/VideoLocal] Opening local camera device 0...")
        cap = cv2.VideoCapture(0)
        if not cap.isOpened():
            return jsonify({
                'error': 'Cannot open local camera (device 0). '
                         'Make sure a webcam is connected and not in use.'
            }), 400

        fps_cam = cap.get(cv2.CAP_PROP_FPS)
        if fps_cam <= 0 or np.isnan(fps_cam) or fps_cam > 120:
            fps_cam = 15
        w = int(cap.get(cv2.CAP_PROP_FRAME_WIDTH))
        h = int(cap.get(cv2.CAP_PROP_FRAME_HEIGHT))

        with tempfile.NamedTemporaryFile(delete=False, suffix='.mp4') as tmp:
            tmp_path = tmp.name

        fourcc = cv2.VideoWriter_fourcc(*'mp4v')
        out = cv2.VideoWriter(tmp_path, fourcc, fps_cam, (w, h))
        frames_target = int(fps_cam * duration)
        frames_captured = 0
        while frames_captured < frames_target:
            ok, frame = cap.read()
            if not ok:
                break
            out.write(frame)
            frames_captured += 1
        out.release()
        cap.release()
        cap = None

        if frames_captured == 0:
            return jsonify({'error': 'No frames captured from local camera'}), 400

        scene_result = predict_video(tmp_path)
        scene_class = (scene_result.get('predictedClass') or scene_result.get('predicted_class') or 'unknown').lower().strip()
        import re as _re
        scene_class = _re.sub(r'\s*\(.*\)', '', scene_class).strip()
        scene_confidence = scene_result.get('confidence', 0)
        print(f"[EventDetection/VideoLocal] Scene: {scene_class} ({scene_confidence*100:.1f}%)")

        relevant_events = get_events_for_scene(scene_class)
        detected_events = {}

        avslowfast_result = None
        if AVSLOWFAST_AVAILABLE:
            try:
                avdetector = get_event_detector(confidence_threshold)
                frames = load_video_frames_for_event_detection(tmp_path)
                if avdetector is not None and frames is not None:
                    avslowfast_result = avdetector.detect(frames, scene_class, scene_confidence)
            except Exception as e:
                print(f"[EventDetection/VideoLocal] AVSlowFast failed: {e}")

        all_event_confidences = {}
        for event in relevant_events:
            severity = get_event_severity(event)
            event_conf = scene_confidence * 0.55 + (severity / 10.0) * 0.1
            event_conf = min(round(event_conf, 4), scene_confidence)
            all_event_confidences[event] = event_conf

        if avslowfast_result:
            for ev_type, ev_conf in avslowfast_result.items():
                conf_val = float(ev_conf) if isinstance(ev_conf, str) else ev_conf
                if conf_val >= confidence_threshold:
                    if ev_type not in detected_events or conf_val > detected_events[ev_type]:
                        detected_events[ev_type] = conf_val
                        all_event_confidences[ev_type] = conf_val

        if not detected_events:
            all_candidates = {e: c for e, c in all_event_confidences.items() if c >= confidence_threshold}
            if all_candidates:
                best_event, best_conf = max(all_candidates.items(), key=lambda x: (x[1], get_event_severity(x[0])))
                detected_events[best_event] = best_conf

        visual_result_local = None
        try:
            visual_result_local = detect_visual_anomalies(tmp_path)
        except Exception as e:
            print(f"[EventDetection/VideoLocal] Visual anomaly failed: {e}")
        if visual_result_local:
            visual_event_local = determine_event_type_from_visual(visual_result_local, scene_class)
            if visual_event_local:
                vis_conf = visual_result_local.get('maxConfidence', 0.75)
                if visual_event_local not in detected_events or vis_conf > detected_events[visual_event_local]:
                    detected_events[visual_event_local] = vis_conf

        if enable_motion_fallback and not detected_events:
            motion_events = analyze_motion_for_events(tmp_path, scene_class, scene_confidence, confidence_threshold)
            if motion_events:
                detected_events.update(motion_events)

        highest_severity = None
        sorted_events = []
        if detected_events:
            sorted_events = sorted(detected_events.items(), key=lambda x: (x[1], get_event_severity(x[0])), reverse=True)
            highest_severity = {
                'type': sorted_events[0][0],
                'confidence': sorted_events[0][1],
                'severity': get_event_severity(sorted_events[0][0])
            }

        return jsonify({
            'success': True,
            'sceneClassification': {
                'predictedClass': scene_class,
                'confidence': scene_confidence,
                'topPredictions': scene_result.get('topPredictions', [])
            },
            'eventDetection': {
                'eventsDetected': len(detected_events) > 0,
                'events': [event for event, _ in sorted_events],
                'eventConfidences': detected_events,
                'relevantEventsForScene': relevant_events,
                'highestSeverityEvent': highest_severity,
                'alertLevel': 'CRITICAL' if highest_severity else 'NORMAL',
                'confidenceThreshold': confidence_threshold,
            },
            'sourceInfo': {
                'source': 'laptop_camera',
                'capturedFrames': frames_captured,
                'capturedDuration': round(frames_captured / fps_cam, 2)
            },
            'location': location
        })
    except Exception as e:
        import traceback
        traceback.print_exc()
        return jsonify({'error': str(e)}), 500
    finally:
        if cap is not None:
            cap.release()
        if tmp_path and os.path.exists(tmp_path):
            os.remove(tmp_path)


@app.route('/geolocation', methods=['GET'])
def get_geolocation_endpoint():
 
    client_ip = get_client_ip()
    location = get_location_from_ip(client_ip)
    return jsonify({
        'success': True,
        'clientIp': client_ip,
        'location': location
    })


if __name__ == '__main__':
    print("Loading MVATS Video Classification Model...")
    load_model()
    print("\nLoading MVATS Audio Classification Model (CNN14)...")
    load_audio_model()
    print(f"\nStarting server on http://localhost:5000")
    print("Available endpoints:")
    print("  GET  /health               - Health check")
    print("  GET  /classes              - Get class names")
    print("  GET  /geolocation          - Get client geolocation from IP")
    print("  POST /predict/video        - Classify video file")
    print("  POST /predict/audio        - Classify audio file (CNN14)")
    print("  POST /predict/multimodal   - Classify multimodal input (separate files)")
    print("  POST /predict/fusion       - Fusion prediction from single video file (audio+video)")
    print("  POST /predict/stream       - Classify from IP video stream")
    print("  POST /predict/audio/stream - Classify audio from IP stream (requires ffmpeg)")
    print("  POST /detect/anomalies         - Detect visual anomalies")
    print("  POST /detect/anomalies/stream  - Detect visual anomalies from stream")
    print("  POST /detect/events        - Comprehensive event detection with geolocation")
    print("  POST /detect/events/stream - Event detection from IP stream with geolocation")
    print("  POST /predict/audio/local       - Classify from laptop microphone")
    print("  POST /predict/video/local       - Classify from laptop camera")
    print("  POST /detect/events/audio/local - Event detection from laptop microphone")
    print("  POST /detect/events/video/local - Event detection from laptop camera")
    app.run(host='0.0.0.0', port=5000, debug=False)
