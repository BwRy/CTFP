module Language.LLVC.Parse ( parse, parseFile ) where

import           Control.Monad (void)
import qualified Data.HashMap.Strict        as M 
import           Text.Megaparsec hiding (parse)
import           Data.List.NonEmpty         as NE
import qualified Text.Megaparsec.Char.Lexer as L
import           Text.Megaparsec.Char
import           Text.Megaparsec.Expr
import           Language.LLVC.Types
import           Language.LLVC.UX 

type Parser = Parsec SourcePos Text

--------------------------------------------------------------------------------
parseFile :: FilePath -> IO BareProgram 
--------------------------------------------------------------------------------
parseFile f = parse f <$> readFile f

--------------------------------------------------------------------------------
parse :: FilePath -> Text -> BareProgram 
----------------------------------------------------------------------------------
parse = parseWith prog

parseWith  :: Parser a -> FilePath -> Text -> a
parseWith p f s = case runParser (whole p) f s of
                    Left err -> panic (show err) (posSpan . NE.head . errorPos $ err)
                    Right e  -> e

-- https://mrkkrp.github.io/megaparsec/tutorials/parsing-simple-imperative-language.html
instance Located (ParseError a b) where
  sourceSpan = posSpan . NE.head . errorPos

instance (Show a, Show b) => PPrint (ParseError a b) where
  pprint = show

type BareProgram = Program SourceSpan 
type BareDef     = FnDef   SourceSpan 

--------------------------------------------------------------------------------
-- | Top-Level Expression Parser
--------------------------------------------------------------------------------

prog :: Parser BareProgram 
prog = do 
  ds    <- many fnDefnP 
  return $ M.fromList [(fnName d, d) | d <- ds] 

fnDefnP :: Parser BareDef 
fnDefnP 
  =  (rWord "declare" >> declareP) 
 <|> (rWord "define"  >> defineP)
 <?> "declaration" 

declareP :: Parser BareDef 
declareP = do 
  outTy      <- typeP 
  (name, sp) <- identifier "@" 
  inTys      <- parens (sepBy typeP comma) <* many attrP
  return (decl name inTys outTy sp)  

defineP :: Parser BareDef 
defineP = undefined 

typeP :: Parser Type 
typeP 
  =  (rWord "float" >> return Float)  
 <|> (rWord "i32"   >> return (I 32)) 
 <|> (rWord "i1"    >> return (I  1)) 
 <?> "type"

attrP :: Parser () 
attrP = symbol "#" >> integer >> return ()


{- 
expr :: Parser Bare
expr = makeExprParser expr0 binops

expr0 :: Parser Bare
expr0 =  try primExpr
     <|> try letExpr
     <|> try ifExpr
     <|> try getExpr
     <|> try appExpr
     <|> try tupExpr
     <|> try constExpr
     <|> idExpr

exprs :: Parser [Bare]
exprs = parens (sepBy1 expr comma)

--------------------------------------------------------------------------------
-- | Individual Sub-Expression Parsers
--------------------------------------------------------------------------------
decl :: Parser BareDecl
decl = withSpan' $ do
  rWord "def"
  f  <- binder
  xs <- parens (sepBy binder comma) <* colon
  e  <- expr
  return (Decl f xs e)

getExpr :: Parser Bare
getExpr = withSpan' (GetItem <$> funExpr <*> brackets expr)

appExpr :: Parser Bare
appExpr = withSpan' (App <$> (fst <$> identifier) <*> exprs)

funExpr :: Parser Bare
funExpr = try idExpr <|> tupExpr

tupExpr :: Parser Bare
tupExpr = withSpan' (mkTuple <$> exprs)

mkTuple :: [Bare] -> SourceSpan -> Bare
mkTuple [e] _ = e
mkTuple es  l = Tuple es l

binops :: [[Operator Parser Bare]]
binops =
  [ [ InfixL (symbol "*"  *> pure (op Times))
    ]
  , [ InfixL (symbol "+"  *> pure (op Plus))
    , InfixL (symbol "-"  *> pure (op Minus))
    ]
  , [ InfixL (symbol "==" *> pure (op Equal))
    , InfixL (symbol ">"  *> pure (op Greater))
    , InfixL (symbol "<"  *> pure (op Less))
    ]
  ]
  where
    op o e1 e2 = Prim2 o e1 e2 (stretch [e1, e2])

idExpr :: Parser Bare
idExpr = uncurry Id <$> identifier

constExpr :: Parser Bare
constExpr
   =  (uncurry Number <$> integer)
  <|> (Boolean True   <$> rWord "true")
  <|> (Boolean False  <$> rWord "false")

primExpr :: Parser Bare
primExpr = withSpan' (Prim1 <$> primOp <*> parens expr)

primOp :: Parser Prim1
primOp
  =  try (rWord "add1"    *> pure Add1)
 <|> try (rWord "sub1"    *> pure Sub1)
 <|> try (rWord "isNum"   *> pure IsNum)
 <|> try (rWord "isBool"  *> pure IsBool)
 <|> try (rWord "isTuple" *> pure IsTuple)
 <|>     (rWord "print"  *> pure Print)

letExpr :: Parser Bare
letExpr = withSpan' $ do
  rWord "let"
  bs <- sepBy1 bind comma
  rWord "in"
  e  <- expr
  return (bindsExpr bs e)

bind :: Parser (BareBind, Bare)
bind = (,) <$> binder <* symbol "=" <*> expr

ifExpr :: Parser Bare
ifExpr = withSpan' $ do
  rWord "if"
  b  <- expr
  e1 <- between colon elsecolon expr
  e2 <- expr
  return (If b e1 e2)
  where
   elsecolon = rWord "else" *> colon
-}
--------------------------------------------------------------------------------
-- | Tokenisers and Whitespace
--------------------------------------------------------------------------------

-- | Top-level parsers (should consume all input)
whole :: Parser a -> Parser a
whole p = sc *> p <* eof

-- RJ: rename me "space consumer"
sc :: Parser ()
sc = L.space (void spaceChar) lineCmnt blockCmnt
  where 
    lineCmnt  = L.skipLineComment  "; "
    blockCmnt = L.skipBlockComment "/*" "*/"

-- | `symbol s` parses just the string s (and trailing whitespace)
symbol :: String -> Parser String
symbol = L.symbol sc

comma :: Parser String
comma = symbol ","

colon :: Parser String
colon = symbol ":"



-- | 'parens' parses something between parenthesis.
parens :: Parser a -> Parser a
parens = betweenS "(" ")"

-- | 'brackets' parses something between [...] 
brackets :: Parser a -> Parser a
brackets = betweenS "[" "]"

-- | 'braces' parses something between {...}
braces :: Parser a -> Parser a
braces = betweenS "[" "]"


betweenS :: String -> String -> Parser a -> Parser a
betweenS l r = between (symbol l) (symbol r)

-- | `lexeme p` consume whitespace after running p
lexeme :: Parser a -> Parser (a, SourceSpan)
lexeme p = L.lexeme sc (withSpan p)

-- | 'integer' parses an integer.
integer :: Parser (Integer, SourceSpan)
integer = lexeme L.decimal

-- | `rWord`
rWord   :: String -> Parser SourceSpan
rWord w = snd <$> (withSpan (string w) <* notFollowedBy alphaNumChar <* sc)

-- | list of reserved words
keywords :: [Text]
keywords =
  [ "define", "declare", "weak"
  , "float", "i32", "i1"
  , "call"
  , "fcmp", "olt", "select"
  , "bitcast", "to"
  , "and", "or"
  , "ret"
  ]

withSpan' :: Parser (SourceSpan -> a) -> Parser a
withSpan' p = do
  p1 <- getPosition
  f  <- p
  p2 <- getPosition
  return (f (SS p1 p2))

withSpan :: Parser a -> Parser (a, SourceSpan)
withSpan p = do
  p1 <- getPosition
  x  <- p
  p2 <- getPosition
  return (x, SS p1 p2)

-- | `binder` parses BareBind, used for let-binds and function parameters.
-- binder :: Parser BareBind
-- binder = uncurry Bind <$> identifier

varP :: Text -> Parser Var
varP s = fst <$> identifier s 

identifier :: Text -> Parser (String, SourceSpan)
identifier s = lexeme (p >>= check)
  where
    p       = (++) <$> symbol s <*> many identChar 
    check x = if x `elem` keywords
                then fail $ "keyword " ++ show x ++ " cannot be an identifier"
                else return x

identChar :: Parser Char
identChar = oneOf ok <?> "identifier-char"
  where 
    ok    = "._" ++ ['0'.. '9'] ++ ['a' .. 'z'] ++ ['A' .. 'Z']

stretch :: (Monoid a) => [Expr a] -> a
stretch = mconcat . fmap getLabel

