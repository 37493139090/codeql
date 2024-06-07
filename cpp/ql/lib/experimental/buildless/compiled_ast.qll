import cpp
import ast_sig

module CompiledAST implements BuildlessASTSig {
  private class SourceLocation extends Location {
    SourceLocation() { not this.hasLocationInfo(_, 0, 0, 0, 0) }
  }

  private Type reachableType(Type type) {
    result = type or
    result = reachableType(type).stripTopLevelSpecifiers() or
    result = reachableType(type).(PointerType).getBaseType() or
    result = reachableType(type).(ReferenceType).getBaseType()
  }

  private newtype TNode =
    // TFunction(SourceLocation loc) { exists(Function f | f.getLocation() = loc) } or
    TStatement(SourceLocation loc) { exists(Stmt s | s.getLocation() = loc) } or
    TDeclaration(SourceLocation loc) { exists(DeclarationEntry decl | decl.getLocation() = loc) } or
    TExpression(SourceLocation loc) { exists(Expr e | e.getLocation() = loc) } or
    TFunctionCallName(SourceLocation loc) { exists(FunctionCall c | c.getLocation() = loc) } or
    TDeclarationType(SourceLocation loc, Type type) {
      // TODO: Avoid template instantiation here
      exists(DeclarationEntry decl |
        decl.getLocation() = loc and not decl.isFromTemplateInstantiation(_)
      |
        type = reachableType(decl.getType())
      )
    } or
    TNamespaceDeclaration(NamespaceDeclarationEntry ns) { any() }

  class Node extends TNode {
    string toString() { result = "node" }

    SourceLocation getLocation() {
      this = TStatement(result) or
      this = TDeclaration(result) or
      this = TExpression(result) or
      this = TFunctionCallName(result) or
      this = TDeclarationType(result, _) or
      result = this.getNamespaceDeclaration().getLocation()
    }

    Stmt getStmt() { this = TStatement(result.getLocation()) }

    Function getFunction() { this = TDeclaration(result.getLocation()) }

    DeclarationEntry getDeclaration() {
      this = TDeclaration(result.getLocation())
      /* or this = TDeclarationType(result.getLocation(), _) */
    }

    NamespaceDeclarationEntry getNamespaceDeclaration() { this = TNamespaceDeclaration(result) }

    Type getType() { this = TDeclarationType(_, result) }

    DeclarationEntry getVariableDeclaration() { this = TDeclarationType(result.getLocation(), _) }

    Expr getExpr() { this = TExpression(result.getLocation()) }

    FunctionCall getFunctionCallName() { this = TFunctionCallName(result.getLocation()) }
  }

  predicate nodeLocation(Node node, Location location) { location = node.getLocation() }

  // Include graph
  predicate userInclude(Node include, string path) { none() }

  predicate systemInclude(Node include, string path) { none() }

  // Functions
  predicate function(Node fn) { exists(fn.getFunction()) }

  predicate functionBody(Node fn, Node body) { body.getStmt() = fn.getFunction().getBlock() }

  predicate functionReturn(Node fn, Node returnType) {
    returnType.getVariableDeclaration() = fn.getDeclaration() and
    fn.getDeclaration().(FunctionDeclarationEntry).getDeclaration().getType() = returnType.getType()
  }

  predicate functionName(Node fn, string name) { name = fn.getFunction().getName() }

  predicate functionParameter(Node fn, int i, Node parameterDecl) {
    functionParameter0(fn, i, parameterDecl) and
    not exists(Node param2 | functionParameter0(fn, i, param2) |
      param2.getLocation().getStartLine() < parameterDecl.getLocation().getStartLine()
    )
  }

  pragma[nomagic]
  private predicate functionParameter0(Node fn, int i, Node parameterDecl) {
    fn.getFunction().getParameter(i).getADeclarationEntry() = parameterDecl.getDeclaration() and
    fn.getLocation().getFile() = parameterDecl.getLocation().getFile() and
    fn.getLocation().getStartLine() <= parameterDecl.getLocation().getStartLine()
  }

  // Statements
  predicate stmt(Node node) { exists(node.getStmt()) }

  predicate blockStmt(Node stmt) { stmt.getStmt() instanceof BlockStmt }

  predicate blockMember(Node stmt, int index, Node child) {
    child.getStmt() = stmt.getStmt().(BlockStmt).getChild(index)
  }

  predicate ifStmt(Node stmt, Node condition, Node thenBranch) { none() }

  predicate ifStmt(Node tmt, Node condition, Node thenBranch, Node elseBranch) { none() }

  predicate whileStmt(Node stmt, Node condition, Node body) { none() }

  predicate doWhileStmt(Node stmt, Node condition, Node body) { none() }

  predicate forStmt(Node stmt, Node init, Node condition, Node update, Node body) { none() }

  predicate exprStmt(Node stmt, Node expr) { none() }

  predicate returnStmt(Node stmt, Node expr) { none() }

  predicate returnVoidStmt(Node stmt) { none() }

  // etc
  // Types
  predicate ptrType(Node node, Node element) {
    exists(PointerType type, Location loc |
      node = TDeclarationType(loc, type) and
      element = TDeclarationType(loc, type.getBaseType())
    )
  }

  predicate refType(Node node, Node element) {
    exists(ReferenceType type, Location loc |
      node = TDeclarationType(loc, type) and
      element = TDeclarationType(loc, type.getBaseType())
    )
  }

  predicate rvalueRefType(Node type, Node element) { none() }

  predicate arrayType(Node type, Node element, Node size) { none() }

  predicate arrayType(Node type, Node element) { none() }

  predicate typename(Node node, string name) {
    name = node.getDeclaration().getDeclaration().(Class).getName() or
    name = node.getType().getName()
  }

  predicate templated(Node node) { none() }

  predicate classOrStructDefinition(Node node) {
    node.getDeclaration().getDeclaration() instanceof Class
  }

  predicate classMember(Node classOrStruct, int child, Node member) {
    classOrStruct.getDeclaration().getDeclaration().(Class).getAMember() =
      member.getDeclaration().getDeclaration() and
    child = 0 and
    classOrStruct.getLocation().getFile() = member.getLocation().getFile() // TODO: Disambiguate
  }

  // Templates
  predicate templateParameter(Node node, int i, Node parameter) { none() }

  predicate typeParameter(Node templateParameter, Node type, Node parameter) { none() }

  predicate typeParameterDefault(Node templateParameter, Node defaultTypeOrValue) { none() }

  // Declarations
  predicate variableDeclaration(Node decl) {
    decl.getDeclaration() instanceof VariableDeclarationEntry
  }

  pragma[nomagic]
  private predicate variableDeclarationType2(Node decl, Node type) {
    decl.getDeclaration() = type.getVariableDeclaration()
  }

  predicate variableDeclarationType(Node decl, Node type) {
    variableDeclarationType2(decl, type) and
    type.getType() = decl.getDeclaration().getType()
  }

  predicate variableDeclarationEntry(Node decl, int index, Node entry) { none() }

  predicate variableDeclarationEntryInitializer(Node entry, Node initializer) { none() }

  predicate variableName(Node decl, string name) {
    decl.getDeclaration().(VariableDeclarationEntry).getName() = name
  }

  predicate ptrEntry(Node entry, Node element) { none() }

  predicate refEntry(Node entry, Node element) { none() }

  predicate rvalueRefEntry(Node entry, Node element) { none() }

  predicate arrayEntry(Node entry, Node element) { none() }

  // Expressions
  predicate expression(Node node) { exists(node.getExpr()) or exists(node.getFunctionCallName()) }

  predicate prefixExpr(Node expr, string operator, Node operand) { none() }

  predicate postfixExpr(Node expr, Node operand, string operator) { none() }

  predicate binaryExpr(Node expr, Node lhs, string operator, Node rhs) { none() }

  predicate castExpr(Node expr, Node type, Node operand) { none() }

  predicate callExpr(Node call) { call.getExpr() instanceof Call }

  predicate callArgument(Node call, int i, Node arg) {
    arg.getExpr() = call.getExpr().(Call).getArgument(i)
  }

  predicate callReceiver(Node call, Node receiver) {
    receiver.getFunctionCallName() = call.getExpr()
  }

  predicate accessExpr(Node expr, string name) {
    expr.getExpr().(VariableAccess).getTarget().getName() = name or
    expr.getFunctionCallName().getTarget().getName() = name
  }

  predicate literal(Node expr, string value) { expr.getExpr().(Literal).toString() = value }

  predicate stringLiteral(Node expr, string value) {
    expr.getExpr().(StringLiteral).getValue() = value
  }

  predicate type(Node node) { node = TDeclarationType(_, _) }

  predicate constType(Node node, Node element) {
    exists(SpecifiedType type, Location loc |
      node = TDeclarationType(loc, type) and
      element = TDeclarationType(loc, type.getBaseType()) and
      type.isConst()
    )
  }

  predicate namespace(Node ns) { exists(ns.getNamespaceDeclaration()) }

  predicate namespaceName(Node ns, string name) {
    ns.getNamespaceDeclaration().getNamespace().getName() = name
  }

  predicate namespaceMember(Node ns, Node member) {
    (
      member.getDeclaration().getDeclaration() =
        ns.getNamespaceDeclaration().getNamespace().getADeclaration()
      or
      ns.getNamespaceDeclaration().getNamespace().getAChildNamespace() =
        member.getNamespaceDeclaration().getNamespace()
    ) and
    ns.getLocation().getFile() = member.getLocation().getFile()
  }

  predicate edge(Node parent, int index, Node child) {
    namespaceMember(parent, child) and index = 0
    or
    classMember(parent, index, child)
    or
    blockMember(parent, index, child)
  }
}
