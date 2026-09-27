#include <stdio.h>

int main() {  // 1-Supports return VOID
    int x;    // 1-Supports INT
    float a = 2.5;  // 1-Supports FLOAT
    float b = 1.5;  // Supports 'ID ASS_OP expression' variable declaration
    float c1;
    float c2;

    c1 = a + b ## a;  // 7-Supports ## operator
    c2 = a * b ## a / b;   // 7-Same priority as MUL_OP & DIV_OP
    printf("c1 = %f\nc2 = %f\n", c1, c2);  // 5-Supports printf in %f type with 2 parameters

    if (c1 > c2)  // 3-Supports comparison
    {  
        printf("c1 is greater than c2\n");  // 5-Supports printf with no type
    } 
    else if (c1 < c2) 
    { 
        printf("c1 is not greater than c2\n");
    } 
    else  // 4-Supports if-then-else constructs
    {   
        printf("c1 is equal to c2\n");
    }

    printf("Enter a number in range 0-10: ");
    scanf("%d", &x);  // 6-Supports scanf with %d type
    
    if (x != 3) {   // 4-Supports if-then constructs
        printf("%d is not equal to 3 (a random number set in c file).\n");  // 5-Supports printf in %d type
    }
   
    return 0;
}
