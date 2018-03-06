module.exports = function(babel) {
  var t = babel.types;

  let globalScope = null;

  const visitor = {
    Program({scope}) {
      globalScope = scope;
    },

    CallExpression(path) {
      const {node} = path;
      if (isFsReadFileSync(node.callee)) {
        const filenameNode = node.arguments[0];
        if (t.isCallExpression(filenameNode) && isRequireResolve(filenameNode.callee)) {
          const moduleNode = filenameNode.arguments[0];
          if (t.isStringLiteral(moduleNode)) {
            path.replaceWith(
              t.callExpression(t.identifier('require'), [
                t.stringLiteral(`raw-loader!${moduleNode.value}`),
              ]),
            );
          }
        }
      }
    },
  };

  function isFsReadFileSync(node) {
    return (
      t.isMemberExpression(node) &&
      t.isIdentifier(node.object) &&
      node.object.name === 'fs' &&
      t.isIdentifier(node.property) &&
      node.property.name === 'readFileSync'
    );
  }

  function isRequireResolve(node) {
    return (
      t.isMemberExpression(node) &&
      t.isIdentifier(node.object) &&
      node.object.name === 'require' &&
      t.isIdentifier(node.property) &&
      node.property.name === 'resolve'
    );
  }

  return {
    visitor,
  };
};
