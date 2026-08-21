import os
import uuid
from django.conf import settings
from django.contrib.auth import get_user_model
from django.core.validators import FileExtensionValidator
from django.db import models
from django.utils import timezone

User = get_user_model()


def transcription_audio_path(instance, filename):
    """Generate unique path for uploaded audio files."""
    ext = filename.split('.')[-1]
    filename = f"{uuid.uuid4()}.{ext}"
    return os.path.join('transcriptions', str(instance.user.id), 'audio', filename)


def transcription_output_path(instance, filename):
    """Generate unique path for output files."""
    return os.path.join('transcriptions', str(instance.user.id), 'output', filename)


class TranscriptionJob(models.Model):
    """
    Represents a music transcription job that converts audio to alto sax sheet music.
    
    Processing pipeline:
    1. Audio normalization (FFmpeg)
    2. Vocal separation (Demucs)
    3. Melody transcription (Basic Pitch)
    4. Musical cleanup & quantization
    5. E♭ alto sax transposition (+9 semitones major sixth)
    6. Sheet music rendering (MusicXML → PDF/SVG)
    """
    
    # Source types
    SOURCE_UPLOAD = 'upload'
    SOURCE_URL = 'url'
    SOURCE_CHOICES = [
        (SOURCE_UPLOAD, 'Uploaded Audio File'),
        (SOURCE_URL, 'URL (authorized sources only)'),
    ]
    
    # Processing statuses
    STATUS_QUEUED = 'queued'
    STATUS_PREPARING_AUDIO = 'preparing_audio'
    STATUS_SEPARATING_VOCALS = 'separating_vocals'
    STATUS_TRANSCRIBING_MELODY = 'transcribing_melody'
    STATUS_CLEANING_NOTES = 'cleaning_notes'
    STATUS_TRANSPOSING_ALTO_SAX = 'transposing_for_alto_sax'
    STATUS_RENDERING_SHEET = 'rendering_sheet_music'
    STATUS_COMPLETE = 'complete'
    STATUS_FAILED = 'failed'
    
    STATUS_CHOICES = [
        (STATUS_QUEUED, 'Queued'),
        (STATUS_PREPARING_AUDIO, 'Preparing Audio'),
        (STATUS_SEPARATING_VOCALS, 'Isolating Vocals'),
        (STATUS_TRANSCRIBING_MELODY, 'Detecting Melody'),
        (STATUS_CLEANING_NOTES, 'Cleaning Notation'),
        (STATUS_TRANSPOSING_ALTO_SAX, 'Transposing for E♭ Alto Sax'),
        (STATUS_RENDERING_SHEET, 'Rendering Sheet Music'),
        (STATUS_COMPLETE, 'Complete'),
        (STATUS_FAILED, 'Failed'),
    ]
    
    # Core fields
    id = models.UUIDField(primary_key=True, default=uuid.uuid4, editable=False)
    user = models.ForeignKey(
        User,
        on_delete=models.CASCADE,
        related_name='transcriptions',
        db_index=True
    )
    
    # Source information
    source_type = models.CharField(max_length=10, choices=SOURCE_CHOICES, default=SOURCE_UPLOAD)
    source_url = models.URLField(blank=True, null=True, help_text='Optional URL for authorized audio sources')
    uploaded_audio = models.FileField(
        upload_to=transcription_audio_path,
        blank=True,
        null=True,
        validators=[FileExtensionValidator(allowed_extensions=['mp3', 'wav', 'm4a', 'flac', 'ogg', 'aac'])],
        help_text='Supported formats: MP3, WAV, M4A, FLAC, OGG, AAC'
    )
    
    # Metadata
    title = models.CharField(max_length=255, blank=True, default='Untitled')
    artist = models.CharField(max_length=255, blank=True, default='Unknown Artist')
    
    # Processing state
    status = models.CharField(max_length=30, choices=STATUS_CHOICES, default=STATUS_QUEUED, db_index=True)
    progress_percentage = models.IntegerField(default=0, help_text='0-100')
    current_stage = models.CharField(max_length=100, blank=True, default='')
    error_message = models.TextField(blank=True, default='')
    
    # Output files
    isolated_vocal = models.FileField(upload_to=transcription_output_path, blank=True, null=True)
    midi_file = models.FileField(upload_to=transcription_output_path, blank=True, null=True)
    musicxml_file = models.FileField(upload_to=transcription_output_path, blank=True, null=True)
    pdf_file = models.FileField(upload_to=transcription_output_path, blank=True, null=True)
    preview_svg = models.FileField(upload_to=transcription_output_path, blank=True, null=True)
    
    # Timestamps
    created_at = models.DateTimeField(auto_now_add=True, db_index=True)
    updated_at = models.DateTimeField(auto_now=True)
    started_at = models.DateTimeField(blank=True, null=True)
    completed_at = models.DateTimeField(blank=True, null=True)
    
    # Processing metadata (stored as JSON-serializable info)
    detected_tempo = models.FloatField(blank=True, null=True, help_text='BPM')
    detected_key = models.CharField(max_length=10, blank=True, default='', help_text='e.g., C major, A minor')
    detected_time_signature = models.CharField(max_length=10, blank=True, default='4/4')
    note_count = models.IntegerField(blank=True, null=True, help_text='Number of notes in transcription')
    
    class Meta:
        ordering = ['-created_at']
        indexes = [
            models.Index(fields=['user', 'status']),
            models.Index(fields=['user', '-created_at']),
        ]
    
    def __str__(self):
        return f"{self.title} by {self.artist} ({self.get_status_display()})"
    
    def get_audio_source(self):
        """Returns the file path or URL of the audio source."""
        if self.uploaded_audio:
            return self.uploaded_audio.path
        return self.source_url
    
    def mark_started(self):
        """Mark the job as started."""
        if not self.started_at:
            self.started_at = timezone.now()
            self.save(update_fields=['started_at'])
    
    def mark_complete(self):
        """Mark the job as complete."""
        self.status = self.STATUS_COMPLETE
        self.completed_at = timezone.now()
        self.progress_percentage = 100
        self.save(update_fields=['status', 'completed_at', 'progress_percentage'])
    
    def mark_failed(self, error_message):
        """Mark the job as failed with an error message."""
        self.status = self.STATUS_FAILED
        self.error_message = error_message
        self.completed_at = timezone.now()
        self.save(update_fields=['status', 'error_message', 'completed_at'])
    
    def update_progress(self, status, percentage, stage=''):
        """Update the job's progress."""
        self.status = status
        self.progress_percentage = min(100, max(0, percentage))
        self.current_stage = stage
        self.save(update_fields=['status', 'progress_percentage', 'current_stage', 'updated_at'])
    
    @property
    def is_processing(self):
        """Check if the job is currently being processed."""
        return self.status not in [self.STATUS_QUEUED, self.STATUS_COMPLETE, self.STATUS_FAILED]
    
    @property
    def is_complete(self):
        """Check if the job has completed successfully."""
        return self.status == self.STATUS_COMPLETE
    
    @property
    def has_failed(self):
        """Check if the job has failed."""
        return self.status == self.STATUS_FAILED
    
    @property
    def processing_time_seconds(self):
        """Calculate total processing time if available."""
        if self.started_at and self.completed_at:
            return (self.completed_at - self.started_at).total_seconds()
        return None
