module Penny.Wheat
  ( -- * Basic predicates
    Pdct
  , payee
  , number
  , flag
  , postingMemo
  , transactionMemo
  , dateTime
  , CompQty(..)
  , qty
  , drCr
  , commodity
  , accountIs
  , account
  , accountLevel
  , accountAny
  , tag

  -- * Convenience predicates
  , reconciled

  -- * Other conveniences
  , futureFirstsOfTheMonth

  -- * Account tests
  , BoundSpec(..)
  , DateSpec
  , anyDate
  , AccountSpec
  , accountTests

  -- * Configuration and CLI
  , ColorToFile
  , BaseTime
  , CurrTime
  , WheatConf(..)
  , wheatMain

  -- * Re-exports
  , S.Runtime
  , S.currentTime
  , module Text.Matchers
  , module Penny.Steel.Prednote
  , module Data.Time
  ) where

import Control.Applicative
import Control.Arrow (second)
import Control.Monad (join, replicateM)
import qualified Control.Monad.Exception.Synchronous as Ex
import Data.List (intersperse)
import qualified Data.Map as Map
import Data.Maybe (mapMaybe)
import qualified Penny.Steel.Prednote as N
import qualified Penny.Copper as Cop
import qualified Penny.Copper.Parsec as CP
import qualified Penny.Lincoln.Predicates as P
import qualified Penny.Lincoln.Queries as Q
import qualified Penny.Lincoln as L
import qualified Data.Text as X
import qualified Penny.Lincoln.Builders as Bd
import Data.Text (Text, pack)
import qualified Data.Time as T
import qualified Data.Tree as E
import qualified Text.Matchers as M
import qualified Text.Parsec as Parsec
import qualified System.Console.MultiArg as MA
import qualified System.Console.Terminfo as TI
import qualified System.Exit as Exit
import System.Locale (defaultTimeLocale)
import qualified System.IO as IO
import qualified Penny.Shield as S

import Text.Matchers
import Penny.Steel.Prednote hiding (Pdct)
import Data.Time

type Pdct = N.Pdct L.PostFam

-- * Pattern matching fields

descItem :: Text -> M.Matcher -> Text
descItem s m = X.concat
  [ pack "field: ", s,  pack "; matcher description: ",
    (M.matchDesc m) ]

payee :: M.Matcher -> Pdct
payee p = pdct (descItem (pack "payee") p) (P.payee (M.match p))


number :: M.Matcher -> Pdct
number p = pdct (descItem (pack "number") p) (P.number (M.match p))

flag :: M.Matcher -> Pdct
flag p = pdct (descItem (pack "flag") p) (P.flag (M.match p))

postingMemo :: M.Matcher -> Pdct
postingMemo p = pdct (descItem (pack "posting memo") p)
                (P.postingMemo (M.match p))

transactionMemo :: M.Matcher -> Pdct
transactionMemo p = pdct (descItem (pack "transaction memo") p)
                (P.transactionMemo (M.match p))

-- * UTC times

dateTime :: M.CompUTC -> T.UTCTime -> Pdct
dateTime c t = pdct (pack "posting "
                    `X.append` (pack $ M.descUTC c t)) p
  where
    p = (`cmp` t) . L.toUTC . Q.dateTime
    cmp = M.compUTCtoCmp c

-- * Quantities

data CompQty
  = QGT
  | QGTEQ
  | QEQ
  | QLTEQ
  | QLT

descQty :: CompQty -> L.Qty -> Text
descQty c q = X.concat [ pack "quantity of posting is ", co,
                         pack " ", pack . show $ q]
  where
    co = pack $ case c of
      QGT -> "greater than"
      QGTEQ -> "greater than or equal to"
      QEQ -> "equal to"
      QLTEQ -> "less than or equal to"
      QLT -> "less than"

qty :: CompQty -> L.Qty -> Pdct
qty c q = pdct (descQty c q) p
  where
    p = (`cmp` q) . Q.qty
    cmp = case c of
      QGT -> (>)
      QGTEQ -> (>=)
      QEQ -> (==)
      QLTEQ -> (<=)
      QLT -> (<)

-- * DrCr

drCr :: L.DrCr -> Pdct
drCr dc = pdct (pack "posting is a " `X.append` desc) p
  where
    desc = pack $ case dc of
      L.Debit -> "debit"
      L.Credit -> "credit"
    p = (== dc) . Q.drCr

-- * Commodity

commodity :: M.Matcher -> Pdct
commodity p = pdct (descItem (pack "commodity") p) (P.commodity (M.match p))

-- * Account name

-- | Exactly matches the given account (case sensitive).
accountIs :: X.Text -> Pdct
accountIs a = pdct ((pack "account name is: ") `X.append` a) f
  where
    f = (== Bd.account a) . Q.account

account :: M.Matcher -> Pdct
account p = pdct (descItem (pack "full account name") p)
            (P.account (X.singleton ':') (M.match p))

accountLevel :: Int -> M.Matcher -> Pdct
accountLevel i p = pdct (descItem ((pack "sub-account ")
                         `X.append` (pack . show $ i)) p)
                   (P.accountLevel i (M.match p))

accountAny :: M.Matcher -> Pdct
accountAny p = pdct (descItem (pack "any sub-account") p)
               (P.accountAny (M.match p))

-- * Tags

tag :: M.Matcher -> Pdct
tag p = pdct (descItem (pack "any tag") p) (P.tag (M.match p))

------------------------------------------------------------
-- Convenience predicates
------------------------------------------------------------

-- | True if a posting is reconciled.
reconciled :: Pdct
reconciled =
  pdct (pack "posting flag is exactly \"R\" (is reconciled)")
  (maybe False ((== X.singleton 'R'). L.unFlag) . Q.flag)

------------------------------------------------------------
-- Other conveniences
------------------------------------------------------------


-- | A non-terminating list of starting with the first day of the
-- first month following the given day, followed by successive first
-- days of the month.
futureFirstsOfTheMonth :: T.Day -> [T.Day]
futureFirstsOfTheMonth d = iterate (T.addGregorianMonthsClip 1) d1
  where
    d1 = T.fromGregorian yr mo 1
    (yr, mo, _) = T.toGregorian $ T.addGregorianMonthsClip 1 d

------------------------------------------------------------
-- CLI
------------------------------------------------------------

type ProgName = String
type BriefDesc = String
type ColorToFile = Bool
type CurrTime = L.DateTime
type BaseTime = L.DateTime
type MoreHelp = [String]

help
  :: ProgName
  -> BriefDesc
  -> N.PassVerbosity
  -> N.FailVerbosity
  -> N.SpaceCount
  -> ColorToFile
  -> BaseTime
  -> MoreHelp
  -> String
help pn bd pv fv sc ctf bt mh = unlines $
  [ "usage: " ++ pn ++ "[options] ARGS"
  , ""
  , bd
  , "Options:"
  , ""
  , "--color-to-file no|yes"
  , "  If yes, use colors even when standard output is"
  , "  not a terminal. (default: " ++ dCtf ++ ")"
  , ""
  , "--pass-verbosity, -p VERBOSITY"
  , "--fail-verbosity, -f VERBOSITY"
  , "  Use the given level of verbosity for passing or for"
  , "  failing tests (each may be set independently.) Choices:"
  , "    silent - show nothing at all"
  , "    status - show only that the test passed or failed"
  , "    interesting - show that the test passed or failed, and"
  , "      the interesting results of the underlying predicates"
  , "    all - show that the test passed or failed, and all"
  , "      results from the underlying predicates"
  , "    (default pass verbosity: " ++ descV pv ++ ")"
  , "    (default fail verbosity: " ++ descV fv ++ ")"
  , ""
  , "--indentation, -i SPACES"
  , "  indent each level by this many spaces"
  , "  (default: " ++ dSc ++ ")"
  , ""
  , "--base-date, -d DATE"
  , "  use this date as basis for checks"
  , "  (currently: " ++ showDateTime bt ++ ")"
  , ""
  , "--help, -h - show help and exit"
  , ""
  ] ++ mh
  where
    dCtf = if ctf then "yes" else "no"
    descV v = case v of
      N.Silent -> "silent"
      N.Status -> "status"
      N.Interesting -> "interesting"
      N.All -> "all"
    dSc = show sc

showDateTime :: L.DateTime -> String
showDateTime (L.DateTime d h m s tz) =
  ds ++ " " ++ hmss ++ " " ++ showOffset
  where
    ds = show d
    hmss = hs ++ ":" ++ ms ++ ":" ++ ss
    hs = pad0 . show . L.unHours $ h
    ms = pad0 . show . L.unMinutes $ m
    ss = pad0 . show . L.unSeconds $ s
    pad0 str = if length str < 2 then '0':str else str
    showOffset =
      let (zoneHr, zoneMin) = abs (L.offsetToMins tz) `divMod` 60
          sign = if L.offsetToMins tz < 0 then "-" else "+"
      in sign ++ pad0 (show zoneHr) ++ pad0 (show zoneMin)

data Arg
  = AHelp
  | APassV N.Verbosity
  | AFailV N.Verbosity
  | AColorToFile ColorToFile
  | AIndentation N.SpaceCount
  | ABaseTime L.DateTime
  | APosArg String
  deriving Eq

optHelp :: MA.OptSpec Arg
optHelp = MA.OptSpec ["help"] "h" (MA.NoArg AHelp)

lsVerbosity :: [(String, N.Verbosity)]
lsVerbosity = [ ("silent", N.Silent)
              , ("status", N.Status)
              , ("interesting", N.Interesting)
              , ("all", N.All)
              ]

optPassVerbosity :: MA.OptSpec Arg
optPassVerbosity = MA.OptSpec ["pass-verbosity"] "p" (MA.ChoiceArg ls)
  where
    ls = fmap (second APassV) lsVerbosity

optFailVerbosity :: MA.OptSpec Arg
optFailVerbosity = MA.OptSpec ["fail-verbosity"] "f" (MA.ChoiceArg ls)
  where
    ls = fmap (second AFailV) lsVerbosity

optColorToFile :: MA.OptSpec Arg
optColorToFile = MA.OptSpec ["color-to-file"] "" (MA.ChoiceArg ls)
  where
    ls = fmap (second AColorToFile) [ ("no", False), ("yes", True) ]

type ExS = Ex.Exceptional String
optIndentation :: MA.OptSpec (ExS Arg)
optIndentation = MA.OptSpec ["indentation"] "i" (MA.OneArg f)
  where
    f s =
      let err = Ex.throw $ "improper indentation argument: " ++ s
      in case reads s of
          (i, ""):[] ->
            if i >= 0 then Ex.Success (AIndentation i) else err
          _ -> err

optBaseTime :: MA.OptSpec (ExS Arg)
optBaseTime = MA.OptSpec ["base-date"] "b" (MA.OneArg f)
  where
    f s = case Parsec.parse CP.dateTime  "" (X.pack s) of
      Left e -> Ex.throw $ "could not parse date: " ++ show e
      Right g -> return . ABaseTime $ g

type ParsedOpts = ( N.PassVerbosity, N.FailVerbosity, N.SpaceCount,
                    ColorToFile, BaseTime, [String])

data ParseResult
  = NeedsHelp
  | ParseErr String
  | Parsed ParsedOpts

-- | When passed the defaults, return the values to use, as they might
-- have been affected by the command arguments, or return Nothing if
-- help is needed.
parseArgs
  :: N.PassVerbosity
  -> N.FailVerbosity
  -> N.SpaceCount
  -> ColorToFile
  -> BaseTime
  -> [String]
  -> ParseResult
parseArgs pv fv sc ctf bt ss =
  let exLs = MA.simple MA.Intersperse opts (return . APosArg) ss
      opts = [ fmap return optHelp
             , fmap return optPassVerbosity
             , fmap return optFailVerbosity
             , fmap return optColorToFile
             , optIndentation
             , optBaseTime
             ]
  in case exLs of
      Ex.Exception e -> ParseErr . show $ e
      Ex.Success ls -> case sequence ls of
        Ex.Exception e -> ParseErr e
        Ex.Success ls' ->
          if AHelp `elem` ls'
          then NeedsHelp
          else Parsed ( (getPassVerbosity pv ls'), (getFailVerbosity fv ls')
                        , (getSpaceCount sc ls')
                        , (getColorToFile ctf ls'), (getBaseTime bt ls')
                        , (getPosArg ls'))

getPassVerbosity :: N.PassVerbosity -> [Arg] -> N.PassVerbosity
getPassVerbosity v as = case mapMaybe f as of
  [] -> v
  xs -> last xs
  where f a = case a of { APassV vb -> Just vb; _ -> Nothing }

getFailVerbosity :: N.FailVerbosity -> [Arg] -> N.FailVerbosity
getFailVerbosity v as = case mapMaybe f as of
  [] -> v
  xs -> last xs
  where f a = case a of { AFailV vb -> Just vb; _ -> Nothing }

getSpaceCount :: N.SpaceCount -> [Arg] -> N.SpaceCount
getSpaceCount sc as = case mapMaybe f as of
  [] -> sc
  xs -> last xs
  where f a = case a of { AIndentation i -> Just i; _ -> Nothing }

getColorToFile :: ColorToFile -> [Arg] -> ColorToFile
getColorToFile ctf as = case mapMaybe f as of
  [] -> ctf
  xs -> last xs
  where f a = case a of { AColorToFile i -> Just i; _ -> Nothing }

getPosArg :: [Arg] -> [String]
getPosArg = mapMaybe f
  where f a = case a of { APosArg s -> Just s; _ -> Nothing }

getBaseTime :: BaseTime -> [Arg] -> BaseTime
getBaseTime bd as = case mapMaybe f as of
  [] -> bd
  xs -> last xs
  where f a = case a of { ABaseTime x -> Just x; _ -> Nothing }

data WheatConf = WheatConf
  { briefDescription :: String
  , moreHelp :: [String]
  , passVerbosity :: N.PassVerbosity
  , failVerbosity :: N.FailVerbosity
  , spaceCount :: N.SpaceCount
  , colorToFile :: ColorToFile
  , tests :: CurrTime -> BaseTime -> [N.Test L.PostFam]
  , baseTime :: BaseTime
  }

applyParse
  :: ProgName
  -> WheatConf
  -> [String]
  -> IO ParsedOpts
applyParse pn c as =
  case parseArgs (passVerbosity c) (failVerbosity c) (spaceCount c)
       (colorToFile c) (baseTime c) as of
    NeedsHelp -> do
      putStrLn (help pn (briefDescription c)
                (passVerbosity c) (failVerbosity c)
                (spaceCount c) (colorToFile c) (baseTime c)
                (moreHelp c))
      Exit.exitSuccess
    ParseErr e -> do
      putStrLn $ pn ++ ": could not parse command line: " ++ e
      Exit.exitFailure
    Parsed r -> return r

wheatMain :: (S.Runtime -> WheatConf) -> IO ()
wheatMain getConf = do
  rt <- S.runtime
  let currTime = S.currentTime rt
  pn <- MA.getProgName
  as <- MA.getArgs
  let c = getConf rt
  (pv, fv, sc, ctf, bt, posargs) <- applyParse pn c as
  let getTerm =
        if ctf || (S.output rt == S.IsTTY)
        then TI.setupTermFromEnv
        else TI.setupTerm "dumb"
  ti <- getTerm
  let runTests is = map (N.runTest pv fv is 0) (tests c currTime bt)
  good <- fmap and
          . join
          . fmap (mapM (N.showResults ti sc display))
          . fmap runTests
          $ getItems pn posargs
  if good
    then Exit.exitSuccess
    else Exit.exitFailure

-- | Displays a PostFam in a one line format.
--
-- Format:
--
-- File LineNo Date Payee Acct DrCr Cmdty Qty
display :: L.PostFam -> Text
display p = X.pack $ concat (intersperse " " ls)
  where
    ls = [file, lineNo, dt, pye, acct, dc, cmdty, qt]
    file = maybe (labelNo "filename") (X.unpack . L.unFilename)
           (Q.filename p)
    lineNo = maybe (labelNo "line number")
             (show . L.unPostingLine) (Q.postingLine p)
    dateFormat = "%Y-%m-%d %T %z"
    dt = T.formatTime defaultTimeLocale dateFormat
         . T.utctDay
         . L.toUTC
         . Q.dateTime
         $ p
    pye = maybe (labelNo "payee")
            (X.unpack . L.text) (Q.payee p)
    acct = X.unpack . X.intercalate (X.singleton ':')
           . map L.unSubAccount . L.unAccount . Q.account $ p
    dc = case Q.drCr p of
      L.Debit -> "Dr"
      L.Credit -> "Cr"
    cmdty = X.unpack . L.unCommodity . Q.commodity $ p
    qt = show . Q.qty $ p

labelNo :: String -> String
labelNo s = "(no " ++ s ++ ")"

getItems :: ProgName -> [String] -> IO [L.PostFam]
getItems pn ss = Cop.openStdin ss >>= f
  where
    f res = case res of
      Ex.Exception e -> do
        IO.hPutStrLn IO.stderr $ pn
          ++ ": error: could not parse ledgers: "
          ++ (X.unpack . Cop.unErrorMsg $ e)
        Exit.exitFailure
      Ex.Success g ->
        let toTxn i = case i of { Cop.Transaction x -> Just x; _ -> Nothing }
        in return . concatMap L.postFam
           . mapMaybe toTxn . Cop.unLedger $ g

--
-- Account testers
--

-- | Specifies a bound on the valid dates of an account.
data BoundSpec
  = Inf
  -- ^ Infinity
  | Bound T.UTCTime

-- | A range of dates. This is closed ended on the left, open ended on
-- the right; that is, [x, y).
type DateSpec = (BoundSpec, BoundSpec)

anyDate :: DateSpec
anyDate = (Inf, Inf)

-- | A specification for a valid account. A posting has a valid
-- account if its name exactly matches the name given here and if it
-- matches at least one of the DateSpec in the list. If there are no
-- DateSpec in the list, postings in this account will never be valid.
type AccountSpec = (L.Account, [DateSpec])

-- | Returns a Test that examines the account name and date of a
-- posting to ensure both are good.
accountTests :: [AccountSpec] -> N.Test L.PostFam
accountTests as = N.eachSubjectMustBeTrue tn p
  where
    tn = X.pack "Account name and date is valid"
    p = N.Pdct fn
    fn pf = E.Node (psd, tn, i) cs
      where
        acctMap = Map.fromList as
        (psd, i, cs) = case Map.lookup (Q.account pf) acctMap of
          Nothing -> (False, True, [])
          Just ls -> (dm, not dm, [c1, c2])
            where
              c1 = E.Node (True, tnn, False) []
                where tnn = X.pack "Account name is valid"
              c2 = E.Node (dm, tnn, not dm) []
                where
                  tnn = X.pack $ "Posting date is in " ++
                                 "valid range for account"
              dm = any (dateMatches (Q.dateTime pf)) ls

-- | Does this date fall within the given DateSpec?
dateMatches :: L.DateTime -> DateSpec -> Bool
dateMatches dt (l, u) = above && below
  where
    ut = L.toUTC dt
    above = case l of
      Inf -> True
      Bound x -> x <= ut
    below = case u of
      Inf -> True
      Bound x -> ut < x

type FirstPurch = T.Day

-- | Creates a predicate for commodity purchases.
--
-- When you buy a commodity, you will need to set up two additional
-- accounts: a Basis account for each purchase and a Proceeds account
-- for each sale. This function creates the necessary predicate for
-- you. It checks postings to see if they in the Basis or Proceeds
-- account for this commodity.

commodityPredicate
  :: L.Commodity
  -- ^ The commodity you are purchasing
  -> FirstPurch
  -- ^ The first day you purchased the commodity
  -> CurrTime
  -- ^ Today
  -> N.Pdct L.PostFam
commodityPredicate cy fp ct = undefined

capitalChangePredicate
  :: L.Commodity
  -> FirstPurch
  -> CurrTime
  -> N.Pdct L.PostFam
capitalChangePredicate cy fp ct = undefined

capFirstAccts :: L.Account -> E.Tree N.PdctOutput
capFirstAccts ac = E.Node (psd, nm, ii) []
  where
    nm = X.pack $ "Account is Expenses:Capital Loss or "
                ++ "Income:Capital Gain"
    (psd, ii) = case (extractSubAcct 0 ac, extractSubAcct 1 ac) of
      (Just (L.SubAccount a), Just (L.SubAccount b)) ->
        if (a == X.pack "Expenses" && b == X.pack "Capital Loss")
           || (b == X.pack "Income" && b == X.pack "Capital Gain")
        then (True, False)
        else (False, True)
      _ -> (False, True)

capCmdtyAcct :: L.Commodity -> L.Account -> E.Tree N.PdctOutput
capCmdtyAcct (L.Commodity cy) ac = E.Node (psd, nm, ii) []
  where
    nm = X.pack $ "Account name has proper commodity"
    (psd, ii) = case extractSubAcct 2 ac of
      Nothing -> (False, True)
      Just (L.SubAccount ac) ->
        if ac == cy
        then (True, False)
        else (False, True)

capDates
  :: FirstPurch -> CurrTime -> L.Account -> E.Tree N.PdctOutput
capDates fp ct ac = E.Node (psd, nm, ii) []
  where

extractSubAcct :: Int -> L.Account -> Maybe L.SubAccount
extractSubAcct i (L.Account ls) =
  if length ls > i
  then Just (ls !! i)
  else Nothing

data BasisOrProceeds = Basis | Proceeds

basisOrProceedsPredicate
  :: BasisOrProceeds
  -> L.Commodity
  -- ^ The commodity you are purchasing
  -> FirstPurch
  -- ^ The first day you purchased the commodity
  -> CurrTime
  -- ^ Today
  -> N.Pdct L.PostFam
basisOrProceedsPredicate bp cy fp ct = N.Pdct func
  where
    func pf = E.Node (psd, nm, int) cs
      where
        ac = Q.account pf
        t1@(E.Node (psd1, _, _) _) =
          isBasisOrProcAcct bp (extractSubAcct 0 ac)
        t2@(E.Node (psd2, _, _) _) =
          isRightCmdty (extractSubAcct 1 ac) cy
        t3@(E.Node (psd3, _, _) _) =
          isRightDay (extractSubAcct 2 ac) fp ct
        t4@(E.Node (psd4, _, _) _) = isRightLength ac
        cs = [t1, t2, t3]
        psd = psd1 && psd2 && psd3
        int = not psd
        nm = X.pack $ desc ++ " account is correct"
        desc = case bp of
          Basis -> "Basis"
          Proceeds -> "Proceeds"

isRightLength :: L.Account -> E.Tree N.PdctOutput
isRightLength (L.Account ac) = E.Node (psd, nm, int) []
  where
    (psd, int) = if length ac == 3
                 then (True, False)
                 else (False, True)
    nm = X.pack "Account has three sub-accounts"

isBasisOrProcAcct
  :: BasisOrProceeds
  -> Maybe L.SubAccount
  -> E.Tree N.PdctOutput
isBasisOrProcAcct bp sub = E.Node (psd, nm, int) []
  where
    nm = X.pack $ "First account name is '" ++ desc ++ "'"
    desc = case bp of
      Basis -> "Basis"
      Proceeds -> "Proceeds"
    (psd, int) = case sub of
      Nothing -> (False, True)
      Just (L.SubAccount s) ->
        if s == X.pack desc
        then (True, False)
        else (False, True)

isRightCmdty
  :: Maybe L.SubAccount
  -> L.Commodity
  -> E.Tree N.PdctOutput
isRightCmdty maySub cy = E.Node (psd, nm, int) []
  where
    nm = X.pack "Second sub-account matches commodity name"
    (psd, int) = case maySub of
      Nothing -> (False, True)
      Just s -> if L.unSubAccount s == L.unCommodity cy
                then (True, False)
                else (False, True)

isRightDay
  :: Maybe L.SubAccount
  -> FirstPurch
  -> CurrTime
  -> E.Tree N.PdctOutput
isRightDay maySub fp ct = E.Node (psd, nm, int) []
  where
    nm = X.pack "Third sub-account is in correct date range"
    (psd, int) = case maySub of
      Nothing -> (False, True)
      Just (L.SubAccount sub) -> case parseDay sub of
        Nothing -> (False, True)
        Just dy ->
          let maxDy = T.addDays 30 . T.utctDay . L.toUTC $ ct
          in if dy >= fp && dy <= maxDy
             then (True, False)
             else (False, True)

parseDay :: X.Text -> Maybe Day
parseDay dateStr = case Parsec.parse p "" dateStr of
  Left _ -> Nothing
  Right d -> Just d
  where
    p = do
      yd <- fmap read $ replicateM 4 Parsec.digit
      _ <- Parsec.char '-' <|> Parsec.char '/'
      md <- fmap read $ replicateM 2 Parsec.digit
      _ <- Parsec.char '-' <|> Parsec.char '/'
      dd <- fmap read $ replicateM 2 Parsec.digit
      case T.fromGregorianValid yd md dd of
        Nothing -> fail "invalid date"
        Just dte -> return dte


{-
commodityPredicate cy dt ct = N.Pdct f
  where
    f pf = E.Node nd [basis, pcds]

basisTree
  :: L.Commodity
  -> T.Day
  -> CurrTime
  -> L.PostFam
  -> E.Tree E.PdctOutput
basisTree cy dy ct pf = E.Node (psd, nm, int) ls
  where
    ls = [isBasis, rightDay, rightCmdty]
    acctLs = map (Just . L.unSubAccount)
             . L.unAccount . Q.account $ pf
    (s1, s2, s3) = case acctLs of
      [] -> (Nothing, Nothing, Nothing)
      x1:[] -> (x1, Nothing, Nothing)
      x1:x2:[] -> (x1, x2, Nothing)
      x1:x2:x3:_ -> (x1, x2, x3)
    isBasis = E.Node (p, n, i) []
      where
        (p, i) = case s1 of
          Nothing -> (False, True)
          Just sub -> sub == X.pack "Basis"
        n = X.pack $ "First sub-account named 'Basis'"
    rightDay = E.Node (p, n, i) []
      where
        (p, i) = case s3 of
          Nothing -> (False, True)
          Just sub -> case parseDay sub of
            Nothing -> (False, True)
            Just d -> if d >= dy && 
-}
