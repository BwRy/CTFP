{-# LANGUAGE TypeSynonymInstances #-}
{-# LANGUAGE FlexibleInstances    #-}
{-# LANGUAGE BangPatterns         #-}
{-# LANGUAGE OverloadedStrings    #-}

module Language.LLVC.Smt 
  ( -- * Opaque SMT Query type 
    VC

    -- * Opaque SMT Pred
  , SmtPred
  , smtPred

  -- * Constructing Queries
  , comment
  , declare
  , check
  , assert

  -- * Executing Query 
  , runQuery 

  -- * Issuing Query (deprecated)
  , writeQuery 
  ) 
  where 

import qualified Data.Text    as T
import qualified Data.Text.IO as TIO
import           System.IO    as IO 
import           System.Process
import           System.Directory 
import           System.FilePath 
import           Text.Printf (printf) 
import           Data.Monoid
import           Language.LLVC.Types 
import qualified Language.LLVC.Utils as Utils
import qualified Language.LLVC.UX    as UX
import qualified Data.HashMap.Strict as M 
import qualified Paths_llvc 

-------------------------------------------------------------------------------
-- | Query Saving API (not used) 
-------------------------------------------------------------------------------

writeQuery :: FilePath -> VC -> IO () 
writeQuery f vc = do 
  prelude  <- T.unpack <$> readPrelude 
  writeFile f $ prelude ++ toSmt vc 

readPrelude :: IO T.Text 
readPrelude = TIO.readFile =<< Paths_llvc.getDataFileName "include/prelude.smt2"

-------------------------------------------------------------------------------
-- | VC Construction API 
-------------------------------------------------------------------------------

comment :: UX.Text -> VC 
comment s = say $ printf "; %s" s

declare ::  (Var, Type) -> VC 
declare (x, t) = say $ printf "(declare-const %s %s)" (toSmt x) (toSmt t)

newtype SmtPred = SP Pred
smtPred :: Pred -> SmtPred 
smtPred = SP

assert :: SmtPred -> VC 
assert (SP PTrue) = mempty 
assert (SP p    ) = say $ printf "(assert %s)" (toSmt p)

check :: UX.UserError -> SmtPred -> VC 
check _ (SP PTrue) = mempty 
check e (SP p)     = withBracket (assert (SP (PNot p)) <> checkSat e)

withBracket :: VC -> VC 
withBracket vc = push <> vc <> pop 

push, pop :: VC 
push     = say  "(push 1)"
pop      = say  "(pop 1)"

checkSat :: UX.UserError -> VC
checkSat e = VC [ Hear "(check-sat-using (then (repeat (or-else split-clause skip)) (par-or (then solve-eqs simplify qffpbv) smt)))" Unsat e ]

say :: UX.Text -> VC
say s = VC [ Say s ]

-------------------------------------------------------------------------------
-- | VC "Execution" API 
-------------------------------------------------------------------------------
runQuery :: FilePath -> VC -> IO [UX.UserError]
runQuery f (VC cmds) = do 
  me <- makeContext f
  rs <- mapM (command me) cmds 
  return [ e | Fail e <- rs]

-------------------------------------------------------------------------------
-- | Internal (opaque) data types for SMT Interaction 
-------------------------------------------------------------------------------
type    Smt = UX.Text
newtype VC  = VC [Cmd] 
data Cmd    = Say  !Smt 
            | Hear !Smt !Response !UX.UserError 

instance Monoid VC where 
  mempty                  = VC [] 
  mappend (VC q1) (VC q2) = VC (q1 <> q2) 

data Response 
  = Ok 
  | Sat 
  | Unsat 
  | Fail  !UX.UserError 

instance Eq Response where 
  Ok    == Ok    = True 
  Sat   == Sat   = True 
  Unsat == Unsat = True 
  _     == _     = False 

command :: Context -> Cmd -> IO Response
command me !cmd = do 
  _    <- talk cmd 
  resp <- hear cmd
  case resp of
    Fail e -> Fail . UX.extError e . T.unpack <$> smtModel me 
    _      -> return Ok
  where
    talk              = smtWrite me . T.pack . toSmt 
    hear (Hear _ s e) = smtRead me >>= (\s' -> return $ if s == s' then Ok else Fail e)
    hear _            = return Ok


--------------------------------------------------------------------------------
-- | Interacting with the SMT Process 
--------------------------------------------------------------------------------

data Context = Ctx
  { ctxPid     :: !ProcessHandle
  , ctxCin     :: !Handle
  , ctxCout    :: !Handle
  , ctxLog     :: !(Maybe Handle)
  }

--------------------------------------------------------------------------------
makeContext :: FilePath -> IO Context
--------------------------------------------------------------------------------
makeContext smtFile = do 
  me       <- makeProcess 
  prelude  <- readPrelude 
  createDirectoryIfMissing True $ takeDirectory smtFile
  hLog     <- IO.openFile smtFile WriteMode
  let me'   = me { ctxLog = Just hLog }
  smtWrite me' prelude
  return me'

makeProcess :: IO Context
makeProcess = do 
  (hOut, hIn, _ ,pid) <- runInteractiveCommand "z3 --in" 
  return Ctx { ctxPid     = pid
             , ctxCin     = hIn
             , ctxCout    = hOut
             , ctxLog     = Nothing
             }

smtRead :: Context -> IO Response
smtRead me = textResponse <$> smtReadRaw me

textResponse :: T.Text -> Response 
textResponse s 
  | s == "sat"              = Sat 
  | s == "unsat"            = Unsat 
  | T.isPrefixOf "(model" s = error ("ohoho" ++ T.unpack s) 
  | otherwise               = error ("SMT: Unexpected response: " ++ T.unpack s)

smtWrite :: Context -> T.Text -> IO ()
smtWrite me !s = do
  hPutStrLnNow (ctxCout me) s
  case ctxLog me of 
    Just hLog -> hPutStrLnNow hLog s 
    Nothing   -> return ()

smtReadRaw       :: Context -> IO T.Text
smtReadRaw me    = TIO.hGetLine (ctxCin me)

hPutStrLnNow    :: Handle -> T.Text -> IO ()
hPutStrLnNow h s = TIO.hPutStrLn h s >> hFlush h

smtModel :: Context -> IO T.Text 
smtModel me = do 
  smtWrite me "(get-model)"
  T.unlines . reverse <$> go []
  where
    go :: [T.Text] -> IO [T.Text]
    go !acc = do 
      t <- smtReadRaw me
      if t == ")" 
        then return (t:acc)
        else go (t:acc) 

-------------------------------------------------------------------------------
-- | Serializing API
-------------------------------------------------------------------------------

class ToSmt a where 
  toSmt :: a -> Smt 

instance ToSmt VC where 
  toSmt (VC cmds) = unlines (toSmt <$> cmds) 

instance ToSmt Cmd where 
  toSmt (Say s)      = s 
  toSmt (Hear s _ _) = s 

instance ToSmt Op where 
  toSmt BvAnd     = "bvand"
  toSmt BvOr      = "bvor"
  toSmt BvXor     = "bvxor"
  toSmt FpAdd     = "fp_add" 
  toSmt FpSub     = "fp_sub" 
  toSmt FpMul     = "fp_mul" 
  toSmt FpDiv     = "fp_div" 
  toSmt FpEq      = "fp.eq" 
  toSmt FpAbs     = "fp.abs" 
  toSmt FpLt      = "fp.lt" 
  toSmt ToFp32    = "(_ to_fp 8 24)"
  toSmt Ite       = "ite" 
  toSmt Eq        = "=" 
  toSmt (SmtOp x) = x 

instance ToSmt (Arg a) where 
  toSmt (ETFlt n Float _)  = printf "((_ to_fp 8 24) roundTowardZero %s)" (show n)
  toSmt (ETFlt n Double _) = printf "((_ to_fp 11 53) roundTowardZero %s)" (show n)
  toSmt (ETFlt n _ _)      = show n -- Should not happen
  toSmt (ETLit n (I i) _)  = sigIntHex n (I i)
  toSmt (ETLit n Float _)  = printf "((_ to_fp 8 24) %s)" (sigIntHex n Float)
  toSmt (ETLit n Double _) = printf "(fp64_cast %s)" (sigIntHex n Double)
  toSmt (EFlt n    _)      = printf "((_ to_fp 8 24) roundTowardZero %s)" (show n)
  toSmt (ELit n    _)      = show n
  toSmt (EVar x    _)      = toSmt x 
  toSmt (ECon x    _)      = x 

convTable :: M.HashMap (Integer, Type) String
convTable = M.fromList 
  [ ((0x3980000000000000, Float), "#x0c000000") 
  , ((0x3980000020000000, Float), "#x0bffffff")
  , ((0x3C00000000000000, Float), "#x20000000") 
  , ((0x3C00000020000000, Float), "#x1fffffff") 
  , ((0x3FF0000000000000, Float), "#x3f800000") 
  , ((0x7FF0000000000000, Float), "#x7f800000") 
  , ((0x0000000000000000, Float), "#x00000000") 
  , ((0x3810000000000000, Float), "#x00800000")
  , ((0x43D0000000000000, Float), "#x5e800000")
  , ((0x43D0000020000000, Float), "#x5e800001")
  , ((0x3810000000000000, Float), "#x00800000")
  , ((0x380E666640000000, Float), "#x00799999")
  , ((0x4170000000000000, Float), "#x4b800000")
  , ((0x3990000000000000, Float), "#x0c800000")
  , ((0x47D0000000000000, Float), "#x7e800000")
  , ((-1                , I 32) , "#xffffffff")
  , ((-2                , I 32) , "#xfffffffe")
  ]

bwOfType :: Type -> Int
bwOfType Float = 32
bwOfType Double = 64
bwOfType (I n) = n

sigIntHex :: Integer -> Type -> Smt 
sigIntHex n t      = M.lookupDefault res (n, t) convTable
  where 
    bw             = bwOfType t
    vMax           = 2 ^ bw
    res 
      | 0 <= n     = "#x" ++ pad ++ nStr
      | n >= -vMax = sigIntHex (vMax + n) t
      | otherwise  = UX.panic ("sigIntHex: negative" ++ show n) UX.junkSpan
    nStr           = Utils.integerHex (abs n)
    pad            = replicate ((bw `div` 4) - length nStr) '0'

instance ToSmt Pred where 
  toSmt (PArg a)     = toSmt a 
  toSmt (PAtom o ps) = printf "(%s %s)"  (toSmt o) (toSmts ps) 
  toSmt (PNot p)     = printf "(not %s)" (toSmt p)
  toSmt (PAnd ps)    = printf "(and %s)" (toSmts ps)
  toSmt (POr  ps)    = printf "(or %s)"  (toSmts ps)
  toSmt PTrue        =        "true"     

toSmts :: (ToSmt a) => [a] -> Smt
toSmts = unwords . fmap toSmt

instance ToSmt Type where 
  toSmt Float  = "Float32" 
  toSmt Double = "Float64" 
  toSmt (I 1)  = "Bool" 
  toSmt (I 32) = "Int32" 
  toSmt (I 64) = "Int64" 
  toSmt (I n)  = UX.panic ("toSmt: Unhandled Int-" ++ show n) UX.junkSpan 

instance ToSmt Var where 
  toSmt = sanitizeVar

sanitizeVar :: Var -> Smt 
sanitizeVar ('%':cs) = 'r' : (sanitizeChar <$> cs) 
sanitizeVar cs       = sanitizeChar <$> cs 

sanitizeChar :: Char -> Char 
sanitizeChar '%' = '_'
sanitizeChar c   = c 
