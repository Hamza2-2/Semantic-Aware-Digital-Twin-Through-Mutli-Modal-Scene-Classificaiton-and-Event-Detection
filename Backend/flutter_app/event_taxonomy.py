# file header note
"""
Event Taxonomy Module for MVATS
Maps scene classifications to relevant emergency events and provides
Kinetics/AVA action label mappings for AVSlowFast event detection.
"""

                                                  
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

                                          
ALL_EVENT_TYPES = list(set(
    event for events in SCENE_EVENT_MAP.values() for event in events
))

                                          
EVENT_SEVERITY = {
    "explosion": 5,
    "fire": 5,
    "fire_alarm": 4,
    "riot": 4,
    "accident": 4,
    "vehicle_crash": 4,
    "evacuation": 3,
    "fight": 3,
    "sudden_brake": 2
}

                                                        
                                                 
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

                                               
                                  
AVA_TO_EVENT_MAP = {
                       
    12: "fight",                               
    13: "fight",                    
    
                                               
    75: "evacuation",             
    
             
    17: "accident",                 
    
                                           
    4: "evacuation",                             
}

                                            
                                                         
EVENT_TO_ACTION_INDICES = {
    "explosion": [147],
    "fire": [148],
    "fire_alarm": [52, 148],
    "riot": [156, 157, 184, 262],
    "fight": [156, 157, 184],
    "accident": [68, 69, 78],
    "vehicle_crash": [78],
    "evacuation": [267, 268],
    "sudden_brake": [68],                             
}

                                             
ACTION_TO_EVENT = {}
for event, indices in EVENT_TO_ACTION_INDICES.items():
    for idx in indices:
        if idx not in ACTION_TO_EVENT:
            ACTION_TO_EVENT[idx] = []
        ACTION_TO_EVENT[idx].append(event)


def get_events_for_scene(scene_class: str) -> list:
    """
    Get relevant event types for a given scene classification.
    
    Args:
        scene_class: Predicted scene class (e.g., "bus", "street_traffic")
    
    Returns:
        List of relevant event types for this scene
    """
    scene_lower = scene_class.lower().strip()
    return SCENE_EVENT_MAP.get(scene_lower, [])


def filter_events_by_scene(detected_events: dict, scene_class: str) -> dict:
    """
    Filter detected events to only include those relevant to the scene.
    
    Args:
        detected_events: Dict of {event_type: confidence}
        scene_class: Predicted scene class
    
    Returns:
        Filtered dict with only scene-relevant events
    """
    relevant_events = get_events_for_scene(scene_class)
    return {
        event: conf 
        for event, conf in detected_events.items() 
        if event in relevant_events
    }


def get_event_severity(event_type: str) -> int:
    """Get severity level for an event type (1-5 scale)."""
    return EVENT_SEVERITY.get(event_type, 1)


def get_highest_severity_event(events: dict) -> tuple:
    """
    Get the event with highest severity from detected events.
    
    Args:
        events: Dict of {event_type: confidence}
    
    Returns:
        Tuple of (event_type, confidence, severity) or None if no events
    """
    if not events:
        return None
    
    sorted_events = sorted(
        events.items(),
        key=lambda x: (get_event_severity(x[0]), x[1]),
        reverse=True
    )
    
    top_event, confidence = sorted_events[0]
    return (top_event, confidence, get_event_severity(top_event))


def map_kinetics_predictions_to_events(
    predictions: dict, 
    threshold: float = 0.3
) -> dict:
    """
    Map Kinetics-400 class predictions to our event taxonomy.
    
    Args:
        predictions: Dict of {kinetics_class_index: confidence}
        threshold: Minimum confidence threshold
    
    Returns:
        Dict of {event_type: confidence}
    """
    event_confidences = {}
    
    for class_idx, confidence in predictions.items():
        if confidence < threshold:
            continue
            
        if class_idx in ACTION_TO_EVENT:
            for event_type in ACTION_TO_EVENT[class_idx]:
                                                          
                if event_type not in event_confidences:
                    event_confidences[event_type] = confidence
                else:
                    event_confidences[event_type] = max(
                        event_confidences[event_type], 
                        confidence
                    )
    
    return event_confidences


                                                       
AUDIO_EMERGENCY_KEYWORDS = {
    "explosion": ["explosion", "blast", "bang", "boom"],
    "fire_alarm": ["alarm", "siren", "beep", "alert"],
    "accident": ["crash", "collision", "impact", "screech"],
    "riot": ["shouting", "crowd", "yelling", "chanting"],
    "fight": ["scream", "yell", "shout"],
    "evacuation": ["siren", "alarm", "announcement"],
}


def detect_audio_events(audio_class: str, confidence: float = 1.0) -> dict:
    """
    Detect events from audio classification results.
    
    Args:
        audio_class: Predicted audio class
        confidence: Classification confidence
    
    Returns:
        Dict of {event_type: confidence}
    """
    audio_lower = audio_class.lower()
    detected = {}
    
    for event_type, keywords in AUDIO_EMERGENCY_KEYWORDS.items():
        for keyword in keywords:
            if keyword in audio_lower:
                detected[event_type] = confidence
                break
    
    return detected
