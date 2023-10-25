#! /bin/bash

INSTALL_PREFIX="$1"

create_install_folder() {
  FOLDER="$1"
  mkdir -p "$INSTALL_PREFIX/$FOLDER"
}

create_install_folder "stublibs"
create_install_folder "share"
create_install_folder "sbin"
create_install_folder "man"
create_install_folder "lib"
create_install_folder "etc"
create_install_folder "bin"
create_install_folder "doc"
create_install_folder "bin"
