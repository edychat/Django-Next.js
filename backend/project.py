"""
Project-specific overrides — keep settings.py as a shared template.

• Python section  : extra INSTALLED_APPS, setting overrides, integrations
• Services section: extra Docker Compose services for this project
  (written as YAML in the COMPOSE_SERVICES string below — dev.sh picks it up)
• Sync section    : SYNC_PROJECT_PATHS — auto-discovered, no hardcoding needed.
  dev.sh sync skips these paths when pulling template updates.
"""
import os
from pathlib import Path

_BASE_DIR = Path(__file__).resolve().parent       # backend/
_PROJECT_ROOT = _BASE_DIR.parent                  # repo root


# Python settings ∿∿∿∿∿∿∿∿∿∿∿∿∿∿∿∿∿∿∿∿∿∿∿∿∿∿∿∿∿∿∿∿∿∿∿∿∿∿∿∿∿∿∿∿
# Custom URL prefixes for apps: CUSTOM_URL_PREFIXES = {"myapp": "my-prefix"}

# Stripe
STRIPE_PUBLISHABLE_KEY = os.getenv('STRIPE_PUBLISHABLE_KEY')
STRIPE_SECRET_KEY = os.getenv('STRIPE_SECRET_KEY')
STRIPE_WEBHOOK_SECRET = os.getenv('STRIPE_WEBHOOK_SECRET')

print(f"⊧ STRIPE: {'Test' if os.getenv('DJANGO_DEBUG', 'False').lower() == 'true' else 'Live'} keys configured")


# Sync protection ∿∿∿∿∿∿∿∿∿∿∿∿∿∿∿∿∿∿∿∿∿∿∿∿∿∿∿∿∿∿∿∿∿∿∿∿∿∿∿∿∿∿∿∿
# Auto-discovered — no hardcoding needed.
# Backend : any folder with __init__.py (Django apps), excluding config/
# Mobile  : any folder with package.json under frontend/mobile/, excluding shared/
_MOBILE_SKIP = {'shared', 'node_modules', 'scripts', 'packages'}
_MOBILE_DIR = _PROJECT_ROOT / 'frontend' / 'mobile'

SYNC_PROJECT_PATHS = (
    # All Django apps in backend/
    [
        f"backend/{item}/"
        for item in os.listdir(_BASE_DIR)
        if item != 'config'
        and os.path.isdir(_BASE_DIR / item)
        and os.path.isfile(_BASE_DIR / item / '__init__.py')
    ]
    +
    # All Expo/RN apps in frontend/mobile/
    (
        [
            f"frontend/mobile/{item}/"
            for item in os.listdir(_MOBILE_DIR)
            if item not in _MOBILE_SKIP
            and os.path.isdir(_MOBILE_DIR / item)
            and os.path.isfile(_MOBILE_DIR / item / 'package.json')
        ]
        if _MOBILE_DIR.is_dir() else []
    )
)


# Compose services ∿∿∿∿∿∿∿∿∿∿∿∿∿∿∿∿∿∿∿∿∿∿∿∿∿∿∿∿∿∿∿∿∿∿∿∿∿∿∿∿∿∿∿
# Extra Docker Compose services merged alongside dev.yml by dev.sh.
# Add project-specific services here — dev.yml stays a clean shared template.
#
# Example — mount a large data directory into the frontend container:
#
# COMPOSE_SERVICES = """
# services:
#   frontend:
#     volumes:
#       - ./frontend/web/public/mydata:/app/public/mydata:z,ro
# """
#
# Startup hook: add <app>/management/commands/entrypoint.py to any app.
# entrypoint.sh calls `manage.py entrypoint` — Django auto-discovers it.
