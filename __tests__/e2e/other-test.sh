#!/bin/bash

doTest() {
  # Just a sanity check
  run esy --help
  run esy help
  run esy --version
  run esy version
}
