{-# LANGUAGE TemplateHaskell #-}
{-# LANGUAGE TypeSynonymInstances, FlexibleInstances #-}
{-# LANGUAGE DeriveGeneric #-}
{-# LANGUAGE DeriveAnyClass #-}

-- | "Penny.Trio" hews closely to the possible manifestations of the
-- quantity, commodity, and arrangement in the ledger file.  The
-- "Penny.Trio" corresponds only to what is in a single posting.
--
-- The 'Troika' is concerned with holding the manifestation of the
-- quantity, commodity and arrangement, but after considering all
-- the postings of a single transaction together.  The biggest
-- consequence of this is that, unlike a "Penny.Trio", a 'Troika'
-- always contains a 'Commodity'.  In addition, the quantity in a
-- 'Troika' always is positive, negative, or zero, while the
-- quantity in a "Penny.Trio" is sometimes unsigned.
--
-- Also, the 'Troika' always has a quantity, while sometimes a
-- "Penny.Trio" has no quantity if the user did not enter one.
-- Therefore, the quantity in the 'Troika' sometimes is one of the
-- types from "Penny.Decimal" is the quantity was calculated rather
-- tha entered by the user.  It will ultimately be one of the types from
-- "Penny.Copper.Types" if the user did enter it.
module Penny.Troika where

import qualified Penny.Amount as A
import Penny.Arrangement
import Penny.Balance
import Penny.Commodity
import Penny.Copper.Decopperize
import Penny.Decimal
import Penny.Copper.Types (GrpRadCom, GrpRadPer)
import Penny.NonZero
import qualified Penny.NonZero as NZ
import Penny.Pretty
import Penny.Polar
import qualified Penny.Positive as Pos
import Penny.Rep
import qualified Penny.Trio as Trio

import qualified Control.Lens as Lens
import qualified Data.Map as M
import Data.Sequence (Seq)
import GHC.Generics (Generic)
import Text.Show.Pretty (PrettyVal)
import qualified Text.Show.Pretty as Pretty

-- | The payload data of a 'Troika'.
data Troiload
  = QC RepAnyRadix Arrangement
  | Q RepAnyRadix
  | SC DecNonZero
  | S DecNonZero
  | UC BrimAnyRadix Pole Arrangement
  | NC NilAnyRadix Arrangement
  | US BrimAnyRadix Pole
  | UU NilAnyRadix
  | C DecNonZero
  | E DecNonZero
  deriving (Show, Generic)

instance PrettyVal Troiload where
  prettyVal tl = case tl of
    QC rar ar -> ct "QC" [reify rar, pretty ar]
    Q rar -> ct "Q" [reify rar]
    SC dnz -> ct "SC" [pretty dnz]
    S dnz -> ct "S" [pretty dnz]
    UC brim pole ar -> ct "UC" [reify brim, pretty pole, pretty ar]
    NC nil ar -> ct "NC" [reify nil, pretty ar]
    US brim pole -> ct "US" [reify brim, pretty pole]
    UU nil -> ct "UU" [reify nil]
    C dnz -> ct "C" [pretty dnz]
    E dnz -> ct "E" [pretty dnz]
    where
      -- do not eta reduce pretty - monomorphism restriction
      pretty v = Pretty.prettyVal v
      ct v = Pretty.Con v
      reify v = case Pretty.reify v of
        Nothing -> error $ "Penny.Troika.Troika.prettyVal: reification failed"
        Just r -> r

troiloadPole :: Troiload -> Maybe Pole
troiloadPole x = case x of
  QC q _ -> pole'RepAnyRadix q
  Q q -> pole'RepAnyRadix q
  SC qnz -> Just . nonZeroSign . _coefficient $ qnz
  S qnz -> Just . nonZeroSign . _coefficient $ qnz
  UC _ s _ -> Just s
  NC _ _ -> Nothing
  US _ s -> Just s
  UU _ -> Nothing
  C qnz -> Just . nonZeroSign . _coefficient $ qnz
  E qnz -> Just . nonZeroSign . _coefficient $ qnz

data Troika = Troika
  { _commodity :: Commodity
  , _troiload :: Troiload
  } deriving (Show, Generic)

instance PrettyVal Troika where
  prettyVal (Troika cy tq) = Pretty.Rec "Troika"
    [ ("_commodity", prettyText cy)
    , ("_troiload", Pretty.prettyVal tq)
    ]

Lens.makeLenses ''Troika

-- TODO the () type is too specific
troikaRendering
  :: Troika
  -> Maybe (Commodity, Arrangement,
            Either (Seq (GrpRadCom Char ())) (Seq (GrpRadPer Char ())))
troikaRendering (Troika cy tl) = case tl of
  QC qr ar -> Just (cy, ar, ei)
    where
      ei = groupers'RepAnyRadix qr
  UC rnn _ ar -> Just (cy, ar, ei)
    where
      ei = groupers'BrimAnyRadix rnn
  _ -> Nothing

c'Decimal'Troiload :: Troiload -> Decimal
c'Decimal'Troiload x = case x of
  QC q _ -> c'Decimal'RepAnyRadix q
  Q q -> c'Decimal'RepAnyRadix q
  SC qnz -> fmap c'Integer'NonZero qnz
  S qnz -> fmap c'Integer'NonZero qnz
  UC rnn s _ ->
    fmap c'Integer'NonZero
    . c'DecNonZero'DecPositive s
    . c'DecPositive'BrimAnyRadix
    $ rnn
  NC nilAnyRadix _ ->
    fmap (const 0) . c'DecZero'NilAnyRadix $ nilAnyRadix
  US rnn s ->
    fmap c'Integer'NonZero
    . c'DecNonZero'DecPositive s
    . c'DecPositive'BrimAnyRadix
    $ rnn
  UU nil -> fmap (const 0) . c'DecZero'NilAnyRadix $ nil
  C qnz -> fmap c'Integer'NonZero qnz
  E qnz -> fmap c'Integer'NonZero qnz

c'Decimal'Troika :: Troika -> Decimal
c'Decimal'Troika (Troika _ tq) = c'Decimal'Troiload tq

pole'Troika :: Troika -> Maybe Pole
pole'Troika (Troika _ tl) = pole'Decimal . c'Decimal'Troiload $ tl

c'Amount'Troika :: Troika -> A.Amount
c'Amount'Troika (Troika cy ei) = A.Amount cy
  (c'Decimal'Troiload ei)


trioToTroiload
  :: Imbalance
  -> Trio.Trio
  -> Either Trio.TrioError (Troiload, Commodity)

trioToTroiload _ (Trio.QC qnr cy ar) = Right (QC qnr ar, cy)

trioToTroiload imb (Trio.Q qnr) = fmap f $ oneCommodity imb
  where
    f (cy, _) = (Q qnr, cy)

trioToTroiload imb (Trio.SC s cy) = do
  qnz <- lookupCommodity imb cy
  let qtSide = Lens.view (coefficient . NZ.pole) qnz
  notSameSide qtSide s
  return (SC qnz, cy)

trioToTroiload imb (Trio.S s) = do
  (cy, qnz) <- oneCommodity imb
  let qtSide = Lens.view (coefficient . NZ.pole) qnz
  notSameSide s qtSide
  return (S qnz, cy)

trioToTroiload imb (Trio.UC qnr cy ar) = do
  qnz <- lookupCommodity imb cy
  return (UC qnr (opposite . Lens.view (coefficient . NZ.pole) $ qnz) ar, cy)

trioToTroiload _ (Trio.NC nilAnyRadix cy ar) = Right (troiload, cy)
  where
    troiload = NC nilAnyRadix ar

trioToTroiload imb (Trio.US brim) = do
  (cy, qnz) <- oneCommodity imb
  rnnIsSmallerAbsoluteValue brim qnz
  let pole' = Lens.view (coefficient . NZ.pole . Lens.to opposite) qnz
  return (US brim pole', cy)

trioToTroiload imb (Trio.UU nil) = do
  (cy, _) <- oneCommodity imb
  return (UU nil, cy)

trioToTroiload imb (Trio.C cy) = do
  qnz <- lookupCommodity imb cy
  let qnz' = Lens.over (coefficient . NZ.pole) opposite qnz
  return (C qnz', cy)

trioToTroiload imb Trio.E = do
  (cy, qnz) <- oneCommodity imb
  return (E (Lens.over (coefficient . NZ.pole) opposite qnz), cy)

oneCommodity :: Imbalance -> Either Trio.TrioError (Commodity, DecNonZero)
oneCommodity (Imbalance imb) = case M.toList imb of
  [] -> Left Trio.NoImbalance
  (cy, q):[] -> return (cy, q)
  x:y:xs -> Left $ Trio.MultipleImbalance x y xs

notSameSide :: Pole -> Pole -> Either Trio.TrioError ()
notSameSide x y
  | x == y = Left $ Trio.BalanceIsSameSide x
  | otherwise = return ()

lookupCommodity :: Imbalance -> Commodity -> Either Trio.TrioError DecNonZero
lookupCommodity (Imbalance imb) cy = case M.lookup cy imb of
  Nothing -> Left $ Trio.CommodityNotFound cy
  Just dnz -> return dnz

rnnIsSmallerAbsoluteValue
  :: BrimAnyRadix
  -> DecNonZero
  -> Either Trio.TrioError ()
rnnIsSmallerAbsoluteValue qnr qnz
  | _coefficient qnr'' < _coefficient qnz'' = return ()
  | otherwise = Left $ Trio.UnsignedTooLarge qnr qnz
  where
    qnr' = fmap Pos.c'Integer'Positive . c'DecPositive'BrimAnyRadix $ qnr
    qnz' = c'Decimal'DecNonZero qnz
    (qnr'', qnz'') = equalizeExponents qnr' qnz'

trioToAmount :: Imbalance -> Trio.Trio -> Either Trio.TrioError A.Amount

trioToAmount _ (Trio.QC qnr cy _) = Right $ A.Amount cy (c'Decimal'RepAnyRadix qnr)

trioToAmount imb (Trio.Q qnr) = fmap f $ oneCommodity imb
  where
    f (cy, _) = A.Amount cy (c'Decimal'RepAnyRadix qnr)

trioToAmount imb (Trio.SC s cy) = do
  qnz <- lookupCommodity imb cy
  let qtSide = Lens.view (coefficient . NZ.pole) qnz
  notSameSide qtSide s
  return
    . A.Amount cy
    . fmap (Prelude.negate . c'Integer'NonZero)
    $ qnz

trioToAmount imb (Trio.S s) = do
  (cy, qnz) <- oneCommodity imb
  let qtSide = Lens.view (coefficient . NZ.pole) qnz
  notSameSide s qtSide
  return
    . A.Amount cy
    . fmap (Prelude.negate . c'Integer'NonZero)
    $ qnz

trioToAmount imb (Trio.UC qnr cy _) = do
  qnz <- lookupCommodity imb cy
  return
    . A.Amount cy
    . Lens.over coefficient c'Integer'NonZero
    . Lens.set (coefficient . NZ.pole) (Lens.view (coefficient . NZ.pole) qnz)
    . fmap NZ.c'NonZero'Positive
    . c'DecPositive'BrimAnyRadix
    $ qnr

trioToAmount _ (Trio.NC nilAnyRadix cy _) = Right (A.Amount cy qty)
  where
    qty = fmap (const 0) . c'DecZero'NilAnyRadix $ nilAnyRadix

trioToAmount imb (Trio.US qnr) = do
  (cy, qnz) <- oneCommodity imb
  rnnIsSmallerAbsoluteValue qnr qnz
  return
    . A.Amount cy
    . Lens.over coefficient c'Integer'NonZero
    . Lens.set (coefficient . NZ.pole) (Lens.view (coefficient . NZ.pole) qnz)
    . fmap NZ.c'NonZero'Positive
    . c'DecPositive'BrimAnyRadix
    $ qnr

trioToAmount imb (Trio.UU nil) = do
  (cy, _) <- oneCommodity imb
  return (A.Amount cy (fmap (const 0) (c'DecZero'NilAnyRadix nil)))

trioToAmount imb (Trio.C cy) = do
  qnz <- lookupCommodity imb cy
  return
    . A.Amount cy
    . fmap c'Integer'NonZero
    . Lens.set (coefficient . NZ.pole) (Lens.view (coefficient . NZ.pole) qnz)
    $ qnz

trioToAmount imb Trio.E = do
  (cy, qnz) <- oneCommodity imb
  return
    . A.Amount cy
    . fmap c'Integer'NonZero
    . Lens.set (coefficient . NZ.pole) (Lens.view (coefficient . NZ.pole) qnz)
    $ qnz

-- | What side the troiload is on.
troiloadSide :: Troiload -> Maybe Pole
troiloadSide x = case x of
  QC rar _ -> pole'RepAnyRadix rar
  Q q -> pole'RepAnyRadix q
  SC dnz -> Just $ Lens.view poleDecNonZero dnz
  S dnz -> Just $ Lens.view poleDecNonZero dnz
  UC _ p _ -> Just p
  NC _ _ -> Nothing
  US _ p -> Just p
  UU _ -> Nothing
  C dnz -> Just $ Lens.view poleDecNonZero dnz
  E dnz -> Just $ Lens.view poleDecNonZero dnz

-- | What side a troika is on.
troikaSide :: Troika -> Maybe Pole
troikaSide = troiloadSide . _troiload

-- | Convert a 'Troiload' to a 'Trio'.
troiloadToTrio :: Commodity -> Troiload -> Trio.Trio
troiloadToTrio cy tl = case tl of
  QC rar ar -> Trio.QC rar cy ar
  Q rar -> Trio.Q rar
  SC dnz -> Trio.SC (Lens.view poleDecNonZero dnz) cy
  S dnz -> Trio.S (Lens.view poleDecNonZero dnz)
  UC brim _ ar -> Trio.UC brim cy ar
  NC nil ar -> Trio.NC nil cy ar
  US brim _ -> Trio.US brim
  UU nil -> Trio.UU nil
  C _ -> Trio.C cy
  E _ -> Trio.E

-- | Convert a 'Troika' to a 'Trio.Trio'.
troikaToTrio :: Troika -> Trio.Trio
troikaToTrio (Troika cy tl) = troiloadToTrio cy tl
