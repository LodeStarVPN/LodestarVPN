#!/bin/bash
if [ -d "/Applications/Dopamine.app" ] || pgrep -x "lodestar-service" >/dev/null; then
  exit 0
fi
exit 1
