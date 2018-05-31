#!/bin/bash

doTest() {
  initFixture ./fixtures/scripts-workflow

  run esy build

  expectStdout "cmd1_result" esy cmd1
  expectStdout "cmd2_result" esy cmd2
  expectStdout "cmd_array_result" esy cmd3
  runAndExpectFailure esy b cmd1
  runAndExpectFailure esy x cmd1

  expectStdout "script_exec_result" esy exec_cmd1
  expectStdout "script_exec_result" esy exec_cmd2

  expectStdout "build_cmd_result" esy build_cmd
}
