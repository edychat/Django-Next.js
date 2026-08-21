"""
Service layer for music transcription processing.

Each service encapsulates a specific stage of the transcription pipeline,
making the system modular and testable.
"""

from .audio_preparation import AudioPreparationService
from .vocal_separation import VocalSeparationService
from .melody_transcription import MelodyTranscriptionService
from .notation_cleanup import NotationCleanupService
from .alto_sax_transposition import AltoSaxTranspositionService
from .sheet_music_renderer import SheetMusicRenderService

__all__ = [
    'AudioPreparationService',
    'VocalSeparationService',
    'MelodyTranscriptionService',
    'NotationCleanupService',
    'AltoSaxTranspositionService',
    'SheetMusicRenderService',
]
