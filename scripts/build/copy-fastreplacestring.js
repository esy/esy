const cp = require("child_process");
const fs = require("fs");
const path = require("path");

const command = (c) => {
    console.log("[esy-build] Running command: " + c);
    const out = cp.execSync(c).toString("utf8").trim();
    if (out) {
        console.log("[esy-build] Output: " + out);
    }
    return out;
}

const rootDir = path.join(__dirname, "..", "..", "bin");
const destPath = path.join(rootDir, "fastreplacestring");

const frsPath = command("esy b which fastreplacestring");
console.log(frsPath);
command(`esy b cp "${frsPath}" "${destPath}"`);

if (!fs.existsSync(destPath)) {
    command(`esy b mv "${destPath}.exe" "${destPath}"`)
}
