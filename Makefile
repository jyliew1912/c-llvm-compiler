ANTLR_JAR    = lib/antlr4-4.13.1-complete.jar
BIN_DIR      = bin
SRC_DIR      = src
TEST_DIR     = tests
RUNTIME_SRC  = $(SRC_DIR)/runtime/myRuntime.c
CLASSPATH    = .:$(ANTLR_JAR):$(BIN_DIR)

GRAMMAR      = $(SRC_DIR)/myCompiler.g4
MAIN_CLASS   = myCompiler_test

.PHONY: all generate compile test run clean

all: generate compile

generate: $(GRAMMAR)
	@echo "==> Generating ANTLR Parser & Lexer..."
	java -jar $(ANTLR_JAR) $(GRAMMAR)

compile: generate
	@echo "==> Compiling Java sources into $(BIN_DIR)/..."
	@mkdir -p $(BIN_DIR)
	javac -cp .:$(ANTLR_JAR) -d $(BIN_DIR) $(SRC_DIR)/*.java

test: compile
	@echo "==> Compiling test cases to LLVM IR..."
	java -cp $(CLASSPATH) $(MAIN_CLASS) $(TEST_DIR)/test1.c > $(TEST_DIR)/test1.ll
	java -cp $(CLASSPATH) $(MAIN_CLASS) $(TEST_DIR)/test2.c > $(TEST_DIR)/test2.ll
	java -cp $(CLASSPATH) $(MAIN_CLASS) $(TEST_DIR)/test3.c > $(TEST_DIR)/test3.ll
	@echo "==> LLVM IR generation successful."

run: test
	@echo "==> [Execution 1] Compiling test1 via Clang + Runtime..."
	clang $(TEST_DIR)/test1.ll $(RUNTIME_SRC) -o $(BIN_DIR)/test1_exec -lm
	./$(BIN_DIR)/test1_exec

	@echo "==> [Execution 2] Running test2 via LLVM JIT (lli)..."
	lli $(TEST_DIR)/test2.ll

	@echo "==> [Execution 3] Running test3 via LLVM JIT (lli)..."
	lli $(TEST_DIR)/test3.ll

clean:
	@echo "==> Cleaning generated artifacts..."
	rm -rf $(BIN_DIR)
	rm -f $(SRC_DIR)/myCompilerLexer.* $(SRC_DIR)/myCompilerParser.*
	rm -f $(SRC_DIR)/myCompilerListener.* $(SRC_DIR)/myCompilerBaseListener.*
	rm -f $(SRC_DIR)/*.tokens $(SRC_DIR)/*.interp
	rm -f $(TEST_DIR)/*.ll
