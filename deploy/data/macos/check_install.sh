#!/bin/bash
if [ -d "/Applications/Dopamine.app" ] || pgrep -x "lodestar-service" >/dev/null; then
  exit 1
fi
exit 0
