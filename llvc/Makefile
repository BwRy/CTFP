all:
	stack build --fast

run:
	stack build --fast
	@#stack exec llvc test/ll/restrict.add.f32.ll # PASS
	@#stack exec llvc test/ll/restrict.sub.f32.ll # PASS
	@#stack exec llvc test/ll/restrict.mul.f32.ll # PASS
	@#stack exec llvc test/ll/full.add.f32.ll # PASS
	stack exec llvc test/ll/full.add.f64.ll @ctfp_full_add_f64v1_2
	@#stack exec llvc test/ll/restrict.div.f32.ll @ctfp_restrict_div_f32v1
	@#stack exec llvc test/ll/restrict.add.f64.ll @ctfp_restrict_add_f64v1
	@#stack exec llvc test/ll/restrict.sub.f32.ll
	@#stack exec llvc test/ll/restrict.mul.f32.ll
	@#stack exec llvc test/ll/restrict.div.f32.ll
	@#stack exec llvc test/ll/restrict.sqrt.f32.ll
