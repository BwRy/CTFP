{-# LANGUAGE MultiParamTypeClasses, FunctionalDependencies, FlexibleInstances #-}


debug = False
--debug = True

prelude =
  "target datalayout = \"e-m:e-i64:64-f80:128-n8:16:32:64-S128\"\n" ++
  "target triple = \"x86_64-pc-linux-gnu\"\n" ++
  "declare float @dbg_fadd_f32(float %a, float %b)\n" ++
  "declare float @dbg_fdiv_sig_f32(float %a, float %b)\n" ++
  "declare float @dbg_fdiv_exp_f32(float %a, float %b)\n" ++
  "" ++
  "declare float @llvm.fabs.f32(float %a)\n" ++
  "declare < 2 x float > @llvm.fabs.v2f32(< 2 x float > %a)\n" ++
  "declare < 4 x float > @llvm.fabs.v4f32(< 4 x float > %a)\n" ++
  "declare double @llvm.fabs.f64(double %a)\n" ++
  "declare < 2 x double > @llvm.fabs.v2f64(< 2 x double > %a)\n" ++
  "" ++
  "declare float @llvm.copysign.f32(float %a, float %b)\n" ++
  "declare < 2 x float > @llvm.copysign.v2f32(< 2 x float > %a, < 2 x float > %b)\n" ++
  "declare < 4 x float > @llvm.copysign.v4f32(< 4 x float > %a, < 4 x float > %b)\n" ++
  "declare double @llvm.copysign.f64(double %a, double %b)\n" ++
  "declare < 2 x double > @llvm.copysign.v2f64(< 2 x double > %a, < 2 x double > %b)\n" ++
  "\n"

main = 
  do putStr prelude
     --gen_func stupid Float1 "stupid"
     gen_func restrict_add Float1 "ctfp_restrict_add"
     --gen_func restrict_div Float1 "ctfp_restrict_div"
     putStr "\n"

stupid (a, b) =
  FAdd (a, func FAdd (a, b))
  --FAdd (a, b)


-- Create a call from a function and arguments
func :: ((Expr, Expr) -> Expr) -> (Expr, Expr) -> Expr
func fn (a, b) =
  Call (fn (Arg "a", Arg "b"), a, b)


data Expr
  = Arg      String
  | Int      (String, String)
  | Float    String
  | Not      (Expr)
  | Abs      (Expr)
  | Or       (Expr, Expr)
  | And      (Expr, Expr)
  | FAdd     (Expr, Expr)
  | FDivSig  (Expr, Expr)
  | FDivExp  (Expr, Expr)
  | FcmpOEQ  (Expr, Expr)
  | FcmpOLT  (Expr, Expr)
  | CopySign (Expr, Expr)
  | Call     (Expr, Expr, Expr)
  deriving Eq

data Type
  = Float1
  | Float2
  | Float4
  | Double1
  | Double2


-- Function type
--   name :: Int   The function index name.
--   expr :: Expr  The function body.
type Func = (Int, Expr)

-- Queue type
--   idx :: Int     The current index name.
--   fns :: [Func]  The list of queued functions.
type Queue = (Int, [Func])

-- Environment type
--   reg :: Int    The current register index.
--   ty  :: Type   The generation type.
--   q   :: Queue  The queue of named functions.
type Env = (Int, Type, Queue)

ite :: Expr -> Expr -> Expr -> Expr
ite b x y = 
  if x == y
    then x
    else Or (And (b, x), And (Not b, y))

ite2 :: Expr -> (Expr,Expr) -> (Expr,Expr) -> (Expr,Expr)
ite2 b (x1,x2) (y1,y2) = (ite b x1 y1, ite b x2 y2)

class WithBlind e f | e -> f where
  withBlind :: (e -> Expr)    -- ^ test
            -> (e -> e)       -- ^ blinder
            -> f              -- ^ fixer
            -> (e -> Expr)    -- ^ operation
            -> (e -> Expr)    -- ^ blinded-operation

instance WithBlind Expr (Expr -> Expr -> Expr) where
  withBlind cond blind fix op v =
    let b   = cond v
        tmp = ite b (blind v) v
        res = op tmp
        out = ite b (fix v res) res
    in out

instance WithBlind (Expr, Expr) ((Expr, Expr) -> Expr -> Expr) where
  withBlind cond blind fix op v =
    let b   = cond v
        tmp = ite2 b (blind v) v
        res = func op tmp
        out = ite b (fix v res) res
    in out

type FP1   = Expr
type FP2   = (FP1, FP1)
type UnOp  = FP1 -> FP1
type BinOp = FP2 -> FP2


-- underflow with one input
withUnderflow :: FP1 -> (FP1 -> FP1) -> FP1 -> FP1
withUnderflow lim =
  withBlind
    (\v -> FcmpOLT(Abs(v), lim))
    (\v -> Float "0.0")
    (\v r -> CopySign(r, v))

-- underflow only on the first input
withUnderflow1 :: FP1 -> (FP2 -> FP1) -> FP2 -> FP1
withUnderflow1 lim =
  withBlind
    (\(v,_) -> FcmpOLT(Abs(v), lim))
    (\(v, w) -> (Float "0.0", w))
    (\v r -> r)

-- underflow only on the second input
withUnderflow2 :: FP1 -> (FP2 -> FP1) -> FP2 -> FP1
withUnderflow2 lim =
  withBlind
    (\(_,v) -> FcmpOLT(v, lim))
    (\(w,v) -> (w, Float "0.0"))
    (\_ r -> r)




infixr 8 @@

(@@):: ((a -> b) -> (a -> b)) -> (a -> b) -> (a -> b)
tx @@ f = tx f


-- ## HELPERS ## --

-- extract the exponent component
get_exp :: Expr -> Expr
get_exp e =
  And (e, Int ("0x7F800000", "0x7FF0000000000000") )

-- extract the significand component
get_sig :: Expr -> Expr
get_sig e =
  Or ( And (e, Int ("0x007FFFFF", "0x000FFFFFFFFFFFFF") ), Float "1.0" )



-- ## STRATEGIES ## --

with_dummy1 :: FP1 -> FP1 -> FP1 -> (FP2 -> FP1) -> FP2 -> FP1
with_dummy1 badIn badOut safeIn op (v1, v2) =
  withBlind
    (\(v,w) -> FcmpOEQ (v, badIn))
    (\(v,w) -> (safeIn, w))
    (\_ _ -> CopySign(badOut, v1))
    op
    (v1, v2)

-- compare and replace both inputs if matching the bad input
with_dummy' :: FP2 -> FP1 -> FP1 -> (FP2 -> FP1) -> FP2 -> FP1
with_dummy' badIn badOut safeIn op (v1, v2) =
  withBlind
    (\(v,w) -> And(FcmpOEQ (v, fst badIn), FcmpOEQ (w, snd badIn)))
    (\(v,w) -> (safeIn, safeIn))
    (\_ _ -> badOut)
    op
    (v1, v2)

with_dummy1' :: FP1 -> FP1 -> FP1 -> (FP2 -> FP1) -> FP2 -> FP1
with_dummy1' badIn badOut safeIn op (v1, v2) =
  withBlind
    (\(v,_) -> FcmpOEQ (v, badIn))
    (\(v,w) -> (safeIn, safeIn))
    (\_ _ -> badOut)
    op
    (v1, v2)

with_dummy2' :: FP1 -> FP1 -> FP1 -> (FP2 -> FP1) -> FP2 -> FP1
with_dummy2' badIn badOut safeIn op (v1, v2) =
  withBlind
    (\(_,w) -> FcmpOEQ (w, badIn))
    (\(v,w) -> (safeIn, safeIn))
    (\_ _ -> badOut)
    op
    (v1, v2)

-- divide only by the exponent component of the inputs
div_exp :: (FP2 -> FP1) -> FP2 -> FP1
div_exp =
  withBlind
    (\_ -> val_true)
    (\(w,v) -> (FDivExp(w, get_exp v), get_sig v))
    --(\(w,v) -> (w, get_exp(v)))
    (\v r -> r)

-- prevent division by one using a dummy
div_noop op (a, b) =
  withBlind
    (\(u,v) -> FcmpOEQ(v, val_one))
    (\_ -> (val_dummy, val_dummy))
    (\_ _ -> a)
    op
    (a, b)

-- values
val_true = Int ("-1", "-1")
val_false = Int ("0", "0")
val_zero = Float "0.0"
val_one = Float "1.0"
val_dummy = Float "1.5"
val_nan = Int ("0x7FC00000", "0x7FF8000000000000")
val_inf = Int ("0x7F800000", "0x7FF0000000000000")

-- constants
addmin = "9.8607613152626476e-32"


-- ## RESTRICT ## --

-- addition
restrict_add :: FP2 -> FP1
restrict_add =
  withUnderflow1 (Float addmin) @@
  withUnderflow2 (Float addmin) @@
  FAdd


-- division
restrict_div :: FP2 -> FP1
restrict_div =
  with_dummy' (val_zero, val_zero) val_nan val_dummy @@
  with_dummy' (val_inf, val_inf) val_nan val_dummy @@
  with_dummy1' val_zero val_zero val_dummy @@
  with_dummy1' val_inf val_inf val_dummy @@
  with_dummy2' val_zero val_inf val_dummy @@
  with_dummy2' val_inf val_zero val_dummy @@
  div_exp @@
  div_noop @@
  FDivSig


name :: Env -> Expr -> (Env, String)
name (i, t, (name, fns)) expr =
  let env' = (i, t, (name+1, (name, expr):fns)) in
    (env', "fn_"++(show name))


-- allocate a register from the environment
alloc :: Env -> (Env, String)
alloc (i, t, q) = ((i+1, t, q), "%"++(show i))

-- allocate an array of registers from the environment
allocs :: Env -> Int -> (Env, [String])
allocs e n =
  if n == 0
    then (e, [])
    else let ((i,t,q),ns) = allocs e (n-1) in
      ((i+1,t,q),ns++["%"++(show i)])


floats :: Env -> String -> String
floats (i, t, q) v =
  case t of
    Float1 -> v
    Float2 -> "< float " ++ v ++ ", float " ++ v ++ " >"
    Float4 -> "< float " ++ v ++ ", float " ++ v ++ ", float " ++ v ++ ", float " ++ v ++ " >"
    Double1 -> v
    Double2 -> "< double " ++ v ++ ", double " ++ v ++ " >"

ints :: Env -> String -> String
ints (i, t, q) v =
  case t of
    Float1 -> v
    Float2 -> "< i32 " ++ v ++ ", i32 " ++ v ++ " >"
    Float4 -> "< i32 " ++ v ++ ", i32 " ++ v ++ ", i32 " ++ v ++ ", i32 " ++ v ++ " >"
    Double1 -> v
    Double2 -> "< i64 " ++ v ++ ", i64 " ++ v ++ " >"


-- create an integer values of all ones
ones :: Env -> String
ones e = ints e "-1"

-- create an integer values of all zeros
zeros :: Env -> String
zeros e = ints e "0"


-- select a string using the type
type2sel :: Type -> (String, String) -> String
type2sel Float1 p = fst p
type2sel Float2 p = fst p
type2sel Float4 p = fst p
type2sel Double1 p = snd p
type2sel Double2 p = snd p

-- select a string using the environment
env2sel :: Env -> (String, String) -> String
env2sel (_,t,_) p = type2sel t p

-- convert a type to the floating-point type string
type2flt :: Type -> String
type2flt Float1 = "float"
type2flt Float2 = "< 2 x float >"
type2flt Float4 = "< 4 x float >"
type2flt Double1 = "double"
type2flt Double2 = "< 2 x double >"

-- generate float type string from the environment
env2flt :: Env -> String
env2flt (_,t,_) = type2flt t

-- convert a type to the integer type string
type2int :: Type -> String
type2int Float1 = "i32"
type2int Float2 = "< 2 x i32 >"
type2int Float4 = "< 4 x i32 >"
type2int Double1 = "i64"
type2int Double2 = "< 2 x i64 >"

-- generate integer type string from the environment
env2int :: Env -> String
env2int (_,t,_) = type2int t

-- convert a type to the boolean type string
type2bool :: Type -> String
type2bool Float1 = "i1"
type2bool Float2 = "< 2 x i1 >"
type2bool Float4 = "< 4 x i1 >"
type2bool Double1 = "i1"
type2bool Double2 = "< 2 x i1 >"

-- generate boolean type string from the environment
env2bool :: Env -> String
env2bool (_,t,_) = type2bool t

-- convert a type to the vectorized builtin string
type2vec :: Type -> String
type2vec Float1 = "f32"
type2vec Float2 = "v2f32"
type2vec Float4 = "v4f32"
type2vec Double1 = "f64"
type2vec Double2 = "v2f64"

-- generate vectorized name from the environment
env2vec :: Env -> String
env2vec (_,t,_) = type2vec t


gen_unnamed :: [Func] -> Type -> Int -> IO ()
gen_unnamed [] _ _ = return ()
gen_unnamed ((nam, expr):fns) t idx =
  let ty = type2flt t in
    do putStr $ "define weak " ++ ty ++ " @fn_" ++ (show nam) ++ "(" ++ ty ++ " %a, " ++ ty ++ " %b) {\n"
       (r,(_,_,(idx',fns'))) <- gen_expr (expr, (1, t, (idx, fns)))
       putStr $ "ret " ++ ty ++ " " ++ r ++ "\n}\n"
       gen_unnamed fns' t idx'

-- generate the code for a function
gen_func :: ((Expr, Expr) -> Expr) -> Type -> String -> IO ()
gen_func f t n = 
  let ty = type2flt t in
    do
       putStr $ "define weak " ++ ty ++ " @" ++ n ++ "(" ++ ty ++ " %a, " ++ ty ++ " %b) {\n"
       (r,(_,_,(idx,fns))) <- gen_expr (f (Arg "a", Arg "b"), (1, t, (1, [])))
       putStr $ "ret " ++ ty ++ " " ++ r ++ "\n}\n"
       gen_unnamed fns t idx

-- generate code for an arbitrary expression
gen_expr :: (Expr, Env) -> IO (String, Env)
gen_expr (Arg s, env) = return ("%" ++ s, env)
gen_expr (Int val, env) = gen_int (env2sel env val, env)
gen_expr (Float val, env) = return (floats env val, env)
gen_expr (Not a, env) = gen_not (a, env)
gen_expr (Abs a, env) = gen_call1("llvm.fabs." ++ (env2vec env), a, env);
gen_expr (Or (a, b), env) = gen_iop2 ("or", a, b, env)
gen_expr (And (a, b), env) = gen_iop2 ("and", a, b, env)
gen_expr (FAdd (a, b), env) = if debug then gen_call2 ("dbg_fadd_" ++ (env2vec env), a, b, env) else gen_fop2 ("fadd", a, b, env)
gen_expr (FDivSig (a, b), env) = if debug then gen_call2 ("dbg_fdiv_sig_" ++ (env2vec env), a, b, env) else gen_fop2 ("fdiv", a, b, env)
gen_expr (FDivExp (a, b), env) = if debug then gen_call2 ("dbg_fdiv_exp_" ++ (env2vec env), a, b, env) else gen_fop2 ("fdiv", a, b, env)
gen_expr (FcmpOLT (a, b), env) = gen_fcmp ("fcmp olt", a, b, env)
gen_expr (FcmpOEQ (a, b), env) = gen_fcmp ("fcmp oeq", a, b, env)
gen_expr (CopySign (a, b), env) = gen_call2 ("llvm.copysign." ++ (env2vec env), a, b, env)
gen_expr (Call (fn, a, b),  env) = gen_call (fn, a, b, env)

gen_call :: (Expr, Expr, Expr, Env) -> IO (String, Env)
gen_call (fn, a, b, env) =
  do (ra, env) <- gen_expr (a, env)
     (rb, env) <- gen_expr (b, env)
     let (env',r) = alloc env in
       let (env'',func) = name env' fn in
         let flt = env2flt env'' in 
           do putStr $ r++" = call "++flt++" @"++func++"("++flt++" "++ra++", "++flt++" "++rb++")\n"
              return (r, env'')

-- generate an integer constant
gen_int :: (String, Env) -> IO (String, Env)
gen_int (int, env) =
  let (env',r) = alloc env in
    do putStr $ r++" = bitcast "++(env2int env')++" "++(show (read int::Int))++" to "++(env2flt env')++"\n"
       return (r, env')

-- generate a bitwise not
gen_not :: (Expr, Env) -> IO (String, Env)
gen_not (a, env) =
  do (ra, env) <- gen_expr (a, env)
     let (env',[ra',rt,ro]) = allocs env 3 in
       do putStr $ ra'++" = bitcast "++(env2flt env')++" "++ra++" to "++(env2int env')++"\n"
          putStr $ rt++" = xor "++(env2int env')++" "++ra'++", "++(ones env')++"\n"
          putStr $ ro++" = bitcast "++(env2int env')++" "++rt++" to "++(env2flt env')++"\n"
          return (ro, env')

-- generate code for a two-operand integer operation
gen_iop2 :: (String, Expr, Expr, Env) -> IO (String, Env)
gen_iop2 (op, a, b, env) =
  do (ra, env) <- gen_expr (a, env)
     (rb, env) <- gen_expr (b, env)
     let (env',[ra',rb',rt,ro]) = allocs env 4 in
       do putStr $ ra'++" = bitcast "++(env2flt env)++" "++ra++" to "++(env2int env)++"\n"
          putStr $ rb'++" = bitcast "++(env2flt env)++" "++rb++" to "++(env2int env)++"\n"
          putStr $ rt++" = "++op++" "++(env2int env)++" "++ra'++", "++rb'++"\n"
          putStr $ ro++" = bitcast "++(env2int env)++" "++rt++" to "++(env2flt env)++"\n"
          return (ro, env')

-- generate code for a two-operand floating-point operation
gen_fop2 :: (String, Expr, Expr, Env) -> IO (String, Env)
gen_fop2 (op, a, b, env) =
  do (ra, env) <- gen_expr (a, env)
     (rb, env) <- gen_expr (b, env)
     let (env',ro) = alloc env in
       do putStr $ ro++" = "++op++" "++(env2flt env)++" "++ra++", "++rb++"\n"
          return (ro, env')

-- generate code for a floating-point comparison
gen_fcmp :: (String, Expr, Expr, Env) -> IO (String, Env)
gen_fcmp (cmp, a, b, env) =
  do (ra, env) <- gen_expr (a, env)
     (rb, env) <- gen_expr (b, env)
     let (env', [rt,rs,ro]) = allocs env 3 in
       do putStr $ rt++" = "++cmp++" "++(env2flt env')++" "++ra++", "++rb++"\n"
          putStr $ rs++" = select "++(env2bool env')++" "++rt++", "++(env2int env')++" "++(ones env')++", "++(env2int env')++" "++(zeros env')++"\n"
          putStr $ ro++" = bitcast "++(env2int env')++" "++rs++" to "++(env2flt env')++"\n"
          return (ro, env')

-- create a function call with one argument
gen_call1 :: (String, Expr, Env) -> IO (String, Env)
gen_call1 (fn, a, env) =
  do (ra, env) <- gen_expr (a, env)
     let (env', r) = alloc env in
       do putStr $ r++" = call "++(env2flt env')++" @"++fn++"("++(env2flt env')++" "++ra++")\n"
          return (r, env')

-- create a function call with one argument
gen_call2 :: (String, Expr, Expr, Env) -> IO (String, Env)
gen_call2 (fn, a, b, env) =
  do (ra, env) <- gen_expr (a, env)
     (rb, env) <- gen_expr (b, env)
     let (env', r) = alloc env in
       do putStr $ r++" = call "++(env2flt env')++" @"++fn++"("++(env2flt env')++" "++ra++", "++(env2flt env')++" "++rb++")\n"
          return (r, env')
