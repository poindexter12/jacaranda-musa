# Musa Project — Production Environment (placeholder)
#
# Production deployment not yet configured.
# When ready, this will mirror the test module with prod-specific values.
#
# Usage: just prod::<recipe>

import '../../infrastructure/just/terraform.just'
import '../../infrastructure/just/ansible.just'

# Show placeholder message
@_default:
    echo "Production environment not yet configured. Use test:: recipes."
