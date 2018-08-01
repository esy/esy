const path = require("path")
const fs = require("fs")
const os = require("os")

const { bashExec, toCygwinPath } = require("esy-bash")

const rootFolder = path.join(__dirname, "..", "..")
const packageJson = path.join(rootFolder, "package.json")
const packFolder = path.join(rootFolder, "_release")
const destFolder = path.join(rootFolder, "_platformrelease")

const version = require(packageJson).version

const getArch = () => {
    let arch = os.arch() == ("x32" || "ia32") ? "x86" : "x64"

    if (process.env.APPVEYOR) {
        arch = process.env.PLATFORM === "x86" ? "x86" : "x64"
    }

    return arch
}

const arch = getArch();

const bashExecAndThrow = async (command) => {
    const code = await bashExec(command)

    if (code !== 0) {
        throw new Error(`Command: ${command} failed with exit code ${code}`)
    }
}

const pack = async () => {
    // If we pack cygwin + all the installed dependencies, the archive by itself
    // is around 338 MB! If we pack that for both x86 + x64, we'll end up with almost 750 MB.
    // Doesn't seem acceptable for now. The downside is the user will need to download / install
    // cygwin as port of a postinstall step (since `esy-bash` is called out as a dependency,
    // this should happen automatically).
    console.log("Deleting cygwin from release folder...")

    const cygwinDestFolder = await toCygwinPath(destFolder)
    const cygwinPackFolder = await toCygwinPath(packFolder)

    console.log(`- Deleting: ${cygwinPackFolder}/node_modules/esy-bash`)
    await bashExecAndThrow(`rm -rf ${cygwinPackFolder}/node_modules/esy-bash`)

    console.log(`Creating folder: ${cygwinDestFolder}`)
    await bashExecAndThrow(`mkdir ${cygwinDestFolder}`)

    console.log(`Creating archive from ${cygwinPackFolder} in ${cygwinDestFolder}.`)
    await bashExecAndThrow(`tar -czvf ${cygwinDestFolder}/esy-v${version}-windows-${arch}.tgz -C ${cygwinPackFolder} .`)
}

pack()
