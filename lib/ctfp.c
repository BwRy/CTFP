#include <float.h>
#include <emmintrin.h>
#include <math.h>


__attribute__((weak)) float ctfp_flt_mul_1(float d1, float d2)
{
	__m128 v1, v2, v3;

	v1[0] = d1;
	v2[0] = d2;

	__m128 min = { sqrt(DBL_MIN), sqrt(DBL_MIN), sqrt(DBL_MIN), sqrt(DBL_MIN) };

	__m128 abs = _mm_castsi128_ps(_mm_srli_epi32(_mm_set1_epi32(-1), 1));
	v1 = _mm_and_ps(v1, _mm_cmpge_ss(_mm_and_ps(v1, abs), min));
	v2 = _mm_and_ps(v2, _mm_cmpge_ss(_mm_and_ps(v2, abs), min));

	v3 = _mm_mul_ss(v1, v2);

	return v3[0];
}

__attribute__((weak)) float ctfp_flt_div_1(float d1, float d2)
{
	__m128 v1, v2, v3;

	v1[0] = d1;
	v2[0] = d2;

	__m128 min = { sqrt(FLT_MIN), sqrt(FLT_MIN), sqrt(FLT_MIN), sqrt(FLT_MIN) };
	__m128 max = { sqrt(FLT_MAX), sqrt(FLT_MAX), sqrt(FLT_MAX), sqrt(FLT_MAX) };

	__m128 abs = _mm_castsi128_ps(_mm_srli_epi32(_mm_set1_epi32(-1), 1));
	v1 = _mm_and_ps(v1, _mm_cmpge_ss(_mm_and_ps(v1, abs), min));
	v2 = _mm_and_ps(v2, _mm_cmple_ss(_mm_and_ps(v2, abs), max));

	v3 = _mm_div_ss(v1, v2);

	return v3[0];
}


/**
 * Addition between doubles, masks subnormals.
 *   @v1: Value one.
 *   @v2: Value two.
 *   &returns: Their sum.
 */
__attribute__((weak)) double ctfp_dbl_add_1(double v1, double v2)
{
	__m128d r1, r2, r3;

	r1[0] = v1;
	r2[0] = v2;

	__m128d abs = _mm_castsi128_pd(_mm_srli_epi32(_mm_set1_epi32(-1), 1));
	__m128d min = { DBL_MIN, DBL_MIN };

	r1 = _mm_and_pd(r1, _mm_cmpge_sd(_mm_and_pd(r1, abs), min));
	r2 = _mm_and_pd(r2, _mm_cmpge_sd(_mm_and_pd(r2, abs), min));
	r3 = _mm_add_sd(r1, r2);

	return r3[0];
}

__attribute__((weak)) double ctfp_dbl_mul_1(double d1, double d2)
{
	__m128d v1, v2, v3;

	v1[0] = v1[1] = d1;
	v2[0] = v2[1] = d2;

	__m128d min = { sqrt(DBL_MIN), sqrt(DBL_MIN) };

	__m128d abs = _mm_castsi128_pd(_mm_srli_epi32(_mm_set1_epi32(-1), 1));
	v1 = _mm_and_pd(v1, _mm_cmpge_sd(_mm_and_pd(v1, abs), min));
	v2 = _mm_and_pd(v2, _mm_cmpge_sd(_mm_and_pd(v2, abs), min));

	v3 = _mm_mul_sd(v1, v2);

	return v3[0];
}

__attribute__((weak)) double ctfp_dbl_div_1(double d1, double d2)
{
	__m128d v1, v2, v3;

	v1[0] = v1[1] = d1;
	v2[0] = v2[1] = d2;

	__m128d min = { sqrt(DBL_MIN), sqrt(DBL_MIN) };
	__m128d max = { sqrt(DBL_MAX), sqrt(DBL_MAX) };

	//v1 = _mm_and_pd(v1, _mm_cmpge_sd(v1, min));
	//v2 = _mm_and_pd(v2, _mm_cmpge_sd(v2, min));

	__m128d abs = _mm_castsi128_pd(_mm_srli_epi32(_mm_set1_epi32(-1), 1));
	v1 = _mm_and_pd(v1, _mm_cmpge_sd(_mm_and_pd(v1, abs), min));
	v2 = _mm_and_pd(v2, _mm_cmple_sd(_mm_and_pd(v2, abs), max));

	v3 = _mm_div_sd(v1, v2);

	return v3[0];
}


__attribute__((weak)) double ctfp_sqrt_f_1(float v1)
{
	__m128 r1;
	__m128 min = { sqrtf(FLT_MIN), sqrtf(FLT_MIN), sqrtf(FLT_MIN), sqrtf(FLT_MIN) };
	__m128 abs = _mm_castsi128_ps(_mm_srli_epi32(_mm_set1_epi32(-1), 1));

	r1[0] = v1;

	r1 = _mm_and_ps(r1, _mm_cmpge_ss(_mm_and_ps(r1, abs), min));

	return _mm_sqrt_ss(r1)[0];
}

__attribute__((weak)) double ctfp_sqrt_d_1(double v1)
{
	__m128d r1;
	__m128d min = { sqrt(DBL_MIN), sqrt(DBL_MIN) };
	__m128d abs = _mm_castsi128_pd(_mm_srli_epi32(_mm_set1_epi32(-1), 1));

	r1[0] = v1;

	r1 = _mm_and_pd(r1, _mm_cmpge_sd(_mm_and_pd(r1, abs), min));

	return _mm_sqrt_sd(r1, r1)[0];
}
