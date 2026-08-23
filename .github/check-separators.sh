#!/usr/bin/env bash
# Guard against SILENTLY MERGED documents.
#
# A template that forgets a `---` between two objects renders YAML that is
# perfectly valid -- the two maps merge, last key wins, and one object simply
# ceases to exist. `helm lint` says nothing, `helm template` exits 0, and the
# object is missing from the cluster with no error anywhere. This cost an
# ExternalSecret while aypex-platform was being written.
#
# The invariant: every rendered object contributes exactly one `kind:` line at
# column 0 and one `---` separator. If they disagree, documents merged.
set -euo pipefail

rendered="$1"
seps=$(grep -c '^---$' "$rendered" || true)
kinds=$(grep -c '^kind:' "$rendered" || true)

if [ "$seps" != "$kinds" ]; then
  echo "MERGED DOCUMENTS: $kinds objects but $seps separators in $rendered"
  echo "A template is missing a '---' between two objects."
  exit 1
fi
echo "    $kinds objects, $seps separators — no merged documents"
