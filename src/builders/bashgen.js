/**
 * A set of Esy-specific bash generation helpers.
 *
 * @flow
 */

import outdent from 'outdent';
import * as Config from '../build-config';

export const defineScriptDir = outdent`

  #
  # Define $SCRIPTDIR
  #

  SOURCE="\${BASH_SOURCE[0]}"
  while [ -h "$SOURCE" ]; do # resolve $SOURCE until the file is no longer a symlink
    SCRIPTDIR="$( cd -P "$( dirname "$SOURCE" )" && pwd )"
    SOURCE="$(readlink "$SOURCE")"
    [[ $SOURCE != /* ]] && SOURCE="$SCRIPTDIR/$SOURCE" # if $SOURCE was a relative symlink, we need to resolve it relative to the path where the symlink file was located
  done
  SCRIPTDIR="$( cd -P "$( dirname "$SOURCE" )" && pwd )"

`;

export const defineEsyUtil = outdent`

  #
  # Esy utility functions
  #

  esyStrLength() {
    # run in a subprocess to override $LANG variable
    LANG=C /bin/bash -c 'echo "\${#0}"' "$1"
  }

  esyRepeatCharacter() {
    chToRepeat=$1
    times=$2
    printf "%0.s$chToRepeat" $(seq 1 $times)
  }

  esyGetStorePathFromPrefix() {
    ESY_EJECT__PREFIX="$1"
    # Remove trailing slash if any.
    ESY_EJECT__PREFIX="\${ESY_EJECT__PREFIX%/}"
    ESY_STORE_VERSION="${Config.ESY_STORE_VERSION}"

    prefixLength=$(esyStrLength "$ESY_EJECT__PREFIX/$ESY_STORE_VERSION")
    paddingLength=$(expr ${Config.DESIRED_ESY_STORE_PATH_LENGTH} - $prefixLength)

    # Discover how much of the reserved relocation padding must be consumed.
    if [ "$paddingLength" -lt "0" ]; then
      echo "$ESY_EJECT__PREFIX is too deep inside filesystem, Esy won't be able to relocate binaries"
      exit 1;
    fi

    padding=$(esyRepeatCharacter '_' "$paddingLength")
    echo "$ESY_EJECT__PREFIX/$ESY_STORE_VERSION$padding"
  }

`;
