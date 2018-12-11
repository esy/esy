// @flow

const path = require('path');
const fs = require('fs-extra');

const {createTestSandbox, promiseExec, skipSuiteOnWindows} = require('./test/helpers');
const fixture = require('./common/fixture.js');

describe('esy build-plan', () => {
  it('shows build plan in JSON', async () => {
    const p = await createTestSandbox();
    await p.fixture(...fixture.makeSimpleProject(p));

    await p.esy('install');
    await p.esy('build');

    const plan = JSON.parse((await p.esy('build-plan')).stdout);

    expect(plan.name).toBe('simple-project');
  });

  it('shows build plan for a dep (by name)', async () => {
    const p = await createTestSandbox();
    await p.fixture(...fixture.makeSimpleProject(p));

    await p.esy('install');
    await p.esy('build');

    const plan = JSON.parse((await p.esy('build-plan dep')).stdout);
    expect(plan.name).toBe('dep');
  });

  it('shows build plan for a dep (by name)', async () => {
    const p = await createTestSandbox();
    await p.fixture(...fixture.makeSimpleProject(p));

    await p.esy('install');
    await p.esy('build');

    const plan = JSON.parse((await p.esy('build-plan dep@path:dep')).stdout);
    expect(plan.name).toBe('dep');
  });
});
