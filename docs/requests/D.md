# Requests for agent D

## The storage folder literal

`src/games/MM2.luau:1825` hard-codes `local OUTPUT_ROOT: string =
"RandomTestingMenu0001"`, a second copy of the shell's storage folder. It is
correct today only by coincidence.

The shell now publishes the product's identity as one table. Read the folder
from the host instead of retyping it: `host.PRODUCT.storageFolder`.

The folder name itself does not change with the rename. It is not branding — it
is a directory that already holds every existing player's saved configs, and
renaming it would silently orphan all of them.
