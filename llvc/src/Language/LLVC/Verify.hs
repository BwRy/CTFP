{-# LANGUAGE TypeSynonymInstances #-}
{-# LANGUAGE FlexibleInstances    #-}

module Language.LLVC.Verify (vcs) where 

import           Prelude hiding (pred)
import qualified Data.Maybe          as Mb 
import qualified Data.HashMap.Strict as M 
import           Data.Monoid
import qualified Language.LLVC.Parse as Parse 
import           Language.LLVC.UX 
import           Language.LLVC.Utils 
import           Language.LLVC.Smt   
import           Language.LLVC.Types hiding (contract) 

-------------------------------------------------------------------------------
vcs :: (Located a) => Program a -> [(Var, VC)] 
-------------------------------------------------------------------------------
vcs p   = [ (f, vcFun env fd fb)
          | (f, fd) <- M.toList p 
          , fb      <- Mb.maybeToList (fnBody fd)
          ] 
  where 
    env = mkEnv p 

vcFun :: (Located a) => Env -> FnDef a -> FnBody a -> VC 
vcFun env fd fb = comment    ("VC for: " ++  fnName fd)
               <> mconcatMap declare      (fnArgTys fd) 
               <> assert                   pre
               <> mconcatMap (vcStmt env) (fnStmts  fb)
               <> check      l' (subst su    post) 
  where 
    su          = [(retVar, retExp)]
    retExp      = snd (fnRet fb)
    pre         = ctPre  (fnCon fd)        
    post        = ctPost (fnCon fd)
    -- l           = sourceSpan (getLabel fd)
    l'          = mkError "Failed ensures check!" 
                $ sourceSpan (getLabel retExp)

vcStmt :: (Located a) => Env -> Stmt a -> VC 
vcStmt _ (SAssert p l) 
  = check err p 
  where 
    err = mkError "Failed assert" (sourceSpan l)
vcStmt env asgn@(SAsgn x (ECall fn tys tx l) _)
  =  comment (pprint asgn)
  <> declare (x, tx) 
  <> check err pre
  <> assert    post 
  where 
    (pre, post) = contractAt env fn x tys l 
    err         = mkError "Failed requires check" (sourceSpan l)

contractAt :: (Located a) => Env -> Fn -> Var -> [TypedArg a] -> a -> (Pred, Pred)
contractAt env fn rv tys l = (pre, post) 
  where 
    pre                    = subst su (ctPre  ct)
    post                   = subst su (ctPost ct)
    su                     = zip formals actuals 
    actuals                = EVar rv l : (snd <$> tys) 
    formals                = retVar    : ctParams ct
    ct                     = contract env fn (sourceSpan l) 

-------------------------------------------------------------------------------
-- | Contracts for all the `Fn` stuff.
-------------------------------------------------------------------------------
type Env = M.HashMap Fn Contract 

contract :: Env -> Fn -> SourceSpan -> Contract
contract env fn l = Mb.fromMaybe err (M.lookup fn env)
  where 
    err           = panic msg l 
    msg           = "Cannot find contract for: " ++ show fn

mkEnv :: Program a -> Env 
mkEnv p   = M.fromList (prims ++ defs) 
  where 
    prims = primitiveContracts 
    defs  = [ (FnFunc v, fnCon d)  | (v, d) <- M.toList p ]  

-- | We could parse these in too, in due course.
primitiveContracts :: [(Fn, Contract)]
primitiveContracts =  
  [ ( FnCmp Float Olt 
    , postCond 2 "(= %ret (fp.lt %arg0 %arg1))" 
    )
  , ( FnCmp (I 32) Slt 
    , postCond 2 "(= %ret (lt %arg0 %arg1))" 
    )
  , ( FnBin BvXor
    , postCond 2 "(= %ret (bvxor %arg0 %arg1))" 
    )
  , ( FnBin BvOr
    , postCond 2 "(= %ret (bvor  %arg0 %arg1))" 
    )
  , ( FnBin BvAnd
    , postCond 2 "(= %ret (bvand %arg0 %arg1))" 
    )
  , (FnBin FpAdd 
    , mkContract 2 
        "(and (fp_rng addmin %arg0) (fp_rng addmin %arg1))"
        "(= %ret (fp_add %arg0 %arg1))" 
    )
  , ( FnSelect   
    , postCond 3 "(= %ret (ite %arg0 %arg1 %arg2))" 
    )
  , ( FnBitcast (I 32) Float 
    , postCond 1 "(= %ret (to_fp_32 %arg0))" )

  , ( FnBitcast Float (I 32) 
    , postCond 1 "(= %ret (to_ieee_bv  %arg0))" )

  ] 

postCond :: Int -> Text -> Contract 
postCond n = mkContract n "true" 

mkContract :: Int -> Text -> Text -> Contract 
mkContract n tPre tPost = Ct 
  { ctParams = paramVar <$> [0..(n-1)]
  , ctPre    = pred tPre 
  , ctPost   = pred tPost 
  } 

pred :: Text -> Pred 
pred = Parse.parseWith Parse.predP "primitive-contracts" 

-- putStrLn $ printf "The value of %d in hex is: 0x%08x" i i
-- putStrLn $ printf "The value of %d in binary is: %b"  i i
