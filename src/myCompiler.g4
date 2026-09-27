grammar myCompiler;

options {
language = Java;
}

@header {
    import java.util.HashMap;
    import java.util.ArrayList;
    import java.util.Stack;
}

@members {
    // ----- Type information.
    public enum Type {
        ERR, INT, FLOAT, VOID, CONST_INT, CONST_FLOAT
    }

    // ----- Record variable information.
    class tVar {
        int   varIndex; // temporary variable's index. Ex: %1, %2, ..., etc.
        String globalName; // global variable name. Ex: @a, @str0, etc. 
        int   iValue;   // value of constant integer. Ex: 123.
        float fValue;   // value of constant floating point. Ex: 2.314.
    };

    // ----- Record symbol information.
    class Info {
        Type theType;  // type information.
        tVar theVar;
        boolean isArray;
        boolean isGlobal;
        int arraySize;
        
        Info() {
            theType = Type.ERR;
            theVar = new tVar();
            isArray = false;
            isGlobal = false;
            arraySize = 0;
        }
    };

    // ----- SymtabStack: push into another level when entering a block
    ArrayList<HashMap<String, Info>> symtabStack = initSymtabStack();

    ArrayList<HashMap<String, Info>> initSymtabStack() {
        ArrayList<HashMap<String, Info>> stack = new ArrayList<HashMap<String, Info>>();
        stack.add(new HashMap<String, Info>());
        return stack;
    }

    void pushScope() {
        symtabStack.add(new HashMap<String, Info>());
        scopeLevel++;
    }

    void popScope() {
        symtabStack.remove(symtabStack.size() - 1);
        scopeLevel--;
    }

    // Check whether redeclared the current scope
    boolean isDeclaredInCurrentScope(String name) {
        return symtabStack.get(scopeLevel).containsKey(name);
    }

    // Store variable in the current scope
    void addSymbol(String name, Info info) {
        symtabStack.get(scopeLevel).put(name, info);
    }

    // Store function name in the global scope
    void addGlobalSymbol(String name, Info info) {
        symtabStack.get(0).put(name, info);
    }

    // Find variable from the current scope to global scope
    Info getSymbol(String name) {
        for (int i = scopeLevel; i >= 0; i--) {
            if (symtabStack.get(i).containsKey(name)) {
                return symtabStack.get(i).get(name);
            }
        }
        return null;
    }

    // ----- Code generation state
    ArrayList<Info> currentFuncParams = new ArrayList<Info>();

    int labelCount = 1; // For condition label.
    int varCount = 1;   // For variable name.
    int scopeLevel = 0; // For scope level tracking.
    int strCount = 0;   // For string literal naming.

    // ----- Boolean to check prologus.
    boolean usePrintf = false;
    boolean useScanf = false;
    boolean useConcat = false;

    // ----- Record all assembly instructions.
    ArrayList<String> TextCode = new ArrayList<String>();
    ArrayList<String> GlobalStrings = new ArrayList<String>();

    // ----- Support nesting for Break and Continue.
    Stack<String> _continueLabelStack = new Stack<String>();
    Stack<String> _breakLabelStack = new Stack<String>();

    ArrayList<Info> _printfArgs = new ArrayList<Info>();
    ArrayList<String> _forPostCode = new ArrayList<String>();

    // Helpers
    int newVar()       { return varCount++; }
    String newLabel()  { labelCount++; return "L" + labelCount; }

    public ArrayList<String> getTextCode() { return TextCode; }

    // ----- Used for final output.
    public ArrayList<String> getFinalCode() {
        ArrayList<String> full = new ArrayList<String>();
        
        if (usePrintf) full.add("declare i32 @printf(i8* noundef, ...)");
        if (useScanf)  full.add("declare i32 @scanf(i8* noundef, ...)");
        if (useConcat) full.add("declare float @__concat_float(float, float)");
        
        if (usePrintf || useScanf || useConcat) full.add("");

        for (String gs : GlobalStrings) full.add(gs);
        if (!GlobalStrings.isEmpty()) full.add("");

        full.addAll(TextCode);
        return full;
    }

    // Type utilities
    String llvmType(Type t) {
        if (t == Type.VOID) return "void";
        if (t == Type.FLOAT || t == Type.CONST_FLOAT) return "float";
        return "i32";
    }

    Type baseType(Type t) {
        if (t == Type.CONST_INT)   return Type.INT;
        if (t == Type.CONST_FLOAT) return Type.FLOAT;
        return t;
    }

    // ----- Change floating-point values to double
    String getLLVMFloat(float f) {
        double d = (double) f;
        long bits = Double.doubleToRawLongBits(d);
        return String.format("0x%016X", bits);
    }

    // ----- Materialize a constant into an actual LLVM register
    Info materialize(Info src) {
        if (src.theType == Type.CONST_INT) {
            int idx = newVar();
            TextCode.add("  %" + idx + " = add nsw i32 0, " + src.theVar.iValue);
            Info r = new Info(); r.theType = Type.INT; r.theVar.varIndex = idx;
            return r;
        }
        if (src.theType == Type.CONST_FLOAT) {
            int idx = newVar();
            TextCode.add("  %" + idx + " = fadd float 0.0, " + getLLVMFloat(src.theVar.fValue));
            Info r = new Info(); r.theType = Type.FLOAT; r.theVar.varIndex = idx;
            return r;
        }
        return src;
    }


    // ----- BONUS: Promote to float register
    Info toFloat(Info src) {
        if (src.theType == Type.FLOAT)       return src;
        if (src.theType == Type.CONST_FLOAT) return materialize(src);
        int idx = newVar();
        if (src.theType == Type.CONST_INT)
            TextCode.add("  %" + idx + " = sitofp i32 " + src.theVar.iValue + " to float");
        else
            TextCode.add("  %" + idx + " = sitofp i32 %" + src.theVar.varIndex + " to float");
        Info r = new Info(); r.theType = Type.FLOAT; r.theVar.varIndex = idx;
        return r;
    }

    // ----- Binary arithmetic  (+, -, *, /, %)
    Info emitBinop(String op, Info a, Info b) {
        boolean isFloat = (baseType(a.theType) == Type.FLOAT || baseType(b.theType) == Type.FLOAT);
        
        Info r = new Info();

        if (isFloat) {
            Info ra = toFloat(a);
            Info rb = toFloat(b);
            
            int idx = newVar();
            String instr;
            switch (op) {
                case "+": instr = "fadd"; break;
                case "-": instr = "fsub"; break;
                case "*": instr = "fmul"; break;
                case "/": instr = "fdiv"; break;
                default:  instr = "fadd"; break;
            }
            TextCode.add("  %" + idx + " = " + instr + " float %" + ra.theVar.varIndex
                         + ", %" + rb.theVar.varIndex);
                         
            r.theType = Type.FLOAT;
            r.theVar.varIndex = idx;
        } else {
            int idx = newVar();  
            String valA = (a.theType == Type.CONST_INT) ? String.valueOf(a.theVar.iValue) : "%" + a.theVar.varIndex;
            String valB = (b.theType == Type.CONST_INT) ? String.valueOf(b.theVar.iValue) : "%" + b.theVar.varIndex;

            String instr;
            switch (op) {
                case "+": instr = "add nsw"; break;
                case "-": instr = "sub nsw"; break;
                case "*": instr = "mul nsw"; break;
                case "/": instr = "sdiv";    break;
                case "%": instr = "srem";    break;
                default:  instr = "add nsw"; break;
            }
            TextCode.add("  %" + idx + " = " + instr + " i32 " + valA + ", " + valB);
                         
            r.theType = Type.INT;
            r.theVar.varIndex = idx;
        }
        return r;
    }


    // ## operator: Let the function call be @__concat_float
    Info emitConcatOp(Info a, Info b) {
        useConcat = true;
        Info fa = toFloat(a);
        Info fb = toFloat(b);
        int idx = newVar();
        TextCode.add("  %" + idx + " = call float @__concat_float(float %"
                    + fa.theVar.varIndex + ", float %" + fb.theVar.varIndex + ")");
        Info r = new Info(); r.theType = Type.FLOAT; r.theVar.varIndex = idx;
        return r;
    }

    // Comparison
    int emitCmp(String op, Info a, Info b) {
        boolean isFloat = (baseType(a.theType) == Type.FLOAT || baseType(b.theType) == Type.FLOAT);

        if (isFloat) {
            Info ra = toFloat(a);
            Info rb = toFloat(b);
            
            int idx = newVar(); 
            String cond;
            switch (op) {
                case ">":  cond = "ogt"; break;
                case ">=": cond = "oge"; break;
                case "<":  cond = "olt"; break;
                case "<=": cond = "ole"; break;
                case "==": cond = "oeq"; break;
                case "!=": cond = "one"; break;
                default:   cond = "oeq"; break;
            }
            TextCode.add("  %" + idx + " = fcmp " + cond + " float %" + ra.theVar.varIndex
                         + ", %" + rb.theVar.varIndex);
            return idx;
        } else {
            int idx = newVar(); 
            String valA = (a.theType == Type.CONST_INT) ? String.valueOf(a.theVar.iValue) : "%" + a.theVar.varIndex;
            String valB = (b.theType == Type.CONST_INT) ? String.valueOf(b.theVar.iValue) : "%" + b.theVar.varIndex;
            
            String cond;
            switch (op) {
                case ">":  cond = "sgt"; break;
                case ">=": cond = "sge"; break;
                case "<":  cond = "slt"; break;
                case "<=": cond = "sle"; break;
                case "==": cond = "eq";  break;
                case "!=": cond = "ne";  break;
                default:   cond = "eq";  break;
            }
            TextCode.add("  %" + idx + " = icmp " + cond + " i32 " + valA + ", " + valB);
            return idx;
        }
    }

    // ----- printf / scanf
    int computeStrLen(String s) {
        int len = 0;
        for (int i = 0; i < s.length(); i++) {
            if (s.charAt(i) == '\\') i++; 
            len++;
        }
        return len;
    }

    String registerString(String raw) {
        String content = raw.substring(1, raw.length() - 1);
        String llvmContent = content.replace("\\n", "\\0A");
        
        String name = "@.str" + (strCount == 0 ? "" : "." + strCount); 
        strCount++;

        int len = computeStrLen(content) + 1;
        
        GlobalStrings.add(name + " = private unnamed_addr constant [" + len + " x i8] c\"" + llvmContent + "\\00\", align 1");
        return name;
    }


    int emitStrPtr(String gName, int byteLen) {
        int ptrIdx = newVar();
        TextCode.add("  %" + ptrIdx + " = getelementptr inbounds [" + byteLen + " x i8], [" + byteLen + " x i8]* " 
                    + gName + ", i32 0, i32 0");
        return ptrIdx;
    }
}


// 1. program  →  declaration-list 
program
    : declaration_list EOF
    ;

// 2. declaration-list  →  declaration-list  declaration  |  declaration 
declaration_list
    : (declaration)*
    ;

// 3. declaration  →  var-declaration  |  fun-declaration 
declaration
    : var_declaration 
    | fun_declaration
    ;

// 4. var-declaration  →  type-specifier  ID ;  |  type-specifier  ID [ Integer ] ; 
    // * Added more declaration types: type-specifier  ID = expression ;  |  type-specifier  ID [ Integer ] = { init-list } 
var_declaration
@init { Type t = Type.ERR; }
    : type_specifier { t = $type_specifier.attr_type; }
    dec_item[t] ( COMMA dec_item[t] )* SEMICOLON
    ;

dec_item [Type attr_type]
    : ID
    {
        if (isDeclaredInCurrentScope($ID.text)) {
            System.out.println("=== Error === " + $ID.line + ": Redeclared identifier.");
        } else {
            Info e = new Info();
            e.theType = $attr_type;
            
            if (scopeLevel == 0) {
                e.isGlobal = true;
                e.theVar.globalName = "@" + $ID.text;
                addSymbol($ID.text, e);
                String lt = llvmType(e.theType);
                String initVal = (e.theType == Type.FLOAT) ? "0.0" : "0";
                GlobalStrings.add(e.theVar.globalName + " = dso_local global " + lt + " " + initVal + ", align 4");
            } else {
                e.isGlobal = false;
                e.theVar.varIndex = newVar();
                addSymbol($ID.text, e);
                String lt = llvmType(e.theType);
                TextCode.add("  %" + e.theVar.varIndex + " = alloca " + lt + ", align 4");
            }
        }
    }
    | ID ASS_OP expression
    {
        if (isDeclaredInCurrentScope($ID.text)) {
            System.out.println("=== Error === " + $ID.line + ": Redeclared identifier.");
        } else {
            Info e = new Info();
            e.theType = $attr_type;
            
            if (scopeLevel == 0) {
                e.isGlobal = true;
                e.theVar.globalName = "@" + $ID.text;
                addSymbol($ID.text, e);
                String lt = llvmType(e.theType);
                
                String initVal = (e.theType == Type.FLOAT) ? "0.0" : "0";
                if ($expression.theInfo.theType == Type.CONST_INT) {
                    initVal = String.valueOf($expression.theInfo.theVar.iValue);
                } else if ($expression.theInfo.theType == Type.CONST_FLOAT) {
                    initVal = getLLVMFloat($expression.theInfo.theVar.fValue);
                }
                GlobalStrings.add(e.theVar.globalName + " = dso_local global " + lt + " " + initVal + ", align 4");
            } else {
                e.isGlobal = false;
                e.theVar.varIndex = newVar();
                addSymbol($ID.text, e);
                String lt = llvmType(e.theType);
                
                TextCode.add("  %" + e.theVar.varIndex + " = alloca " + lt + ", align 4");
                
                Info rhs = $expression.theInfo;
                String ptrStr = "%" + e.theVar.varIndex;
                
                if (e.theType == Type.INT) {
                    if (baseType(rhs.theType) == Type.FLOAT) {
                        Info rf = toFloat(rhs);
                        int fi = newVar();
                        TextCode.add("  %" + fi + " = fptosi float %" + rf.theVar.varIndex + " to i32");
                        TextCode.add("  store i32 %" + fi + ", " + lt + "* " + ptrStr + ", align 4");
                    } else if (rhs.theType == Type.CONST_INT) {
                        TextCode.add("  store i32 " + rhs.theVar.iValue + ", " + lt + "* " + ptrStr + ", align 4");
                    } else {
                        rhs = materialize(rhs);
                        TextCode.add("  store i32 %" + rhs.theVar.varIndex + ", " + lt + "* " + ptrStr + ", align 4");
                    }
                } else if (e.theType == Type.FLOAT) {
                    if (rhs.theType == Type.CONST_FLOAT) {
                        TextCode.add("  store float " + getLLVMFloat(rhs.theVar.fValue) + ", " + lt + "* " + ptrStr + ", align 4");
                    } else {
                        Info rf = toFloat(rhs);
                        TextCode.add("  store float %" + rf.theVar.varIndex + ", " + lt + "* " + ptrStr + ", align 4");
                    }
                }
            }
        }
    }
    | ID LS_SY DEC_NUM RS_SY ( ASS_OP LB_SY il=init_list RB_SY )?
    {
        if (isDeclaredInCurrentScope($ID.text)) {
            System.out.println("=== Error === " + $ID.line + ": Redeclared identifier.");
        } else {
            Info e = new Info();
            e.theType         = $attr_type;
            e.isArray         = true;
            
            int sz = Integer.parseInt($DEC_NUM.text);
            e.arraySize = sz; 
            
            if (scopeLevel == 0) {
                e.isGlobal = true;
                e.theVar.globalName = "@" + $ID.text;
                addSymbol($ID.text, e);
                String lt = llvmType(e.theType);
                
                String initStr = "zeroinitializer";
                if ($il.ctx != null && $il.code != null) { 
                    initStr = "[" + $il.code + "]";
                }
                GlobalStrings.add(e.theVar.globalName + " = dso_local global [" + sz + " x " + lt + "] " + initStr + ", align 4");
            } else {
                e.isGlobal = false;
                e.theVar.varIndex = newVar();
                addSymbol($ID.text, e);
                String lt = llvmType(e.theType);
                TextCode.add("  %" + e.theVar.varIndex + " = alloca [" + sz + " x " + lt + "], align 4");
            }
        }
    }
    ;

// Array initialize
init_list returns [String code]
@init { $code = ""; }
    : e1=expression 
    {
        String lt = llvmType($e1.theInfo.theType);
        $code = lt + " " + $e1.theInfo.theVar.iValue;
    }
    ( COMMA e2=expression 
        {
        String lt2 = llvmType($e2.theInfo.theType);
        $code += ", " + lt2 + " " + $e2.theInfo.theVar.iValue;
        }
    )*
    ;

// 5. type-specifier  →  int  |  void  |  float 
type_specifier returns [Type attr_type]
    : INT_TYPE   { $attr_type = Type.INT; }
    | FLOAT_TYPE { $attr_type = Type.FLOAT; }
    | VOID_TYPE  { $attr_type = Type.VOID; }
    ;

// 6. fun-declaration → type_specifier ID ( params ) compound_stmt
fun_declaration
    : type_specifier ID LP_SY 
    {
        Info f = new Info();
        f.theType = $type_specifier.attr_type;
        f.isGlobal = true;
        addGlobalSymbol($ID.text, f); 
        pushScope(); 
        varCount = 0; 
        currentFuncParams.clear(); 
    }
    params RP_SY
    {
        varCount++; 
        String lt = llvmType($type_specifier.attr_type);
        TextCode.add("define dso_local " + lt + " @" + $ID.text + "(" + $params.code + ") {");
        
        for (int i = 0; i < currentFuncParams.size(); i++) {
            Info p = currentFuncParams.get(i);
            p.theVar.varIndex = newVar(); 
            String plt = llvmType(p.theType);
            TextCode.add("  %" + p.theVar.varIndex + " = alloca " + plt + ", align 4");
            TextCode.add("  store " + plt + " %" + i + ", " + plt + "* %" + p.theVar.varIndex + ", align 4");
        }

        if ($ID.text.equals("main") && $type_specifier.attr_type != Type.VOID) {
            int retIdx = newVar(); 
            TextCode.add("  %" + retIdx + " = alloca " + lt + ", align 4");
            String initVal = ($type_specifier.attr_type == Type.FLOAT) ? "0.0" : "0";
            TextCode.add("  store " + lt + " " + initVal + ", " + lt + "* %" + retIdx + ", align 4");
        }
    }
    compound_stmt
    {
        popScope(); 
        
        if (!TextCode.isEmpty()) {
            String lastInst = TextCode.get(TextCode.size() - 1).trim();
            if (!lastInst.startsWith("ret") && !lastInst.startsWith("br")) {
                if ($type_specifier.attr_type == Type.VOID) {
                    TextCode.add("  ret void");
                } else if ($type_specifier.attr_type == Type.INT) {
                    TextCode.add("  ret i32 0");
                } else if ($type_specifier.attr_type == Type.FLOAT) {
                    TextCode.add("  ret float 0.0");
                }
            }
        }
        TextCode.add("}");
    }
    ;

// 7. params → param-list  |  void  |  empty
params returns [String code]
@init { $code = ""; }
    : param_list { $code = $param_list.code; }
    | VOID_TYPE 
    | /* empty */ 
    ;

// 8. param-list → param  |  param-list , param
param_list returns [String code]
@init { $code = ""; }
    : p1=param { $code = $p1.code; }
    ( COMMA p2=param { $code += ", " + $p2.code; } )*
    ;

// 9. param → type_specifier ID  |  type_specifier ID [ ]
param returns [String code]
@init { $code = ""; }
    : type_specifier ID 
    {
        Info e = new Info();
        e.theType = $type_specifier.attr_type;
        e.isGlobal = false;
        
        int argIdx = varCount++;
        addSymbol($ID.text, e);
        currentFuncParams.add(e);
        
        String lt = llvmType(e.theType);
        $code = lt + " noundef %" + argIdx;
    }
    | type_specifier ID LS_SY RS_SY
    ;

// 10. compound-stmt  →  {  local-declarations  statement-list  } 
compound_stmt
    : LB_SY block_item_list RB_SY
    ;


// 11. local-declarations  →  local-declarations  var-declarations  |  empty
// 12. statement-list  →  statement-list  statement  |  empty 
block_item_list
    : (var_declaration | statement)*
    ;

// 13. statement  →  expression-stmt  |  compound-stmt  |  selection-stmt  |  iteration-stmt  |  return-stmt 
statement
    : expression_stmt
    | compound_stmt
    | selection_stmt
    | iteration_stmt
    | jump_stmt
    | printf_stmt SEMICOLON
    | scanf_stmt  SEMICOLON
    ;

// 14. expression-stmt  →  expression  ;  |  ; 
expression_stmt returns [Type attr_type]
    : expression SEMICOLON { $attr_type = $expression.theInfo.theType; }
    | SEMICOLON            { $attr_type = Type.VOID; }
    ;

// 15. selection-stmt  →  if (  expression  )  statement  |  if (  expression  )  statement  else  statement 
selection_stmt
@init {
    String s_lTrue  = "";
    String s_lFalse = "";
    String s_lEnd   = "";
}
    : IF_ LP_SY cond=expression RP_SY
    {
        int lcnt = labelCount++;
        String suffix = (lcnt == 1) ? "" : String.valueOf(lcnt);
        
        s_lTrue  = "Ltrue" + suffix;
        s_lFalse = "Lfalse" + suffix;
        s_lEnd   = "Lend" + suffix;
        
        TextCode.add("  br i1 %" + $cond.theInfo.theVar.varIndex
                    + ", label %" + s_lTrue + ", label %" + s_lFalse);
        TextCode.add("");
        TextCode.add(s_lTrue + ":");
    }
    then_s=statement
    {
        String lastInstThen = TextCode.get(TextCode.size() - 1).trim();
        if (!lastInstThen.startsWith("br") && !lastInstThen.startsWith("ret")) {
            TextCode.add("  br label %" + s_lEnd);
        }
        TextCode.add(""); 
        TextCode.add(s_lFalse + ":"); 
    }
    ( ELSE_ else_s=statement )?
    {
        String lastInstElse = TextCode.get(TextCode.size() - 1).trim();
        if (!lastInstElse.startsWith("br") && !lastInstElse.startsWith("ret")) {
            TextCode.add("  br label %" + s_lEnd);
        }
        TextCode.add("");
        TextCode.add(s_lEnd + ":");
    }
    ;

// Add-on
for_init
@init { Type t = Type.ERR; }
    : type_specifier { t = $type_specifier.attr_type; } dec_item[t] ( COMMA dec_item[t] )*
    | expression
    | /* empty */
    ;

// 16. iteration-stmt  →  while (  expression  )  statement  | for ( for-init ; expression ; expression ) statement
iteration_stmt
@init {
    String it_lCond = "";
    String it_lBody = "";
    String it_lPost = "";
    String it_lEnd  = "";
}
    : WHILE_ LP_SY
    {
        it_lCond = newLabel();
        it_lBody = newLabel();
        it_lEnd  = newLabel();
        TextCode.add("  br label %" + it_lCond);
        TextCode.add(it_lCond + ":");
        
        _continueLabelStack.push(it_lCond);
        _breakLabelStack.push(it_lEnd);
    }
    cond=expression RP_SY
    {
        TextCode.add("  br i1 %" + $cond.theInfo.theVar.varIndex
                    + ", label %" + it_lBody + ", label %" + it_lEnd);
        TextCode.add(it_lBody + ":");
    }
    statement
    {
        _continueLabelStack.pop();
        _breakLabelStack.pop();
        
        String lastInst = TextCode.get(TextCode.size() - 1).trim();
        if (!lastInst.startsWith("br") && !lastInst.startsWith("ret")) {
            TextCode.add("  br label %" + it_lCond);
        }
        TextCode.add(it_lEnd + ":");
    }
    | FOR_ LP_SY
    {
        it_lCond = newLabel();
        it_lBody = newLabel();
        it_lPost = newLabel();
        it_lEnd  = newLabel();
        
        _continueLabelStack.push(it_lPost);
        _breakLabelStack.push(it_lEnd);
    }
    for_init SEMICOLON
    {
        TextCode.add("  br label %" + it_lCond);
        TextCode.add(it_lCond + ":");
    }
    for_cond=expression SEMICOLON
    {
        TextCode.add("  br i1 %" + $for_cond.theInfo.theVar.varIndex
                    + ", label %" + it_lBody + ", label %" + it_lEnd);
        TextCode.add(it_lPost + ":");
    }
    for_post=expression RP_SY
    {
        TextCode.add("  br label %" + it_lCond);
        TextCode.add(it_lBody + ":");
    }
    statement
    {
        _continueLabelStack.pop();
        _breakLabelStack.pop();
        
        String lastInst = TextCode.get(TextCode.size() - 1).trim();
        if (!lastInst.startsWith("br") && !lastInst.startsWith("ret")) {
            TextCode.add("  br label %" + it_lPost);
        }
        TextCode.add(it_lEnd + ":");
    }
    ;


// 17. return-stmt  →  return ;  |  return  expression  ; 
    // Add-on: break; |  continue;
jump_stmt
    : RETURN_ expression SEMICOLON
    {
        Info rv = $expression.theInfo;
        if (rv.theType == Type.CONST_INT) {
            TextCode.add("  ret i32 " + rv.theVar.iValue);
        } else if (baseType(rv.theType) == Type.FLOAT) {
            Info rf = toFloat(rv);
            TextCode.add("  ret float %" + rf.theVar.varIndex);
        } else {
            Info rm = materialize(rv);
            TextCode.add("  ret i32 %" + rm.theVar.varIndex);
        }
    }
    | RETURN_ SEMICOLON
    { TextCode.add("  ret void"); }

    | BREAK_ SEMICOLON
    {
        if (!_breakLabelStack.isEmpty())
            TextCode.add("  br label %" + _breakLabelStack.peek());
    }
    | CONTINUE_ SEMICOLON
    {
        if (!_continueLabelStack.isEmpty())
            TextCode.add("  br label %" + _continueLabelStack.peek());
    }
    ;


// PRINTF
printf_stmt
@init { _printfArgs.clear(); usePrintf = true; }
    : PRINTF_ LP_SY fmt=STRING_LITERAL
    ( COMMA printf_arg_list )?
    RP_SY
    {
        String rawFmt  = $fmt.text;
        String gName   = registerString(rawFmt);
        String content = rawFmt.substring(1, rawFmt.length() - 1);
        int byteLen    = computeStrLen(content) + 1;

        String gepInline = "i8* noundef getelementptr inbounds ([" + byteLen + " x i8], [" + byteLen + " x i8]* " + gName + ", i64 0, i64 0)";

        // 1. Process all arguments, prepare LLVM IR code
        StringBuilder argStr = new StringBuilder();
        for (Info arg : _printfArgs) {
            if (baseType(arg.theType) == Type.INT) {
                Info m = materialize(arg);
                argStr.append(", i32 noundef %").append(m.theVar.varIndex);
            } else if (baseType(arg.theType) == Type.FLOAT) {
                Info f  = toFloat(arg);
                int  di = newVar(); 
                TextCode.add("  %" + di + " = fpext float %" + f.theVar.varIndex + " to double");
                argStr.append(", double noundef %").append(di);
            }
        }

        // 2. Assign call instruction
        int callIdx = newVar(); 
        TextCode.add("  %" + callIdx + " = call i32 (i8*, ...) @printf(" + gepInline + argStr.toString() + ")");
        
        _printfArgs.clear();
    }
    ;

printf_arg_list
    : a=arith_expression { _printfArgs.add($a.theInfo); }
    ( COMMA b=arith_expression { _printfArgs.add($b.theInfo); } )*
    ;


// SCANF
scanf_stmt
    : SCANF_ LP_SY fmt=STRING_LITERAL COMMA AMP ID RP_SY
    {
        useScanf = true;
        String rawFmt  = $fmt.text;
        String gName   = registerString(rawFmt);
        String content = rawFmt.substring(1, rawFmt.length() - 1);
        int    byteLen = computeStrLen(content) + 1;

        String gepInline = "i8* noundef getelementptr inbounds ([" + byteLen + " x i8], [" + byteLen + " x i8]* " + gName + ", i64 0, i64 0)";

        Info target = getSymbol($ID.text);
        if (target == null) {
            System.out.println("==Error== " + $ID.line + ": Undeclared identifier.");
        } else {
            String ptrStr = target.isGlobal ? target.theVar.globalName : "%" + target.theVar.varIndex;
            String lt = llvmType(target.theType);
            TextCode.add("  %" + newVar() + " = call i32 (i8*, ...) @scanf(" + gepInline + ", " + lt + "* noundef " + ptrStr + ")");
        }
    }
    ;

// 18. expression  →  var  =  expression  |  increase-unary | decrease-unary | simple-expression 
expression returns [Info theInfo]
@init { $theInfo = new Info(); }
    : v=var ASS_OP e=expression
    {
        Info lhs = $v.theInfo;
        Info rhs = $e.theInfo;
        String ptrStr = lhs.isGlobal ? lhs.theVar.globalName : "%" + lhs.theVar.varIndex;
        String lt = llvmType(lhs.theType); 

        if (lhs.theType == Type.INT) {
            if (baseType(rhs.theType) == Type.FLOAT) {
                Info rf = toFloat(rhs);
                int fi = newVar();
                TextCode.add("  %" + fi + " = fptosi float %" + rf.theVar.varIndex + " to i32");
                TextCode.add("  store i32 %" + fi + ", " + lt + "* " + ptrStr + ", align 4");
            } else if (rhs.theType == Type.CONST_INT) {
                TextCode.add("  store i32 " + rhs.theVar.iValue + ", " + lt + "* " + ptrStr + ", align 4");
            } else {
                rhs = materialize(rhs);
                TextCode.add("  store i32 %" + rhs.theVar.varIndex + ", " + lt + "* " + ptrStr + ", align 4");
            }
        } else if (lhs.theType == Type.FLOAT) {
            if (rhs.theType == Type.CONST_FLOAT) {
                TextCode.add("  store float " + getLLVMFloat(rhs.theVar.fValue) + ", " + lt + "* " + ptrStr + ", align 4");
            } else {
                Info rf = toFloat(rhs);
                TextCode.add("  store float %" + rf.theVar.varIndex + ", " + lt + "* " + ptrStr + ", align 4");
            }
        } 
        $theInfo = lhs;
    }
    | v=var INC_UN
    {
        Info vi = $v.theInfo;
        String ptrStr = vi.isGlobal ? vi.theVar.globalName : "%" + vi.theVar.varIndex;
        String lt = llvmType(vi.theType);
        
        int loadIdx = newVar();
        TextCode.add("  %" + loadIdx + " = load " + lt + ", " + lt + "* " + ptrStr + ", align 4");
        
        int mathIdx = newVar();
        if (vi.theType == Type.FLOAT) {
            TextCode.add("  %" + mathIdx + " = fadd float %" + loadIdx + ", 1.0");
        } else {
            TextCode.add("  %" + mathIdx + " = add nsw i32 %" + loadIdx + ", 1");
        }
        
        TextCode.add("  store " + lt + " %" + mathIdx + ", " + lt + "* " + ptrStr + ", align 4");
        
        Info resInfo = new Info();
        resInfo.theType = vi.theType;
        resInfo.isGlobal = false;
        resInfo.theVar.varIndex = loadIdx;
        $theInfo = resInfo;
    }
    | v=var DEC_UN
    {
        Info vi = $v.theInfo;
        String ptrStr = vi.isGlobal ? vi.theVar.globalName : "%" + vi.theVar.varIndex;
        String lt = llvmType(vi.theType);
        
        int loadIdx = newVar();
        TextCode.add("  %" + loadIdx + " = load " + lt + ", " + lt + "* " + ptrStr + ", align 4");
        
        int mathIdx = newVar();
        if (vi.theType == Type.FLOAT) {
            TextCode.add("  %" + mathIdx + " = fsub float %" + loadIdx + ", 1.0");
        } else {
            TextCode.add("  %" + mathIdx + " = sub nsw i32 %" + loadIdx + ", 1");
        }
        
        TextCode.add("  store " + lt + " %" + mathIdx + ", " + lt + "* " + ptrStr + ", align 4");
        
        Info resInfo = new Info();
        resInfo.theType = vi.theType;
        resInfo.isGlobal = false;
        resInfo.theVar.varIndex = loadIdx;
        $theInfo = resInfo;
    }
    | simple_expression { $theInfo = $simple_expression.theInfo; }
    ;

// 19. var  →  ID  |  ID [  expression  ] 
var returns [Info theInfo]
@init { $theInfo = new Info(); }
    : ID
    {
        Info target = getSymbol($ID.text);
        if (target != null) {
            $theInfo = target;
        } else {
            System.out.println("==Error== " + $ID.line
                                + ": Undeclared identifier.");
            $theInfo.theType = Type.ERR;
        }
    }
    | ID LS_SY idx=expression RS_SY
    {
        Info arr = getSymbol($ID.text);
        if (arr != null) {
            String lt  = llvmType(arr.theType);
            
            if (arr.isGlobal) {
                String arrType = "[" + arr.arraySize + " x " + lt + "]";
                String idxStr = ($idx.theInfo.theType == Type.CONST_INT) 
                                ? String.valueOf($idx.theInfo.theVar.iValue) 
                                : "%" + $idx.theInfo.theVar.varIndex;
                                
                $theInfo.theType = arr.theType;
                $theInfo.isGlobal = true;
                $theInfo.theVar.globalName = "getelementptr inbounds (" + arrType + ", " + arrType + "* " + arr.theVar.globalName + ", i64 0, i64 " + idxStr + ")";
            } else {
                Info idxM  = materialize($idx.theInfo);
                String arrType = "[" + arr.arraySize + " x " + lt + "]";
                int gepIdx = newVar();
                TextCode.add("  %" + gepIdx
                            + " = getelementptr inbounds " + arrType + ", " + arrType + "* %" + arr.theVar.varIndex
                            + ", i32 0, i32 %" + idxM.theVar.varIndex);
                $theInfo.theType         = arr.theType;
                $theInfo.theVar.varIndex = gepIdx;
                $theInfo.isGlobal        = false;
            }
        } else {
            System.out.println("==Error== " + $ID.line + ": Undeclared identifier.");
            $theInfo.theType = Type.ERR;
        }
    }
    ;

// 20. simple-expression  →  additive-expression  relop  additive-expression  |  additive-expression 
simple_expression returns [Info theInfo]
@init { $theInfo = new Info(); }
    : a=additive_expression { $theInfo = $a.theInfo; }
    ( op=relop b=additive_expression
        {
            int cmpIdx = emitCmp($op.text, $a.theInfo, $b.theInfo);
            $theInfo = new Info();
            $theInfo.theType         = Type.INT;
            $theInfo.theVar.varIndex = cmpIdx;
        }
    )?
    ;

// 21. relop  →  <=  |  <  |  >  |  >=  |  ==  |  != 
relop returns [String text]
    : LE_OP { $text = "<="; }
    | LT_OP { $text = "<";  }
    | GT_OP { $text = ">";  }
    | GE_OP { $text = ">="; }
    | EQ_OP { $text = "=="; }
    | NE_OP { $text = "!="; }
    ;

// 22. additive-expression  →  additive-expression  addop  term  |  term 
additive_expression returns [Info theInfo]
@init { $theInfo = new Info(); }
    : a=term { $theInfo = $a.theInfo; }
    ( op=addop b=term
        { $theInfo = emitBinop($op.text, $theInfo, $b.theInfo); }
    )*
    ;

// 23. addop  →  +  |  - 
addop returns [String text]
    : ADD_OP { $text = "+"; }
    | SUB_OP { $text = "-"; }
    ;

// 24. term  →  term  mulop  factor  |  factor 
term returns [Info theInfo]
@init { $theInfo = new Info(); }
    : a=unary_expr { $theInfo = $a.theInfo; }
    ( op=mulop b=unary_expr
        { 
            $theInfo = emitBinop($op.text, $theInfo, $b.theInfo); 
        }
    | CONCAT_OP b=unary_expr
        { 
            $theInfo = emitConcatOp($theInfo, $b.theInfo); 
        }
    )*
    ;


// 25. mulop  →  *  |  / |  % 
mulop returns [String text]
    : MUL_OP { $text = "*"; }
    | DIV_OP { $text = "/"; }
    | MOD_OP { $text = "%"; }
    ;

unary_expr returns [Info theInfo]
@init { $theInfo = new Info(); }
    : SUB_OP f=factor
    {
        Info fi  = materialize($f.theInfo);
        int  idx = newVar();
        if (baseType($f.theInfo.theType) == Type.FLOAT) {
            TextCode.add("  %" + idx + " = fneg float %" + fi.theVar.varIndex);
            $theInfo.theType = Type.FLOAT;
        } else {
            TextCode.add("  %" + idx + " = sub nsw i32 0, %" + fi.theVar.varIndex);
            $theInfo.theType = Type.INT;
        }
        $theInfo.theVar.varIndex = idx;
    }
    | f=factor { $theInfo = $f.theInfo; }
    ;

// 26. factor  →  (  expression  )  |  var  |  call  |  Integer  |  Float 
// 27. call  →  ID (  args  ) 
factor returns [Info theInfo]
@init { $theInfo = new Info(); }
    : LP_SY e=expression RP_SY
    { $theInfo = $e.theInfo; }

    | LP_SY INT_TYPE RP_SY f=factor
    {
        if (baseType($f.theInfo.theType) == Type.FLOAT) {
            Info m  = materialize($f.theInfo);
            int  idx = newVar();
            TextCode.add("  %" + idx + " = fptosi float %"
                        + m.theVar.varIndex + " to i32");
            $theInfo.theType = Type.INT; $theInfo.theVar.varIndex = idx;
        } else {
            $theInfo = materialize($f.theInfo);
        }
    }

    | LP_SY FLOAT_TYPE RP_SY f=factor
    { $theInfo = toFloat($f.theInfo); }

    | DEC_NUM
    {
        $theInfo.theType       = Type.CONST_INT;
        $theInfo.theVar.iValue = Integer.parseInt($DEC_NUM.text);
    }

    | FLOAT_NUM
    {
        $theInfo.theType       = Type.CONST_FLOAT;
        $theInfo.theVar.fValue = Float.parseFloat($FLOAT_NUM.text);
    }

    | v=var
    {
        Info vi = $v.theInfo;
        if (vi.theType != Type.ERR) {
            String lt = llvmType(vi.theType);
            int idx   = newVar();
            String ptrStr = vi.isGlobal ? vi.theVar.globalName : "%" + vi.theVar.varIndex;
            TextCode.add("  %" + idx + " = load " + lt + ", " + lt + "* " + ptrStr + ", align 4");
            
            $theInfo.theType = vi.theType; 
            $theInfo.theVar.varIndex = idx;
        } else {
            $theInfo = vi;
        }
    }

    | BOOL_VAL
    {
        $theInfo.theType       = Type.CONST_INT;
        $theInfo.theVar.iValue = $BOOL_VAL.text.equals("true") ? 1 : 0;
    }

    | ID LP_SY args RP_SY
    {
        Info f = getSymbol($ID.text);
        if (f != null) {
            String lt = llvmType(f.theType);
            
            if (f.theType == Type.VOID) {
                TextCode.add("  call void @" + $ID.text + "(" + $args.code + ")");
                $theInfo.theType = Type.VOID;
            } else {
                int idx = newVar();
                TextCode.add("  %" + idx + " = call " + lt + " @" + $ID.text + "(" + $args.code + ")");
                $theInfo.theType = f.theType;
                $theInfo.theVar.varIndex = idx;
            }
        } else {
            System.out.println("==Error== " + $ID.line + ": Undeclared function.");
            $theInfo.theType = Type.ERR;
        }
    }
    ;


arith_expression returns [Info theInfo]
@init { $theInfo = new Info(); }
    : e=additive_expression { $theInfo = $e.theInfo; }
    ;


// 28. args  →  arg-list  |  empty 
args returns [String code]
@init { $code = ""; }
    : arg_list  { $code = $arg_list.code; }
    | /* empty */ 
    ;

// 29. arg-list  →  arg-list  ,  expression  |  expression
arg_list returns [String code]
@init { $code = ""; }
    : e1=expression 
    {
        String lt = llvmType($e1.theInfo.theType);
        if ($e1.theInfo.theType == Type.CONST_INT) {
            $code = lt + " noundef " + $e1.theInfo.theVar.iValue;
        } else if ($e1.theInfo.theType == Type.CONST_FLOAT) {
            $code = lt + " noundef " + getLLVMFloat($e1.theInfo.theVar.fValue);
        } else {
            Info m = materialize($e1.theInfo);
            lt = llvmType(m.theType);
            $code = lt + " noundef %" + m.theVar.varIndex;
        }
    }
    ( COMMA e2=expression 
        {
        String lt2 = llvmType($e2.theInfo.theType);
        if ($e2.theInfo.theType == Type.CONST_INT) {
            $code += ", " + lt2 + " noundef " + $e2.theInfo.theVar.iValue;
        } else if ($e2.theInfo.theType == Type.CONST_FLOAT) {
            $code += ", " + lt2 + " noundef " + getLLVMFloat($e2.theInfo.theVar.fValue);
        } else {
            Info m2 = materialize($e2.theInfo);
            lt2 = llvmType(m2.theType);
            $code += ", " + lt2 + " noundef %" + m2.theVar.varIndex;
        }
        }
    )*
    ;

        
/* description of the tokens */
INT_TYPE  : 'int';
VOID_TYPE : 'void';
FLOAT_TYPE: 'float';
WHILE_    : 'while';
RETURN_   : 'return';
IF_       : 'if';
ELSE_     : 'else';
BREAK_    : 'break';
CONTINUE_ : 'continue';
FOR_      : 'for';
PRINTF_   : 'printf';
SCANF_    : 'scanf';


EQ_OP : '==';
LE_OP : '<=';
GE_OP : '>=';
NE_OP : '!=';
INC_UN : '++';
DEC_UN : '--';
ADD_OP : '+';
SUB_OP : '-';
MUL_OP : '*';
DIV_OP : '/';
MOD_OP : '%';
LT_OP : '<';
GT_OP : '>';
ASS_OP : '=';
CONCAT_OP : '##';


COLON     : ':';
SEMICOLON : ';';
COMMA     : ',';
LP_SY     : '(';
RP_SY     : ')';
LS_SY     : '[';
RS_SY     : ']';
LB_SY     : '{';
RB_SY     : '}';
AMP       : '&';

BOOL_VAL  : 'true' | 'false';
STRING_LITERAL : '"' ~["]* '"';

FLOAT_NUM: FLOAT_NUM1 | FLOAT_NUM2;
fragment FLOAT_NUM1: (DIGIT)+'.'(DIGIT)*;
fragment FLOAT_NUM2: '.'(DIGIT)+;

DEC_NUM : ('0' | ('1'..'9')(DIGIT)*);

ID : (LETTER)(LETTER | DIGIT)*;

fragment LETTER : 'a'..'z' | 'A'..'Z' | '_';
fragment DIGIT : '0'..'9';


/* IGNORE */
COMMENT1 : '//' (.)*? '\n' -> skip ;
COMMENT2 : '/*' (.)*? '*/' -> skip ;
NEW_LINE: '\n' -> skip ;
WS  : (' '|'\r'|'\t')+ 
    -> skip ;

PREPROCESSOR : '#' [a-zA-Z]+ ~[\r\n]* -> skip ;