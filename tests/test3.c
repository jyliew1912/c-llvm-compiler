#include <stdio.h>

int main() {
    int a = 3;
    float b = 4.5;
    printf("a = %d, b = %f\n", a, b);

    float float_result = a + b;
    printf("The float result of a + b is: %f\n", float_result);
    int int_result = a + b;
    printf("The integer result of a + b is: %d\n", int_result);

    float_result = (float) a;
    printf("The float result of (float)a is: %f\n", float_result);
    int_result = (int) b;
    printf("The integer result of (int)b is: %d\n", int_result);

    while(int_result < 10) {
        printf("This is a while-loop\n");
        for(int i = 0; i < 2; i++) {
            printf("  This is a for-loop inside a while-loop\n");
            for (int j = 0; j < 3; j++) {
                if (j == 1) continue;
                printf("    This is a nested for-loop inside a while-loop. Each loop prints 2 times!\n");
            }
            printf("  We jump back to first for-loop\n");
        }
	printf("We jump back to while-loop\n");
        int_result++;
        break;
    }
    printf("The integer result after the while loop is: %d\n", int_result);
    return 0;
}
