const path = require('path');
const fs = require('fs');
const os = require('os');
const mkdirp = require('mkdirp');

const {bashExec, toCygwinPath} = require('esy-bash');

const rootFolder = path.join(__dirname, '..', '..');
const buildFolder = path.join(rootFolder, '_build');
const packageJson = path.join(rootFolder, 'package.json');
const destFolder = path.join(rootFolder, '_staging');
const platformReleaseFolder = path.join(rootFolder, '_platformrelease');

const version = require(packageJson).version;

const getArch = () => {
  let arch = os.arch() == ('x32' || 'ia32') ? 'x86' : 'x64';

  if (process.env.APPVEYOR) {
    arch = process.env.PLATFORM === 'x86' ? 'x86' : 'x64';
  }

  return arch;
};

const arch = getArch();

const bashExecAndThrow = async command => {
  const code = await bashExec(command);

  if (code !== 0) {
    throw new Error(`Command: ${command} failed with exit code ${code}`);
  }
};

const copy = async (srcFile, destFile) => {
  mkdirp.sync(path.dirname(destFile));
  await bashExecAndThrow(`cp "${srcFile}" "${destFile}"`);
};

const pack = async () => {
  // If we pack cygwin + all the installed dependencies, the archive by itself
  // is around 338 MB! If we pack that for both x86 + x64, we'll end up with almost 750 MB.
  // Doesn't seem acceptable for now. The downside is the user will need to download / install
  // cygwin as port of a postinstall step (since `esy-bash` is called out as a dependency,
  // this should happen automatically).
  console.log('Deleting cygwin from release folder...');

  await copy(
    path.join(buildFolder, 'default', 'bin', 'esy.exe'),
    path.join(destFolder, '_build', 'default', 'bin', 'esy.exe')
  );
  await copy(
    path.join(
      buildFolder,
      'default',
      'esy-build-package',
      'bin',
      'esyBuildPackageCommand.exe'
    ),
    path.join(
      destFolder,
      '_build',
      'default',
      'esy-build-package',
      'bin',
      'esyBuildPackageCommand.exe'
    )
  );
  await copy(
    path.join(
      buildFolder,
      'default',
      'esy-build-package',
      'bin',
      'esyRewritePrefixCommand.exe'
    ),
    path.join(
      destFolder,
      '_build',
      'default',
      'esy-build-package',
      'bin',
      'esyRewritePrefixCommand.exe'
    )
  );

  const cygwinDestFolder = await toCygwinPath(destFolder);
  const cygwinPlatformReleaseFolder = await toCygwinPath(platformReleaseFolder);

  mkdirp.sync(platformReleaseFolder);

  console.log(
    `Creating archive from ${cygwinDestFolder} in ${cygwinPlatformReleaseFolder}`
  );
  await bashExecAndThrow(
    `tar -czvf ${cygwinPlatformReleaseFolder}/esy-v${version}-windows-${arch}.tgz -C ${cygwinDestFolder} .`
  );
};

pack();
