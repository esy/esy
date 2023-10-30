#! /bin/bash

set -x

ENV_FILE="$1"
PATH_FILE="$2"
CMD="$3"

S_VAL="$(cat "$ENV_FILE") ${CMD}"
env -i -P $(cat "$PATH_FILE") -S "${S_VAL}"
