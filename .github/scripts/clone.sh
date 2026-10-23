#!/usr/bin/env bash
# Shallow clone, retried.
#
# actions/checkout retries a failed fetch three times; a plain `git clone` does
# not, and a transient failure fails the job. The clones in this workflow all
# land outside the workspace, which actions/checkout refuses, so they get the
# retry from here instead.
#
# Usage: clone.sh <url> <directory>
set -euo pipefail

url=$1
dir=$2
attempts=3

for attempt in $(seq "$attempts"); do
  if git clone --depth 1 "$url" "$dir"; then
    exit 0
  fi

  if [ "$attempt" -eq "$attempts" ]; then
    echo "::error::Could not clone $url after $attempt attempts"
    exit 1
  fi

  # A partial clone would make the next attempt fail on a non-empty directory.
  rm -rf "$dir"
  echo "Clone of $url failed, retrying in 15 seconds"
  sleep 15
done
