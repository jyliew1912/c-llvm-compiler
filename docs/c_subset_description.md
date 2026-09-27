## 1. Program Structure

* A program consists of a sequence of global variable declarations and function declarations, following the grammar rule:
  * $\text{program} \rightarrow \text{declaration-list EOF}$
  * $\text{declaration-list} \rightarrow (\text{var-declaration} \mid \text{fun-declaration})^*$
* Declarations appear before / between function definitions at the global scope.
* There is no restriction on the ordering of declarations at the global level.

---

## 2. Data Types

* `int`
* `float`
* `void`

---

## 3. Variable Declarations

### 3.1 Scalar Declaration
```c
type ID;                // e.g., int x;
type ID = expression;   // e.g., float y = 1.5;
```

### 3.2 Array Declaration
```c
type ID[integer];                // e.g., int arr[5];
type ID[integer] = { list };     // e.g., int arr[3] = {1, 2, 3};
```
* An array size must be a positive integer.
* Global arrays without initialization are zero-initialized; local arrays without initialization are uninitialized.

### 3.3 Scoping and Shadowing
* An inner scope having the same variable name will shadow the outer scope variable.
* Redeclaring a variable in the same scope level will cause an error.

---

## 4. Operators and Expressions

### 4.1 Arithmetic Operators
* **Addition (`+`):** `int`, `float`
* **Subtraction (`-`):** `int`, `float`
* **Multiplication (`*`):** `int`, `float`
* **Division (`/`):** `int`, `float`
* **Modulo (`%`):** `int`
* **Unary negation (`-`):** `int`, `float`

### 4.2 Comparison Operators
* `==` : equal to
* `!=` : not equal to
* `>`  : greater than
* `>=` : greater than or equal to
* `<`  : less than
* `<=` : less than or equal to

### 4.3 Assignment Operators
* `=`

### 4.4 Increment / Decrement
```c
var++;  // increase by 1
var--;  // decrease by 1
```

### 4.5 `##` Operator
$$a \text{ \#\# } b = a^b + b^a$$
*(float operands only)*

---

## 5. Type Conversion

### 5.1 Implicit Conversion
```c
float result = int_num + float_num; // result is float type
int result = int_num + float_num;   // result is int type
```

### 5.2 Explicit Conversion
```c
float result = (float) int_num;     // result is float type
int result = (int) float_num;       // result is int type
```

---

## 6. Statements

### 6.1 Expression Statement
```c
expression; // e.g., x = x + 1;
;           // empty statement
```

### 6.2 Compound Statement
```c
{ var-declarations statements } // Block
```

### 6.3 Selection Statement
```c
if (expression) statement
if (expression) statement else statement
```

### 6.4 Iteration Statement
```c
while (expression) statement
for (for-init; expression; expression) statement
```

### 6.5 Jump Statement
```c
return;
return expression; // e.g., return 0;
break;
continue;
```

---

## 7. Function

### 7.1 Function Declaration
```c
type-specifier ID (params) compound-stmt
```
* Parameters and return types may be of `int`, `float`, or `void`.
* Can have one or more parameters.

### 7.2 Function Call
```c
ID (args)
```
* Arguments are passed by value.
* Functions must be declared before they are called.

---

## 8. Built-in I/O Functions

### `printf`
* Supports format specifiers `%d` and `%f`.
* Supports more than 1 argument.

### `scanf`
* Supports format specifiers `%d` and `%f`.
* Only supports 1 variable per `scanf`.