# Musa Project — Production Environment (placeholder)
#
# Production deployment not yet configured.
# When ready, this will mirror the test module with prod-specific values.
#
# Usage: just prod::<recipe>

import 'lib/infrastructure/just/terraform.just'
import 'lib/infrastructure/just/ansible.just'

# Show available recipes for this module
@_default:
    just --list prod
    echo
    echo "Note: production environment not yet configured. Use test:: recipes."
