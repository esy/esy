# Package Specification Language

Little language to specify packages for esy.

##

Definition site:

```
{
    "name": "ocaml-ios",
    "params": {
        "sdk": {
          "type": "string",
          "required": "boolean",
          "description": "SDK version"
        }
    },
    "build": "make SDK=#{params.sdk}"
}
```

Call site:

```
"dependencies": {
    "ocaml-ios": {
        "version": ">=4.04 <4.05",
        "params": {
            "arch": "amd64",
            "system": "windows",
            "subarch": "x86_64",
            "platform": "iPhoneSimulator",
            "sdk": "12.1",
            "minVer": "11.2",
        }
    }
}
```

# ConfML

Values:
```
{
    name: "package"
    version: "1.0.0"
}
```

Abstraction:
```
let make (sdk: string) = {
    name: "ocaml",
    sdk: sdk,
    build: "make SDK=#{sdk}"
}
```

Abstraction with default params:
```
let make(sdk: string, flambda: bool = false) = {
    name: "ocaml",
    sdk: sdk,
    build: "make SDK=#{sdk} #{flambda ? '--enable-flambda' : ''}"
}
```


Application:
```
{
  dependencies: {
    ocaml: package(version: "4.6.x", sdk: "1.2"),
    "ocaml-ios": package(version: ">=4.04 <4.05", sdk: "1.2")
  }
}
```

Override:
```
{
  ...self,
  name: "freshest",
  dependencies: {
    ...self.dependencies,
    ocaml: package(">=4.07")
  }
}
```

Projection:

```
obj.name
```

```
let pkg = package("*");
{
    name: pkg.name
    version: pkg.version
    dependencies: pkg.dependencies
}
```

## Examples

### Override package with a custom build command

```
{
    ...package("https://github.com/esy-cross/ocaml/archive/1512.zip"),
    build: [
        "make world opt"
    ]
}
```

### Package with params

You define package with params (`package.esy` inside `ocaml@4.07.0`):

```
let make (sdk: string, flambda=false) = {
    name: "ocaml",
    build: "make SDK=#{sdk}"
}
```

You consume package with params:

```
{
    dependencies: {
        ocaml: package(version: "4.07.x", sdk: "1.12", flambda: true)
    }
}
```

## TODO

- Parsing: `string => Syntax.t`
- Printing: `Fmt.t(Syntax.t)`
