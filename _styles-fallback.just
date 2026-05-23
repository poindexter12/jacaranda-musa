# Style variable fallbacks — used when lib/infrastructure/just/styles.just
# can't be loaded (e.g. when the lib/ submodule is not initialized).
#
# Imported AFTER the optional styles.just import with
# `set allow-duplicate-variables := true`. With that setting, the first
# definition wins, so when styles.just is present its real ANSI codes take
# precedence; otherwise these blanks keep recipes parseable.

CYAN := ''
NC := ''
RED := ''
GREEN := ''
YELLOW := ''
BOLD := ''
