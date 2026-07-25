"""
Project-specific overrides — keep settings.py as a shared template.

• Python section  : extra INSTALLED_APPS, setting overrides, integrations
• Services section: extra Docker Compose services for this project
  (written as YAML in the COMPOSE_SERVICES string below — dev.sh picks it up)
"""
import os


# Python settings ∿∿∿∿∿∿∿∿∿∿∿∿∿∿∿∿∿∿∿∿∿∿∿∿∿∿∿∿∿∿∿∿∿∿∿∿∿∿∿∿∿∿∿∿
#Custom URL prefixes for apps: CUSTOM_URL_PREFIXES = {"myapp": "my-prefix"}

# Stripe
STRIPE_PUBLISHABLE_KEY = os.getenv('STRIPE_PUBLISHABLE_KEY')
STRIPE_SECRET_KEY = os.getenv('STRIPE_SECRET_KEY')
STRIPE_WEBHOOK_SECRET = os.getenv('STRIPE_WEBHOOK_SECRET')

print(f"⊧ STRIPE: {'Test' if os.getenv('DJANGO_DEBUG', 'False').lower() == 'true' else 'Live'} keys configured")


# Compose services ∿∿∿∿∿∿∿∿∿∿∿∿∿∿∿∿∿∿∿∿∿∿∿∿∿∿∿∿∿∿∿∿∿∿∿∿∿∿∿∿∿∿∿
# Extra Docker Compose services merged alongside dev.yml by dev.sh.
#
# Startup logic: add <app>/management/commands/entrypoint.py to any app.
# entrypoint.sh calls `manage.py entrypoint` which Django discovers it automatically.

