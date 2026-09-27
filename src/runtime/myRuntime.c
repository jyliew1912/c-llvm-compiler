#include <stdio.h>
#include <math.h>

float __concat_float(float a, float b) {
    return powf(a, b) + powf(b, a);
}
