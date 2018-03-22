#!/bin/bash

echo '#!/bin/bash' >> $1
echo "echo '$SANDBOX_ENV_VAR-in-dep'" >> $1
