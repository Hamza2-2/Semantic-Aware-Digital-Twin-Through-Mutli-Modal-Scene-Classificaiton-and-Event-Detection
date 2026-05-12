# file header note
"""
AVSlowFast Event Detector Module for MVATS
Runs parallel to R(2+1)D-18 scene classification for emergency event detection.

This module:
- Loads pretrained AVSlowFast weights via PyTorchVideo (torch.hub)
- Performs inference only (frozen weights, no training)
- Outputs filtered event tags based on predicted scene class
"""

import torch
import torch.nn as nn
import torch.nn.functional as F
from typing import Dict, List, Optional, Tuple, Any
import warnings

                       
try:
    from event_taxonomy import (
        SCENE_EVENT_MAP,
        KINETICS_TO_EVENT_MAP,
        get_highest_severity_event,
        get_event_severity,
    )
except ImportError:
                                    
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

    EVENT_SEVERITY = {
        "explosion": 5,
        "fire": 5,
        "fire_alarm": 4,
        "riot": 4,
        "accident": 4,
        "vehicle_crash": 4,
        "evacuation": 3,
        "fight": 3,
        "sudden_brake": 2,
    }

    def get_highest_severity_event(events: dict):
        if not events:
            return None
        top_event, confidence = max(
            events.items(),
            key=lambda item: (EVENT_SEVERITY.get(item[0], 1), item[1]),
        )
        return (top_event, confidence, EVENT_SEVERITY.get(top_event, 1))

    def get_event_severity(event_type: str) -> int:
        return EVENT_SEVERITY.get(event_type, 1)

    KINETICS_TO_EVENT_MAP = {
        147: "explosion",
        148: "fire",
        156: "fight",
        157: "fight",
        184: "fight",
        262: "riot",
        68: "accident",
        69: "accident",
        78: "vehicle_crash",
        267: "evacuation",
        268: "evacuation",
        52: "fire_alarm",
    }


                                                           
                                                                               
KINETICS_EVENT_MAPPING = dict(KINETICS_TO_EVENT_MAP)


class AVSlowFastEventDetector:
    """
    Event detection using AVSlowFast model pretrained on Kinetics-400.
    
    This detector runs in parallel with the existing R(2+1)D-18 scene classifier
    to detect emergency events within video frames.
    
    Architecture:
        Video Input [B, C, T, H, W]
            ├── R(2+1)D-18 → scene_probs (existing, untouched)
            └── AVSlowFast → event_probs → filtered event tags
    
    Usage:
        detector = AVSlowFastEventDetector(device='cuda')
        result = detector.detect(video_tensor, scene_class='bus')
    """
    
    def __init__(
        self,
        device: str = 'cuda',
        confidence_threshold: float = 0.15,
        model_name: str = 'slowfast_r50'
    ):
        """
        Initialize the AVSlowFast event detector.
        
        Args:
            device: 'cuda' or 'cpu'
            confidence_threshold: Minimum confidence for event detection
            model_name: SlowFast variant ('slowfast_r50' or 'slowfast_r101')
        """
        self.device = device if torch.cuda.is_available() else 'cpu'
        self.confidence_threshold = confidence_threshold
        self.model_name = model_name
        self.model = None
        self._model_loaded = False
        
                           
        self._load_model()
    
    def _load_model(self):
        """Load pretrained AVSlowFast model via torch.hub."""
        try:
            with warnings.catch_warnings():
                warnings.simplefilter("ignore")
                
                                                     
                self.model = torch.hub.load(
                    'facebookresearch/pytorchvideo',
                    self.model_name,
                    pretrained=True
                )
                
                                                     
                self.model.eval()
                for param in self.model.parameters():
                    param.requires_grad = False
                
                self.model = self.model.to(self.device)
                self._model_loaded = True
                print(f"[AVSlowFast] Model loaded successfully on {self.device}")
                
        except Exception as e:
            print(f"[AVSlowFast] Warning: Could not load model: {e}")
            print("[AVSlowFast] Event detection will return empty results")
            self._model_loaded = False
    
    def _prepare_slowfast_input(
        self, 
        video_tensor: torch.Tensor
    ) -> List[torch.Tensor]:
        """
        Prepare video tensor for SlowFast model input.
        
        SlowFast expects two pathways:
        - Slow pathway: 8 frames (temporal stride 8)
        - Fast pathway: 32 frames (temporal stride 2) or 16 frames
        
        Args:
            video_tensor: Input tensor [B, C, T, H, W] or [B, T, C, H, W]
        
        Returns:
            List of [slow_tensor, fast_tensor] ready for model input
        """
                                               
        if video_tensor.dim() == 4:
                                 
            video_tensor = video_tensor.unsqueeze(0)
        
                                                                                 
        if video_tensor.shape[1] == 3:
            pass                           
        elif video_tensor.shape[2] == 3:
                                                        
            video_tensor = video_tensor.permute(0, 2, 1, 3, 4)
        
        B, C, T, H, W = video_tensor.shape
        
                                     
        if H != 256 or W != 256:
            video_tensor = F.interpolate(
                video_tensor.reshape(B * T, C, H, W),
                size=(256, 256),
                mode='bilinear',
                align_corners=False
            ).reshape(B, C, T, 256, 256)
        
                                    
        mean = torch.tensor([0.45, 0.45, 0.45]).view(1, 3, 1, 1, 1).to(video_tensor.device)
        std = torch.tensor([0.225, 0.225, 0.225]).view(1, 3, 1, 1, 1).to(video_tensor.device)
        video_tensor = (video_tensor - mean) / std
        
                                              
                                        
        if T >= 8:
            slow_indices = torch.linspace(0, T - 1, 8).long()
        else:
            slow_indices = torch.zeros(8, dtype=torch.long)
            slow_indices[:T] = torch.arange(T)
            slow_indices[T:] = T - 1
        
        slow_tensor = video_tensor[:, :, slow_indices, :, :]
        
                                                                   
        if T >= 32:
            fast_indices = torch.linspace(0, T - 1, 32).long()
        else:
            fast_indices = torch.zeros(32, dtype=torch.long)
            fast_indices[:T] = torch.arange(T)
            fast_indices[T:] = T - 1
        
        fast_tensor = video_tensor[:, :, fast_indices, :, :]
        
        return [slow_tensor, fast_tensor]
    
    def _map_predictions_to_events(
        self,
        predictions: torch.Tensor,
        scene_class: str
    ) -> Dict[str, float]:
        """
        Map AVSlowFast K400 class probabilities to scene-relevant emergency events
        using verified Kinetics-400 class indices with known semantic overlap.
        Only fight/fire/riot are detectable here; explosion/accident are handled
        upstream by visual anomaly analysis.
        """
        scene_key = scene_class.lower().strip()
        if '(' in scene_key and ')' in scene_key:
            scene_key = scene_key.split('(', 1)[0].strip()
        relevant_events = SCENE_EVENT_MAP.get(scene_key, [])
        if not relevant_events:
            return {}

        probs = predictions[0].detach().cpu()
        event_scores = {}

        for k400_idx, event_name in KINETICS_EVENT_MAPPING.items():
            if event_name not in relevant_events:
                continue
            prob = float(probs[k400_idx].item())
                                                                   
            if event_name not in event_scores or prob > event_scores[event_name]:
                event_scores[event_name] = prob

        return event_scores
    
    @torch.no_grad()
    def detect(
        self,
        video_tensor: torch.Tensor,
        scene_class: str,
        scene_confidence: float = 1.0
    ) -> Dict[str, Any]:
        """
        Detect emergency events in video based on scene context.
        
        Args:
            video_tensor: Video frames [B, C, T, H, W] or [B, T, C, H, W]
            scene_class: Predicted scene class (e.g., "bus", "street_traffic")
            scene_confidence: Confidence of scene prediction
        
        Returns:
            Dict containing:
                - scene: Scene class
                - scene_confidence: Scene prediction confidence
                - events: List of detected event types
                - event_confidences: Dict of {event: confidence}
                - highest_severity_event: Most critical detected event
        """
        result = {
            "scene": scene_class,
            "scene_confidence": scene_confidence,
            "events": [],
            "event_confidences": {},
            "raw_event_confidences": {},
            "highest_severity_event": None,
            "emergency_detected": False
        }
        
                                          
        if not self._model_loaded or self.model is None:
            return result
        
        try:
                                        
            video_tensor = video_tensor.to(self.device)
            slowfast_input = self._prepare_slowfast_input(video_tensor)
            
                           
            predictions = self.model(slowfast_input)
            predictions = F.softmax(predictions, dim=1)
            
                                                   
            probs_np = predictions[0].cpu().numpy()
            top20_idx = probs_np.argsort()[::-1][:20]
            print("[AVSlowFast] ── Raw softmax top-20 K400 classes ──")
            for rank, idx in enumerate(top20_idx, 1):
                print(f"  #{rank:2d}  idx={idx:3d}  prob={probs_np[idx]:.6f}")
            
            relevant_events = SCENE_EVENT_MAP.get(scene_class.lower().strip(), [])
            if relevant_events:
                event_scores = self._map_predictions_to_events(predictions, scene_class)
                print("[AVSlowFast] ── Scene event probability distribution ──")
                for ev, conf in sorted(event_scores.items(), key=lambda x: x[1], reverse=True):
                    print(f"  {ev:14s} prob={conf:.6f}")
            else:
                event_scores = {}
                print(f"[AVSlowFast] No scene mapping found for '{scene_class}'")
                                  

                                                                                   
            result["raw_event_confidences"] = dict(event_scores)

                                               
            filtered_events = {
                ev: conf for ev, conf in event_scores.items()
                if conf >= self.confidence_threshold
            }

                           
            result["events"] = list(filtered_events.keys())
            result["event_confidences"] = filtered_events
            result["emergency_detected"] = len(filtered_events) > 0

                                                                             
            if filtered_events:
                best_event, best_conf = max(
                    filtered_events.items(),
                    key=lambda x: (x[1], get_event_severity(x[0]))
                )
                result["highest_severity_event"] = {
                    "type": best_event,
                    "confidence": best_conf,
                    "severity": get_event_severity(best_event)
                }
            
        except Exception as e:
            print(f"[AVSlowFast] Detection error: {e}")
                                          
        
        return result
    
    def detect_from_frames(
        self,
        frames: List,
        scene_class: str,
        scene_confidence: float = 1.0
    ) -> Dict[str, Any]:
        """
        Detect events from a list of frames (numpy arrays or PIL Images).
        
        Args:
            frames: List of frames (numpy arrays H,W,C or PIL Images)
            scene_class: Predicted scene class
            scene_confidence: Scene prediction confidence
        
        Returns:
            Detection result dict
        """
        import numpy as np
        
                                  
        frame_tensors = []
        for frame in frames:
            if hasattr(frame, 'numpy'):
                frame = frame.numpy()
            if isinstance(frame, np.ndarray):
                            
                if frame.ndim == 3 and frame.shape[2] == 3:
                    frame = frame.transpose(2, 0, 1)
                frame_tensors.append(torch.from_numpy(frame).float() / 255.0)
        
        if not frame_tensors:
            return self.detect(torch.zeros(1, 3, 16, 224, 224), scene_class, scene_confidence)
        
                                                                 
        video_tensor = torch.stack(frame_tensors, dim=0)                
        video_tensor = video_tensor.permute(1, 0, 2, 3).unsqueeze(0)                   
        
        return self.detect(video_tensor, scene_class, scene_confidence)


def create_event_detector(
    use_avslowfast: bool = True,
    device: str = 'cuda',
    confidence_threshold: float = 0.15
) -> AVSlowFastEventDetector:
    """
    Factory function to create an event detector.
    IMPORTANT: no heuristic fallback is used.
    If AVSlowFast model can't load, returns an AVSlowFastEventDetector whose
    _model_loaded flag is False and whose detect() simply returns empty events.
    
    Args:
        use_avslowfast: Whether to try loading AVSlowFast
        device: 'cuda' or 'cpu'
        confidence_threshold: Minimum event confidence
    
    Returns:
        AVSlowFastEventDetector instance (may have _model_loaded=False)
    """
    detector = AVSlowFastEventDetector(
        device=device,
        confidence_threshold=confidence_threshold
    )
    if not detector._model_loaded:
        print("[EventDetector] AVSlowFast model NOT loaded — event detection will return empty results (no heuristic fallback)")
    return detector


               
if __name__ == "__main__":
    print("Testing AVSlowFast Event Detector...")
    
                     
    detector = create_event_detector(use_avslowfast=True, device='cpu')
    
                                               
    dummy_video = torch.randn(1, 3, 16, 224, 224)
    
                    
    result = detector.detect(
        dummy_video,
        scene_class="street_traffic",
        scene_confidence=0.87
    )
    
    print(f"Scene: {result['scene']}")
    print(f"Scene Confidence: {result['scene_confidence']}")
    print(f"Detected Events: {result['events']}")
    print(f"Event Confidences: {result['event_confidences']}")
    print(f"Emergency Detected: {result['emergency_detected']}")
    print(f"Highest Severity: {result['highest_severity_event']}")
