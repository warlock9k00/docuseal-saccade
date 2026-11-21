#!/bin/sh
# How Saccade runs this version: the official image docuseal/docuseal:3.3.8
# plus the three changed view files from this branch, mounted read-only.
# Values in <...> are placeholders; no secrets are needed here
# (DocuSeal keeps its own SECRET_KEY_BASE in the data volume).
DOCUSEAL_SRC=<path to a checkout of this branch>
docker run -d --name docuseal --restart unless-stopped \
  --memory 1g --memory-swap 1g \
  --log-opt max-size=10m --log-opt max-file=3 \
  -p 127.0.0.1:3000:3000 \
  -e HOST=<your host> -e FORCE_SSL=true \
  -v <data dir>:/data \
  -v "$DOCUSEAL_SRC/app/views/submit_form/_docuseal_logo.html.erb:/app/app/views/submit_form/_docuseal_logo.html.erb:ro" \
  -v "$DOCUSEAL_SRC/app/views/start_form/_docuseal_logo.html.erb:/app/app/views/start_form/_docuseal_logo.html.erb:ro" \
  -v "$DOCUSEAL_SRC/app/views/shared/_mailer_attribution.html.erb:/app/app/views/shared/_mailer_attribution.html.erb:ro" \
  docuseal/docuseal:3.3.8
