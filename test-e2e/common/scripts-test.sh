#!/bin/bash

doTest() {
  initFixture ./fixtures/scripts-workflow

  expectStdout "cmd1_result" esy cmd1
  expectStdout "cmd2_result" esy cmd2
  expectStdout "cmd_array_result" esy cmd3
}
