/**
 * Command expressions.
 *
 * Commands expressions are meant to be embedded inside JSON syntax thereforce
 * their syntax is designed not to requied escaping from JSON syntax.
 *
 * export MERLIN_VIM_PLUGIN="#{@opam/merlin.share / 'vim'}"
 * export PATH="#{cur.bin : $PATH}"
 *
 * @flow
 */

type Evaluator = {
  /**
   * Eval identifier to string
   */
  id(id: Array<string>): string,

  /**
   * Eval env var
   */
  var(name: string): string,

  /**
   * Eval path separator
   */
  pathSep(): string,

  /**
   * Eval colon
   */
  colon(): string,
};

const dummyEvaluator: Evaluator = {
  id: id => `ID(${id.join('.')})`,
  var: name => `VAR(${name})`,
  pathSep: () => '/',
  colon: () => ':',
};

export function evaluate(expr: string, evaluator?: Evaluator = dummyEvaluator): string {
  const tokens = tokenizeCover(expr);
  const stack = [{type: 'value', children: []}];

  function cur() {
    const last = stack[stack.length - 1];
    return last;
  }

  while (tokens.length > 0) {
    const tok = tokens.shift();
    if (tok.type === 'SHARP_LPAREN') {
      stack.push({type: 'expression', children: []});
      continue;
    } else if (tok.type === 'DOLLAR_LPAREN') {
      cur().children.push('${');
      stack.push({type: 'var', children: []});
      continue;
    } else if (tok.type === 'RPAREN') {
      const c = cur();
      if (c.type === 'expression') {
        const result = evaluateExpr(stack.pop().children.join(''), evaluator);
        cur().children.push(result);
      } else if (c.type === 'var') {
        c.children.push('}');
        const result = stack.pop().children.join('');
        cur().children.push(result);
      } else {
        c.children.push('}');
      }
    } else {
      cur().children.push(tok.value);
    }
  }

  if (stack.length !== 1) {
    throw new Error(`invalid command expression: ${expr}`);
  }

  return stack[0].children.join('');
}

function evaluateExpr(expr, evaluator) {
  const tokens = tokenize(expr);
  const result = [null];

  const nextTok = () => {
    const tok = tokens.shift();
    return tok;
  };

  const peekTok = () => {
    const tok = tokens[0] || TOK_EOF;
    return tok;
  };

  while (tokens.length > 0) {
    const tok = nextTok();
    if (tok.type === 'COLON') {
      result.push(evaluator.colon());
    } else if (tok.type === 'SLASH') {
      result.push(evaluator.pathSep());
    } else if (tok.type === 'VALUE') {
      result.push(tok.value);
    } else if (tok.type === 'VAR') {
      result.push(evaluator.var(tok.name));
    } else if (tok.type === 'ID') {
      let id = [tok.id];
      while (peekTok().type === 'DOT') {
        nextTok();
        const tok = nextTok();
        if (typeof tok !== 'string' && tok.type !== 'ID') {
          throw new Error('invalid identifier');
        }
        id.push(tok.id);
      }
      result.push(evaluator.id(id));
    } else {
      throw new Error('invalid expression');
    }
  }

  if (peekTok().type !== 'EOF') {
    throw new Error('invalid expression');
  }

  return result.join('');
}

type CoverTokValue = {type: 'VALUE', value: string};
type CoverTokSharpLParen = {type: 'SHARP_LPAREN'};
type CoverTokDollarLParen = {type: 'DOLLAR_LPAREN'};
type CoverTokRParen = {type: 'RPAREN'};
type CoverTok =
  | CoverTokValue
  | CoverTokSharpLParen
  | CoverTokDollarLParen
  | CoverTokRParen;

function tokenizeCover(input: string): Array<CoverTok> {
  const tokens = [];
  let index = 0;

  while (index < input.length) {
    if (input[index] === '#' && input[index + 1] === '{') {
      tokens.push({type: 'SHARP_LPAREN'});
      index = index + 2;
    } else if (input[index] === '$' && input[index + 1] === '{') {
      tokens.push({type: 'DOLLAR_LPAREN'});
      index = index + 2;
    } else if (input[index] === '}') {
      tokens.push({type: 'RPAREN'});
      index = index + 1;
    } else {
      const findOtherTok = /#{|\${|}/g;
      findOtherTok.lastIndex = index;
      const match = findOtherTok.exec(input);
      if (match != null) {
        tokens.push({type: 'VALUE', value: input.slice(index, match.index)});
        index = match.index;
        continue;
      } else {
        tokens.push({type: 'VALUE', value: input.slice(index)});
        break;
      }
    }
  }

  return tokens;
}

type TokColon = {type: 'COLON'};
type TokSlash = {type: 'SLASH'};
type TokDot = {type: 'DOT'};
type TokValue = {type: 'VALUE', value: string};
type TokId = {type: 'ID', id: string};
type TokVar = {type: 'VAR', name: string};
type Tok = TokColon | TokSlash | TokDot | TokValue | TokId | TokVar;

const TOK_COLON = {type: 'COLON'};
const TOK_SLASH = {type: 'SLASH'};
const TOK_DOT = {type: 'DOT'};
const TOK_EOF = {type: 'EOF'};

function tokenize(input: string): Array<Tok> {
  const tokens = [];
  let index = 0;

  function match(re) {
    re.lastIndex = index;
    let m = re.exec(input);
    if (m != null && m.index !== index) {
      m = null;
    }
    re.lastIndex = 0;
    return m;
  }

  function findMatch(re) {
    re.lastIndex = index;
    let m = re.exec(input);
    re.lastIndex = 0;
    return m;
  }

  while (index < input.length) {
    if (input[index] === "'") {
      index = index + 1;
      const m = findMatch(/'/g);
      if (m == null) {
        throw new Error("Expected '");
      }
      tokens.push({type: 'VALUE', value: input.slice(index, m.index)});
      index = m.index + m[0].length;
    } else if (input[index] === '$') {
      index = index + 1;
      const m = findMatch(/[^a-zA-Z0-9_]/g);
      if (m == null) {
        tokens.push({type: 'VAR', name: input.slice(index)});
        break;
      } else {
        tokens.push({type: 'VAR', name: input.slice(index, m.index)});
        index = m.index;
        continue;
      }
    } else if (input[index] === '/') {
      tokens.push(TOK_SLASH);
      index = index + 1;
    } else if (input[index] === '.') {
      tokens.push(TOK_DOT);
      index = index + 1;
    } else if (input[index] === ':') {
      tokens.push(TOK_COLON);
      index = index + 1;
    } else {
      let m;
      const id = /[a-zA-Z0-9_\-]+/g;
      const scopedId = /@[a-zA-Z0-9_\-]+\/[a-zA-Z0-9_\-]+/g;
      const space = /\s+/g;

      if ((m = match(space))) {
        index = index + m[0].length;
      } else if ((m = match(scopedId))) {
        tokens.push({type: 'ID', id: m[0]});
        index = index + m[0].length;
        continue;
      } else if ((m = match(id))) {
        tokens.push({type: 'ID', id: m[0]});
        index = index + m[0].length;
        continue;
      }
    }
  }

  return tokens;
}
