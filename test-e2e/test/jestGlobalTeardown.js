const path = require('path');
const del = require('del');

module.exports = async function jestGlobalTeardown(_globalConfig) {
  await del(
    [path.join(global.__TEST_PATH__, '*'), '!' + path.join(global.__TEST_PATH__, 'esy')],
    {force: true},
  );
};
