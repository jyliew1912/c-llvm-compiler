#include <stdio.h>

// --- 1. Global Variables ---
int g_val = 100;
float g_pi = 3.14;

// --- 2. Void Function & No Parameter ---
void print_banner() {
    printf("=== Compiler Test Start ===\n");
}

// --- 3. Function with 2 or more parameters & Return ---
int get_first(int a, int b) {
    return a;
}

// --- 4. Float Function & Mixed Arithmetic ---
float calculate_area(float radius) {
    return radius * radius * g_pi;
}


int main() {
    print_banner();

    // --- Test A: Local variable & global variable ---
    int g_val = 10;
    printf("Local g_val is %d\n", g_val);  // Should print 10 local variable, not 100

    // --- Test B: Complex Arithmetic (priority of operators) ---
    int math_res;
    math_res = g_val + 5 * (100 - g_val) / 2;  // math_res should be 235: 10 + ( 5 * (100 - 10) / 2 )

    // --- Test C: Function Calls ---
    int first_val = get_first(10, 50);
    float area = calculate_area(5.0);

    // --- Test D: Nested If-Else & Comparison ---
    if (math_res == 235) {
        if (first_val < 20) {
            printf("Nested IF: Passed!\n");
        } else {
            printf("Nested IF: Failed (Inner)\n");
        }
    } else {
        printf("Nested IF: Failed (Outer)\n");
    }

    return 0;
}
