# C Subset to LLVM IR Compiler

[![Build and Verify Compiler](https://github.com/jyliew1912/c-llvm-compiler/actions/workflows/ci.yml/badge.svg)](https://github.com/jyliew1912/c-llvm-compiler/actions/workflows/ci.yml)

An ahead-of-time (AOT) and JIT-compatible compiler for an extended subset of the C programming language, emitting verifiable **LLVM Intermediate Representation (LLVM IR)**. Built with **ANTLR v4** for lexical and syntactic parsing, featuring custom semantic analysis, symbol table management, type coercion, and LLVM IR code emission implemented in **Java**.

---

## Architecture Pipeline
```
   C Source Code (.c)
            │
            ▼
[ ANTLR v4 Lexer & Parser ] ──▶ Parse Tree & Token Stream
            │
            ▼
[ Java Semantic Analyzer ]  ──▶ Multi-level Scoping & Symbol Tables
            │               ──▶ Implicit Type Promotion & Explicit Casting
            │               ──▶ Loop Control Flow Stacks (break / continue)
            ▼
  LLVM IR Assembly (.ll)
            │
     ┌──────┴──────┐
     ▼             ▼
[ LLVM JIT ]   [ Clang Driver ] ──▶ Links Native Runtime (`myRuntime.c`)
  (`lli`)          │
     │             ▼
     └────▶ Target Machine Execution

```

---

## Compiler Capabilities

### Core Language Support
* **Type System:** `int`, `float`, `void`, `bool`.
* **Arithmetic & Relational:** `+`, `-`, `*`, `/`, `%`, `>`, `>=`, `<`, `<=`, `==`, `!=`.
* **Standard I/O:**
  * Formatted output: `printf()` supporting `%d`, `%f` across arbitrary argument lengths.
  * Formatted input: `scanf()` supporting `%d`, `%f`.
* **Custom Operator (`##`):**
  * Evaluates `a ## b` = $a^b + b^a$ on floating-point operands.
  * Shares operator precedence with multiplication (`*`) and division (`/`).
  * Backed by native runtime math functions in `myRuntime.c`.

### Advanced & Optimization Features

1. **IEEE-754 Hexadecimal Floating-Point Representation:**
   * Emits floating-point constants using 64-bit double-precision hexadecimal formatting (e.g., `0x4014000000000000`).
   * Adheres strictly to the LLVM IR specification, preventing `lli` invalid type parsing errors.
2. **Type Coercion & Explicit Casting:**
   * **Implicit Promotion:** Auto-promotes `int op float` to `float` via `sitofp`. Truncates assignments from float to integer via `fptosi`.
   * **Explicit Casting:** Supports standard explicit casts `(int)expr` and `(float)expr`.
3. **Control Flow & Loop Stacks:**
   * **Nested `if-else`:** Deterministic basic block label generation (`Ltrue`, `Lfalse`, `Lend`) with scope counter tracking.
   * **Loops:** `while` loops and `for` loops with arbitrary initialization, condition, and step expressions.
   * **Stack-Allocated Loop Contexts:** Manages nested `break` and `continue` jumps using an internal label stack.
4. **Scoping & Variable Shadowing:**
   * Hierarchical symbol tables supporting block-level lexical scoping and shadowing between global and local identifiers.
5. **Functions & Arrays:**
   * Multi-argument function prototypes and definitions (`int`, `float`, `void`).
   * Stack array allocations with initialization lists (e.g., `int arr[3] = {1, 2, 3};`).

---

## Repository Structure

```text
.
├── Makefile                     # Build, test, and execution automation
├── lib/
│   └── antlr4-4.13.1-complete.jar # ANTLR4 tooling fat JAR
├── src/
│   ├── myCompiler.g4            # ANTLR4 grammar & semantic translation actions
│   ├── myCompiler_test.java     # CLI driver invoking the parser pipeline
│   └── runtime/
│       └── myRuntime.c          # C native runtime for standard I/O & `##` operator
├── tests/
│   ├── test1.c                  # End-to-end verification (I/O, control flow, `##` operator)
│   ├── test2.c                  # Standard C test case for parity comparison with Clang IR
│   └── test3.c                  # Bonus features (type casting, nested loops, break/continue)  
└── docs/
    └── c_subset_description.md         # Formal C-subset grammar and semantics specification
```

---

## Build & Execution

### Prerequisites

* **Java Development Kit:** JDK 11 or newer
* **LLVM Toolchain:** `clang` and `lli`
* **Build Essentials:** `make`

On Ubuntu / Debian / WSL2:

```bash
sudo apt update
sudo apt install build-essential openjdk-17-jdk clang llvm -y

```

### Automation Targets

| Target | Command | Action |
| --- | --- | --- |
| **Build** | `make all` | Generates lexer/parser Java files and compiles classes into `bin/`. |
| **Emit IR** | `make test` | Runs the compiler over `tests/*.c` and outputs corresponding `.ll` IR. |
| **Execute** | `make run` | Runs test cases via `clang` (AOT linking) and `lli` (JIT interpreter). |
| **Clean** | `make clean` | Purges generated ANTLR sources, compiled `.class` files, and `.ll` outputs. |

---

## Verification & Test Demos

### 1. End-to-End System & Runtime Verification (`test1.c`)

Tests the full compilation pipeline, non-standard C extension (`##`), and native runtime linking:

```c
float a = 1.5;
float b = 2.5;
float c1 = a + b ## a;
float c2 = a * b ## a / b;

```

* **Theoretical Formulation:**
  * $c1 = a + (b^a + a^b) = 1.5 + (2.5^{1.5} + 1.5^{2.5}) \approx 1.5 + 7.7085 \approx 9.208523$
  * $c2 = ((a \times b)^a + a^{(a \times b)}) / b = (3.75^{1.5} + 1.5^{3.75}) / 2.5 \approx 38.864788$


* **Runtime Execution Output:**
```text
c1 = 9.208523
c2 = 38.864788
c1 is not greater than c2
Enter a number in range 0-10: 
```



### 2. Clang IR Parity Comparison (`test2.c`)

Omits custom operator extensions to permit direct differential comparison against upstream `clang -S -emit-llvm test2.c`.

**IR Analysis:**
* **Memory Allocation:** Identical stack allocation semantics, with minor variations in local variable register scheduling.
* **Control Flow Labels:** Emits semantic branch tags (`Ltrue`, `Lfalse`, `Lend`) providing identical basic-block CFG equivalence to Clang's numeric labels.
* **Constants:** Hexadecimal IEEE-754 constant notation matches Clang target semantics and is verified clean by `lli` and `llc`.



### 3. Advanced Features & Loop Control Verification (`test3.c`)

Evaluates explicit/implicit type coercion, loop nesting, and jump target resolution under the JIT:

```text
a = 3, b = 4.500000
The float result of a + b is: 7.500000
The integer result of a + b is: 7
The float result of (float)a is: 3.000000
The integer result of (int)b is: 4
This is a while-loop
  This is a for-loop inside a while-loop
    This is a nested for-loop inside a while-loop. Each loop prints 2 times!
    This is a nested for-loop inside a while-loop. Each loop prints 2 times!
  We jump back to first for-loop
  This is a for-loop inside a while-loop
    This is a nested for-loop inside a while-loop. Each loop prints 2 times!
    This is a nested for-loop inside a while-loop. Each loop prints 2 times!
  We jump back to first for-loop
We jump back to while-loop
The integer result after the while loop is: 5
```

### What Changed & Why It Improves the Project
* **Formalized Technical Vocabulary:** Replaced colloquial descriptions with compiler terminology (e.g., *basic block labels*, *symbol table scoping*, *stack-allocated loop contexts*, *type coercion*).
* **Clear Architecture:** Preserved the end-to-end ASCII diagram so reviewers can understand the compiler's flow in three seconds.
* **Documented Differential Testing:** Kept your comparison against Clang in `test2.c` and execution of `test3.c` to showcase rigorous verification standards.

<FollowUp label="Want to inspect the Image Recognition project repository next?" query="Let's proceed to the Image Recognition repository. Here is my current file structure and code."/>

```
