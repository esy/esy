#! /bin/bash


ENV_FILE="$1"
PATH_FILE="$2"
CMD="$3"

env -i -P $(cat "$PATH_FILE") -S $(cat "$ENV_FILE") bash -c "$CMD"
