"""
URL configuration for backend project.

The `urlpatterns` list routes URLs to views. For more information please see:
    https://docs.djangoproject.com/en/5.2/topics/http/urls/
Examples:
Function views
    1. Add an import:  from my_app import views
    2. Add a URL to urlpatterns:  path('', views.home, name='home')
Class-based views
    1. Add an import:  from other_app.views import Home
    2. Add a URL to urlpatterns:  path('', Home.as_view(), name='home')
Including another URLconf
    1. Import the include() function: from django.urls import include, path
    2. Add a URL to urlpatterns:  path('blog/', include('blog.urls'))
"""

# backend/urls.py
import os
import importlib
from django.contrib import admin
from django.urls import path, include
from django.http import JsonResponse
from django.middleware.csrf import get_token
from certificate.views import generate_certificate_legacy


# --- Dynamic app discovery ---
def find_apps(base_dir, exclude_dirs=None):
    exclude_dirs = exclude_dirs or []
    exclude_dirs = list(exclude_dirs) + ["_config", "__pycache__"]
    apps = []
    for item in os.listdir(base_dir):
        item_path = os.path.join(base_dir, item)
        if (
            os.path.isdir(item_path)
            and item not in exclude_dirs
            and os.path.isfile(os.path.join(item_path, "__init__.py"))
        ):
            apps.append(item)
    return apps


# --- Health and CSRF endpoints ---
def health_check(request):
    return JsonResponse({"status": "healthy", "service": "backend"})


def csrf_token(request):
    """CSRF token endpoint for frontend API calls"""
    return JsonResponse({"csrfToken": get_token(request)})


# --- Build urlpatterns dynamically ---
urlpatterns = [
    path("health/", health_check, name="health-check"),
    path("csrf/", csrf_token, name="csrf-token"),
    path("admin/", admin.site.urls),
    
    # Legacy certificate generation endpoint for backward compatibility
    # This matches the original frontend API call to /api/generate-certificate/
    path("generate-certificate/", generate_certificate_legacy, name="generate-certificate-legacy"),
]

BASE_DIR = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
apps = find_apps(BASE_DIR, exclude_dirs=["backend", "migrations"])

for app in apps:
    try:
        importlib.import_module(f"{app}.urls")  # check if app has urls
        urlpatterns.append(path(f"{app}/", include(f"{app}.urls")))
    except ModuleNotFoundError:
        # silently skip apps without urls.py
        pass
