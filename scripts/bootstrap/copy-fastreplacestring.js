const path = require("path")
const fs = require("fs")
const os = require("os")

const rootFolder = path.join(__dirname, "..", "..")
const sourceFolder = path.join(rootFolder, "node_modules", "fastreplacestring", ".bin")
const destFolder = path.join(rootFolder, "bin")

const plat = os.arch() === "x64" ? "win64" : "win32"

const sourceFile = path.join(sourceFolder, `fastreplacestring-${plat}.exe`)
const destFile = path.join(destFolder, `fastreplacestring`)

console.log(`Copying ${sourceFile} to ${destFile}... `)
fs.copyFileSync(sourceFile, destFile)
console.log(`Copy complete`)
