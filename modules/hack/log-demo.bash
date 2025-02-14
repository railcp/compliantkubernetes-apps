#!/bin/bash

set -euo pipefail

here="$(dirname "$(readlink -f "$0")")"

root="${here}/../.."

# "${root}/bin/ck8s" ops helmfile sc diff -l name=module-opensearch --include-transitive-needs --output simple
"${root}/bin/ck8s" ops helmfile sc apply -l name=module-opensearch --include-transitive-needs
