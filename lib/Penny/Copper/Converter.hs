{-# LANGUAGE TemplateHaskell #-}
{-# LANGUAGE GeneralizedNewtypeDeriving #-}
{-# LANGUAGE OverloadedLists #-}
{-# LANGUAGE OverloadedStrings #-}

-- | Obtaining transactions and prices from a Copper-formatted file
-- takes three steps: parsing, conversion, and proofing.  This
-- module performs conversion.
--
-- Conversion cannot fail; that is, any valid parse result will
-- successfully convert.
--
-- Conversion takes the data types from "Penny.Copper.Types" and does
-- most of the work of converting them to types that are used in the
-- rest of the library.  More importantly, conversion also assigns
-- file locations (that is, line and column numbers) where
-- necessary.  Because the Earley parser does not have location
-- tracking, this module simply scans all characters and keeps track
-- of the position as it progresses through the characters.
module Penny.Copper.Converter where

import Control.Monad.Trans.State (State)
import qualified Control.Monad.Trans.State as State
import qualified Control.Lens as Lens
import Data.Coerce (coerce)
import Data.Foldable (toList)
import Data.Maybe (fromMaybe, catMaybes)
import Data.Text (Text)
import qualified Data.Text as X
import Data.Time (Day, TimeOfDay(TimeOfDay), ZonedTime)
import qualified Data.Time as Time
import Data.Sequence (Seq)
import qualified Data.Sequence as Seq
import Pinchot (terminals)

import Penny.Arrangement
import qualified Penny.Commodity as Commodity
import Penny.Copper.Types
import Penny.DateTime
import Penny.Decimal
import Penny.Digit
import Penny.Natural
import Penny.Polar
import Penny.Realm
import qualified Penny.Scalar as Scalar
import qualified Penny.Tree as Tree
import qualified Penny.Trio as Trio

data Pos = Pos
  { _line :: !Int
  , _column :: !Int
  } deriving (Eq, Ord, Show)

Lens.makeLenses ''Pos

newtype Converter a = Converter { runConverter :: State Pos a }
  deriving (Functor, Applicative, Monad)

locate :: Converter Pos
locate = Converter $ State.get

advanceOne :: Char -> Converter ()
advanceOne c
  | c == '\n' = Converter $ do
      Lens.modifying line succ
      Lens.assign column 1
  | c == '\t' = Converter $ do
      col <- Lens.use column
      Lens.assign column (col + 8 - ((col - 1) `mod` 8))
  | otherwise = Converter $ Lens.modifying column succ

advance :: Traversable f => f Char -> Converter ()
advance = mapM_ advanceOne

c'Day :: Date -> Converter Day
c'Day date = advance (terminals date) >> return (c'Day'Date date)


c'TimeOfDay :: Time -> Converter TimeOfDay
c'TimeOfDay time = advance (terminals time) >> return (TimeOfDay h m s)
  where
    h = digitToInt (_r'Time'0'Hours time)
    m = digitToInt (_r'Time'2'Minutes time)
    s = fromMaybe 0 getSecs
    getSecs = Lens.preview getter time
      where
        getter = r'Time'3'ColonSeconds'Maybe
          . Lens._Wrapped' . Lens._Just . r'ColonSeconds'1'Seconds
          . Lens.to digitToInt . Lens.to fromIntegral


c'Zone :: Zone -> Converter Int
c'Zone (Zone _ zone)
  = advance (terminals zone) >> return mins
  where
    mins
      = changeSign
      $ d3 * 10 ^ 3
      + d2 * 10 ^ 2
      + d1 * 10 * 1
      + d0
    d3 = digitToInt . _r'ZoneHrsMins'1'D0'2 $ zone
    d2 = digitToInt . _r'ZoneHrsMins'2'D0'3 $ zone
    d1 = digitToInt . _r'ZoneHrsMins'3'D0'9 $ zone
    d0 = digitToInt . _r'ZoneHrsMins'4'D0'9 $ zone
    changeSign = case _r'ZoneHrsMins'0'PluMin zone of
      PluMin'Plus _ -> id
      PluMin'Minus _ -> negate

c'QuotedString :: QuotedString -> Converter Text
c'QuotedString qs = advance (terminals qs) >> return x
  where
    x = X.pack . catMaybes . toList . fmap toChar
      . Lens.view Lens._Wrapped'
      . _r'QuotedString'1'QuotedChar'Seq
      $ qs
    toChar (QuotedChar'NonEscapedChar (NonEscapedChar x)) = Just x
    toChar (QuotedChar'EscSeq (EscSeq _ pld)) = payloadToChar pld
    payloadToChar c = case c of
      EscPayload'Backslash _ -> Just '\\'
      EscPayload'Newline _ -> Just '\n'
      EscPayload'DoubleQuote _ -> Just '"'
      EscPayload'Gap _ -> Nothing

c'UnquotedString :: UnquotedString -> Converter Text
c'UnquotedString us = advance (terminals us) >> return x
  where
    x = X.pack . toList . terminals $ us

c'UnquotedCommodity :: UnquotedCommodity -> Converter Commodity.Commodity
c'UnquotedCommodity c
  = advance (terminals c)
  >> return (X.pack . toList . terminals $ c)

c'QuotedCommodity :: QuotedCommodity -> Converter Commodity.Commodity
c'QuotedCommodity = c'QuotedString . Lens.view Lens._Wrapped'

c'Commodity :: Commodity -> Converter Commodity.Commodity
c'Commodity x = case x of
  Commodity'UnquotedCommodity u -> c'UnquotedCommodity u
  Commodity'QuotedCommodity q -> c'QuotedCommodity q

c'WholeAny :: WholeAny -> Converter Integer
c'WholeAny a = advance (terminals a) >> return x
  where
    x = case a of
      WholeAny'Zero _ -> 0
      WholeAny'WholeNonZero
        (WholeNonZero (PluMin'Maybe mayPm) d1 (D0'9'Seq ds)) ->
        changeSign . naturalToInteger $ novDecsToPositive d1 ds
        where
          changeSign = case mayPm of
            Nothing -> id
            Just (PluMin'Plus _) -> id
            Just (PluMin'Minus _) -> negate

-- | Returns True if there is at least one whitespace character.
c'WhiteSeq :: White'Seq -> Converter Bool
c'WhiteSeq ws@(White'Seq sq) = advance (terminals ws) >> return b
  where
    b = not . Seq.null $ sq

c'DebitCredit :: DebitCredit -> Converter Pole
c'DebitCredit dc = advance (terminals dc) >> return p
  where
    p = case dc of
      DebitCredit'Debit _ -> debit
      DebitCredit'Credit _ -> credit

c'T_DebitCredit :: T_DebitCredit -> Converter Trio.Trio
c'T_DebitCredit (T_DebitCredit dc ws) = do
  pole <- c'DebitCredit dc
  _ <- c'WhiteSeq ws
  return $ Trio.S pole

c'T_DebitCredit_Commodity
  :: T_DebitCredit_Commodity
  -> Converter Trio.Trio
c'T_DebitCredit_Commodity (T_DebitCredit_Commodity dc0 w1 cy2 w3) = do
  p <- c'DebitCredit dc0
  _ <- c'WhiteSeq w1
  cy <- c'Commodity cy2
  _ <- c'WhiteSeq w3
  return $ Trio.SC p cy

c'T_DebitCredit_NonNeutral
  :: T_DebitCredit_NonNeutral
  -> Converter Trio.Trio
c'T_DebitCredit_NonNeutral (T_DebitCredit_NonNeutral dc0 w1 nn2 w3) = do
  p <- c'DebitCredit dc0
  _ <- c'WhiteSeq w1
  advance (terminals nn2)
  _ <- c'WhiteSeq w3
  let repAnyRadix = case nn2 of
        NonNeutralRadCom _ brimRadCom ->
          Left $ Extreme  (Polarized brimRadCom p)
        NonNeutralRadPer brimRadPer ->
          Right $ Extreme (Polarized brimRadPer p)
  return $ Trio.Q repAnyRadix

c'T_DebitCredit_Commodity_NonNeutral
  :: T_DebitCredit_Commodity_NonNeutral
  -> Converter Trio.Trio
c'T_DebitCredit_Commodity_NonNeutral (T_DebitCredit_Commodity_NonNeutral
  dc0 w1 c2 w3 nn4 w5) = do
  p <- c'DebitCredit dc0
  _ <- c'WhiteSeq w1
  cy <- c'Commodity c2
  isSpace <- c'WhiteSeq w3
  _ <- advance (terminals nn4)
  _ <- c'WhiteSeq w5
  let repAnyRadix = case nn4 of
        NonNeutralRadCom _ brimRadCom ->
          Left $ Extreme  (Polarized brimRadCom p)
        NonNeutralRadPer brimRadPer ->
          Right $ Extreme (Polarized brimRadPer p)
      arrangement = Arrangement CommodityOnLeft isSpace
  return $ Trio.QC repAnyRadix cy arrangement

c'T_DebitCredit_NonNeutral_Commodity
  :: T_DebitCredit_NonNeutral_Commodity
  -> Converter Trio.Trio
c'T_DebitCredit_NonNeutral_Commodity (T_DebitCredit_NonNeutral_Commodity
  dc0 w1 nn2 w3 c4 w5) = do
  p <- c'DebitCredit dc0
  _ <- c'WhiteSeq w1
  _ <- advance (terminals nn2)
  isSpace <- c'WhiteSeq w3
  cy <- c'Commodity c4
  _ <- c'WhiteSeq w5
  let repAnyRadix = case nn2 of
        NonNeutralRadCom _ brimRadCom ->
          Left $ Extreme  (Polarized brimRadCom p)
        NonNeutralRadPer brimRadPer ->
          Right $ Extreme (Polarized brimRadPer p)
      arrangement = Arrangement CommodityOnLeft isSpace
  return $ Trio.QC repAnyRadix cy arrangement

c'T_Commodity :: T_Commodity -> Converter Trio.Trio
c'T_Commodity (T_Commodity cy0 w1) = do
  cy <- c'Commodity cy0
  _ <- c'WhiteSeq w1
  return $ Trio.C cy

c'T_Commodity_Neutral :: T_Commodity_Neutral -> Converter Trio.Trio
c'T_Commodity_Neutral (T_Commodity_Neutral cy0 w1 n2 w3) = do
  cy <- c'Commodity cy0
  isSpace <- c'WhiteSeq w1
  advance (terminals n2)
  _ <- c'WhiteSeq w3
  let nilAnyRadix = case n2 of
        NeuCom _ nilRadCom -> Left nilRadCom
        NeuPer nilRadPer -> Right nilRadPer
  return $ Trio.NC nilAnyRadix cy (Arrangement CommodityOnLeft isSpace)

c'T_Neutral_Commodity :: T_Neutral_Commodity -> Converter Trio.Trio
c'T_Neutral_Commodity (T_Neutral_Commodity n0 w1 cy2 w3) = do
  advance (terminals n0)
  isSpace <- c'WhiteSeq w1
  cy <- c'Commodity cy2
  _ <- c'WhiteSeq w3
  let nilAnyRadix = case n0 of
        NeuCom _ nilRadCom -> Left nilRadCom
        NeuPer nilRadPer -> Right nilRadPer
  return $ Trio.NC nilAnyRadix cy (Arrangement CommodityOnRight isSpace)

c'T_Commodity_NonNeutral :: T_Commodity_NonNeutral -> Converter Trio.Trio
c'T_Commodity_NonNeutral (T_Commodity_NonNeutral cy0 w1 n2 w3) = do
  cy <- c'Commodity cy0
  isSpace <- c'WhiteSeq w1
  advance (terminals n2)
  _ <- c'WhiteSeq w3
  let brimScalarAnyRadix = case n2 of
        NonNeutralRadCom _ nilRadCom -> Left nilRadCom
        NonNeutralRadPer nilRadPer -> Right nilRadPer
  return $ Trio.UC brimScalarAnyRadix cy (Arrangement CommodityOnLeft isSpace)

c'T_NonNeutral_Commodity :: T_NonNeutral_Commodity -> Converter Trio.Trio
c'T_NonNeutral_Commodity (T_NonNeutral_Commodity n0 w1 cy2 w3) = do
  advance (terminals n0)
  isSpace <- c'WhiteSeq w1
  cy <- c'Commodity cy2
  _ <- c'WhiteSeq w3
  let brimScalarAnyRadix = case n0 of
        NonNeutralRadCom _ nilRadCom -> Left nilRadCom
        NonNeutralRadPer nilRadPer -> Right nilRadPer
  return $ Trio.UC brimScalarAnyRadix cy (Arrangement CommodityOnRight isSpace)

c'T_Neutral :: T_Neutral -> Converter Trio.Trio
c'T_Neutral (T_Neutral n0 w1) = do
  advance (terminals n0)
  _ <- c'WhiteSeq w1
  let nilAnyRadix = case n0 of
        NeuCom _ nilRadCom -> Left nilRadCom
        NeuPer nilRadPer -> Right nilRadPer
  return $ Trio.UU nilAnyRadix

c'T_NonNeutral :: T_NonNeutral -> Converter Trio.Trio
c'T_NonNeutral (T_NonNeutral n0 w1) = do
  advance (terminals n0)
  _ <- c'WhiteSeq w1
  let brimScalarAnyRadix = case n0 of
        NonNeutralRadCom _ brimRadCom -> Left brimRadCom
        NonNeutralRadPer brimRadPer -> Right brimRadPer
  return $ Trio.US brimScalarAnyRadix

c'Trio :: Trio -> Converter Trio.Trio
c'Trio x = case x of
  Trio'T_DebitCredit a -> c'T_DebitCredit a
  Trio'T_DebitCredit_Commodity a -> c'T_DebitCredit_Commodity a
  Trio'T_DebitCredit_NonNeutral a -> c'T_DebitCredit_NonNeutral a
  Trio'T_DebitCredit_Commodity_NonNeutral a ->
    c'T_DebitCredit_Commodity_NonNeutral a
  Trio'T_DebitCredit_NonNeutral_Commodity a ->
    c'T_DebitCredit_NonNeutral_Commodity a
  Trio'T_Commodity a -> c'T_Commodity a
  Trio'T_Commodity_Neutral a -> c'T_Commodity_Neutral a
  Trio'T_Neutral_Commodity a -> c'T_Neutral_Commodity a
  Trio'T_Commodity_NonNeutral a -> c'T_Commodity_NonNeutral a
  Trio'T_NonNeutral_Commodity a -> c'T_NonNeutral_Commodity a
  Trio'T_Neutral a -> c'T_Neutral a
  Trio'T_NonNeutral a -> c'T_NonNeutral a

c'Scalar :: Scalar -> Converter Scalar.Scalar
c'Scalar x = case x of
  Scalar'UnquotedString y -> Scalar.SText <$> c'UnquotedString y
  Scalar'QuotedString y -> Scalar.SText <$> c'QuotedString y
  Scalar'Date y -> Scalar.SDay <$> c'Day y
  Scalar'Time y -> Scalar.STime <$> c'TimeOfDay y
  Scalar'Zone y -> Scalar.SZone <$> c'Zone y
  Scalar'WholeAny y -> Scalar.SInteger <$> c'WholeAny y

positionTree :: Converter Tree.Tree
positionTree = fmap f locate
  where
    f pos = tree (Scalar.SText "position") [line, column]
      where
        tree scalar = Tree.Tree System (Just scalar)
        line = tree (Scalar.SText "line") [treeLine]
        column = tree (Scalar.SText "column") [treeCol]
        treeLine = tree (Scalar.SInteger (fromIntegral . _line $ pos)) []
        treeCol = tree (Scalar.SInteger (fromIntegral . _column $ pos)) []

-- | Converts a 'Tree'.  Adds a child tree to the end of the list of
-- child trees indicating the position.
c'Tree :: Tree -> Converter Tree.Tree
c'Tree x = do
  pos <- positionTree
  tree <- getTree
  return $ addPositionTree pos tree
  where
    getTree = case x of
      TreeScalarFirst sc may ->
        f <$> c'Scalar sc <*> c'BracketedForest'Maybe may
        where
          f scalar forest = Tree.Tree User (Just scalar) forest
      TreeForestFirst bf sc ->
        f <$> c'BracketedForest bf <*> c'Scalar'Maybe sc
        where
          f forest mayScalar = Tree.Tree User mayScalar forest
    addPositionTree pos = Lens.over Tree.children (`Lens.snoc` pos)

c'BracketedForest'Maybe :: BracketedForest'Maybe -> Converter (Seq Tree.Tree)
c'BracketedForest'Maybe (BracketedForest'Maybe may) = case may of
  Nothing -> return Seq.empty
  Just bf -> c'BracketedForest bf

c'BracketedForest :: BracketedForest -> Converter (Seq Tree.Tree)
c'BracketedForest (BracketedForest os0 w1 f2 cs3 w4)
  = advance (terminals os0)
  *> advance (terminals w1)
  *> c'Forest f2
  <* advance (terminals cs3)
  <* advance (terminals w4)


c'Scalar'Maybe :: Scalar'Maybe -> Converter (Maybe Scalar.Scalar)
c'Scalar'Maybe (Scalar'Maybe may) = case may of
  Nothing -> return Nothing
  Just sca -> fmap Just (c'Scalar sca)

c'CommaTree :: CommaTree -> Converter Tree.Tree
c'CommaTree (CommaTree comma whites1 tree whites2)
  = advance (terminals comma)
  *> advance (terminals whites1)
  *> c'Tree tree
  <* advance (terminals whites2)

c'CommaTree'Seq :: CommaTree'Seq -> Converter (Seq Tree.Tree)
c'CommaTree'Seq (CommaTree'Seq sq) = traverse c'CommaTree sq

c'Forest :: Forest -> Converter (Seq Tree.Tree)
c'Forest (Forest t0 w1 ts2) = f <$> c'Tree t0 <* c'WhiteSeq w1
  <*> c'CommaTree'Seq ts2
  where
    f t ts = t `Lens.cons` ts

c'TopLine :: TopLine -> Converter (Seq Tree.Tree)
c'TopLine (TopLine forest) = c'Forest forest

c'Posting :: Posting -> Converter (Pos, Trio.Trio, Seq Tree.Tree)
c'Posting x = do
  pos <- locate
  case x of
    PostingTrioFirst trio bf -> do
      convTrio <- c'Trio trio
      ts <- c'BracketedForest'Maybe bf
      return (pos, convTrio, ts)
    PostingNoTrio bf -> do
      ts <- c'BracketedForest bf
      return (pos, Trio.E, ts)

c'SemiPosting
  :: SemiPosting
  -> Converter (Pos, Trio.Trio, Seq Tree.Tree)
c'SemiPosting (SemiPosting s0 w1 p2)
  = advance (terminals s0)
  *> advance (terminals w1)
  *> c'Posting p2

c'SemiPosting'Seq
  :: SemiPosting'Seq
  -> Converter (Seq (Pos, Trio.Trio, Seq Tree.Tree))
c'SemiPosting'Seq (SemiPosting'Seq sq)
  = traverse c'SemiPosting sq

c'PostingList
  :: PostingList
  -> Converter (Seq (Pos, Trio.Trio, Seq Tree.Tree))
c'PostingList (PostingList p0 ps1)
  = Lens.cons <$> c'Posting p0 <*> c'SemiPosting'Seq ps1

c'PostingList'Maybe
  :: PostingList'Maybe
  -> Converter (Seq (Pos, Trio.Trio, Seq Tree.Tree))
c'PostingList'Maybe (PostingList'Maybe may) = case may of
  Nothing -> return Seq.empty
  Just pl -> c'PostingList pl

c'Postings
  :: Postings
  -> Converter (Seq (Pos, Trio.Trio, Seq Tree.Tree))
c'Postings (Postings oc0 w1 pl2 cc3 w4)
  = advance (terminals oc0)
  *> advance (terminals w1)
  *> c'PostingList'Maybe pl2
  <* advance (terminals cc3)
  <* advance (terminals w4)

c'TopLine'Maybe :: TopLine'Maybe -> Converter (Seq Tree.Tree)
c'TopLine'Maybe = maybe (return Seq.empty) c'TopLine . coerce

c'Transaction
  :: Transaction
  -> Converter (Seq Tree.Tree, Seq (Pos, Trio.Trio, Seq Tree.Tree))
c'Transaction (Transaction tl pstgs)
  = (,)
  <$> c'TopLine'Maybe tl
  <*> c'Postings pstgs

data PriceParts = PriceParts
  { _pricePos :: Pos
  , _priceTime :: ZonedTime
  , _priceFrom :: Commodity.Commodity
  , _priceTo :: Commodity.Commodity
  , _priceExch :: Decimal
  }

c'PluMin :: Num a => PluMin -> Converter (a -> a)
c'PluMin x = do
  advance (terminals x)
  return $ case x of
    PluMin'Plus _ -> id
    PluMin'Minus _ -> negate

c'PluMinFs :: Num a => PluMinFs -> Converter (a -> a)
c'PluMinFs (PluMinFs pm sq) = c'PluMin pm <* advance (terminals sq)

c'PluMinFs'Maybe :: Num a => PluMinFs'Maybe -> Converter (a -> a)
c'PluMinFs'Maybe = maybe (return id) c'PluMinFs . coerce

c'Exch :: Exch -> Converter Decimal
c'Exch x = case x of
  ExchNeutral neu ws -> do
    advance (terminals neu)
    advance (terminals ws)
    return . fmap (const 0) . toDecZero $ neu
  ExchNonNeutral pm nn ws -> do
    changeSign <- c'PluMinFs'Maybe pm
    advance (terminals nn)
    advance (terminals ws)
    return . fmap (changeSign . naturalToInteger) . toDecPositive $ nn

c'CyExch :: CyExch -> Converter (Commodity.Commodity, Decimal)
c'CyExch x = case x of
  CyExchCy cy ws ex -> (,)
    <$> c'Commodity cy
    <* advance (terminals ws)
    <*> c'Exch ex
  CyExchExch ex cy ws -> (\a b -> (b, a))
    <$> c'Exch ex
    <*> c'Commodity cy
    <* advance (terminals ws)

c'TimeWhites'Optional :: TimeWhites'Optional -> Converter TimeOfDay
c'TimeWhites'Optional x = case x of
  TimeWhitesYes t w -> c'TimeOfDay t <* advance (terminals w)
  TimeWhitesNo -> return Time.midnight

c'ZoneWhites'Optional :: ZoneWhites'Optional -> Converter Time.TimeZone
c'ZoneWhites'Optional (ZoneWhitesYes z ws)
  = Time.minutesToTimeZone <$> c'Zone z <* advance (terminals ws)
c'ZoneWhites'Optional ZoneWhitesNo = return Time.utc

c'Price :: Price -> Converter PriceParts
c'Price (Price a0 w1 d2 w3 tw4 zw5 c6 w7 e8)
  = f
  <$> locate
  <* advance (terminals a0)
  <* advance (terminals w1)
  <*> c'Day d2
  <* advance (terminals w3)
  <*> c'TimeWhites'Optional tw4
  <*> c'ZoneWhites'Optional zw5
  <*> c'Commodity c6
  <* advance (terminals w7)
  <*> c'CyExch e8
  where
    f loc day tod zone from (to, exch) = PriceParts loc
      (Time.ZonedTime (Time.LocalTime day tod) zone)
      from to exch

type TxnParts = (Seq Tree.Tree, Seq (Pos, Trio.Trio, Seq Tree.Tree))

c'FileItem
  :: FileItem
  -> Converter (Either PriceParts TxnParts)
c'FileItem x = case x of
  FileItem'Price p -> Left <$> c'Price p
  FileItem'Transaction t -> Right <$> c'Transaction t

c'FileItem'Seq
  :: FileItem'Seq
  -> Converter (Seq (Either PriceParts TxnParts))
c'FileItem'Seq = traverse c'FileItem . coerce

c'WholeFile
  :: WholeFile
  -> Converter (Seq (Either PriceParts TxnParts))
c'WholeFile (WholeFile w0 i1) = advance (terminals w0)
  *> c'FileItem'Seq i1