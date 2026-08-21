from django.contrib import admin
from .models import TranscriptionJob


@admin.register(TranscriptionJob)
class TranscriptionJobAdmin(admin.ModelAdmin):
    list_display = [
        'id',
        'title',
        'artist',
        'user',
        'status',
        'progress_percentage',
        'source_type',
        'created_at',
        'completed_at',
    ]
    list_filter = ['status', 'source_type', 'created_at']
    search_fields = ['title', 'artist', 'user__username', 'user__email', 'id']
    readonly_fields = [
        'id',
        'created_at',
        'updated_at',
        'started_at',
        'completed_at',
        'progress_percentage',
        'current_stage',
        'processing_time_seconds',
    ]
    
    fieldsets = (
        ('Basic Information', {
            'fields': ('id', 'user', 'title', 'artist')
        }),
        ('Source', {
            'fields': ('source_type', 'source_url', 'uploaded_audio')
        }),
        ('Processing Status', {
            'fields': (
                'status',
                'progress_percentage',
                'current_stage',
                'error_message',
            )
        }),
        ('Output Files', {
            'fields': (
                'isolated_vocal',
                'midi_file',
                'musicxml_file',
                'pdf_file',
                'preview_svg',
            )
        }),
        ('Musical Analysis', {
            'fields': (
                'detected_tempo',
                'detected_key',
                'detected_time_signature',
                'note_count',
            )
        }),
        ('Timestamps', {
            'fields': (
                'created_at',
                'updated_at',
                'started_at',
                'completed_at',
                'processing_time_seconds',
            )
        }),
    )
    
    def processing_time_seconds(self, obj):
        """Display processing time in admin."""
        time = obj.processing_time_seconds
        if time:
            return f"{time:.2f}s"
        return "—"
    processing_time_seconds.short_description = "Processing Time"
    
    def has_add_permission(self, request):
        """Disable manual creation in admin."""
        return False
