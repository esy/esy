var path = require('path');
var fs = require('fs');
var platform = process.platform;

switch (platform) {
  case 'linux':
  case 'darwin':
    fs.renameSync(
      path.join(__dirname, '..', 'platform-' + platform, '_build'),
      path.join(__dirname, '..', '_build')
    );
    break;
  default:
    console.warn("error: no release built for the " + platform + " platform");
    process.exit(1);
}
