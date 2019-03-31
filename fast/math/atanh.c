#include "../ctfp-math.h"

#include "libm.h"

/* ctfp_atanh(x) = ctfp_log((1+x)/(1-x))/2 = ctfp_log1p(2x/(1-x))/2 ~= x + x^3/3 + o(x^5) */
double ctfp_atanh(double x)
{
	union {double f; uint64_t i;} u = {.f = x};
	unsigned e = u.i >> 52 & 0x7ff;
	unsigned s = u.i >> 63;
	double_t y;

	/* |x| */
	u.i &= (uint64_t)-1/2;
	y = u.f;

	if (e < 0x3ff - 1) {
		if (e < 0x3ff - 32) {
			/* handle underflow */
			if (e == 0)
				FORCE_EVAL((float)y);
		} else {
			/* |x| < 0.5, up to 1.7ulp error */
			y = 0.5*ctfp_log1p(2*y + 2*y*y/(1-y));
		}
	} else {
		/* avoid overflow */
		y = 0.5*ctfp_log1p(2*(y/(1-y)));
	}
	return s ? -y : y;
}
