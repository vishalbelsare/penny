-- | The Postings grid.
--
-- The Postings report is just a big grid. This is represented as an
-- array. Filling in the grid is a multiple-step process. This module
-- contains the higher-level functions that are responsible for
-- filling in the grid.
--
-- The grid is cooperative: in order for things to line up on screen,
-- it is essential that each cell be the right size. However the model
-- ultimately relies on the contents of each cell to size itself
-- correctly, rather than other functions resizing the cells. This is
-- because ultimately each cell knows best how to size itself to
-- fit--for example, how it might truncate its contents to fit a
-- narrow cell.
module Penny.Cabin.Postings.Grid where

import Control.Applicative ((<$>), (<*>))
import qualified Data.Array as A
import qualified Data.Foldable as F
import qualified Data.List.NonEmpty as NE
import qualified Data.Table as Ta
import qualified Data.Traversable as Tr

import qualified Penny.Cabin.Colors as C
import qualified Penny.Cabin.Postings.Types as T
import qualified Penny.Cabin.Row as R
import qualified Penny.Liberty.Types as LT
import qualified Penny.Lincoln.Balance as Bal
import qualified Penny.Lincoln.Queries as Q

-- | fmap over an array, with additional information. Similar to fmap,
-- but with an ordinary fmap the function sees only the contents of
-- the current cell. fmapArray shows the function the entire array and
-- the address of the current cell, as well as the contents of the
-- cell itself. The function then returns the contents of the new
-- cell.
fmapArray ::
  A.Ix i
  => (A.Array i y -> i -> y -> z)
  -> A.Array i y
  -> A.Array i z
fmapArray f a = A.array b ls' where
  b = A.bounds a
  ls' = map f' . A.assocs $ a
  f' (i, e) = (i, f a i e)

-- * Step 1 - Compute balances
{-
balanceAccum :: Bal.Balance -> LT.PostingInfo -> (Bal.Balance, Bal.Balance)
balanceAccum bal po = (bal', bal') where
  bal' = bal `mappend` pstgBal
  pstgBal = Bal.entryToBalance . Q.entry . LT.postingBox $ po
-}

balanceAccum :: Maybe Bal.Balance
                -> LT.PostingInfo
                -> (Maybe Bal.Balance, (LT.PostingInfo, Bal.Balance))
balanceAccum mb po = (Just bal', (po, bal')) where
  bal' = let
    balThis = Bal.entryToBalance . Q.entry . LT.postingBox $ po
    in case mb of
      Nothing -> balThis
      Just balOld -> Bal.addBalances balOld balThis

balances :: NE.NonEmpty LT.PostingInfo
            -> NE.NonEmpty (LT.PostingInfo, Bal.Balance)
balances = snd . Tr.mapAccumL balanceAccum Nothing

{-
balances :: [LT.PostingInfo] -> [(LT.PostingInfo, Bal.Balance)]
balances ps = zip ps (snd . Tr.mapAccumL balanceAccum mempty $ ps)
-}
-- * Step 2 - Number postings

{-
numberPostings ::
  [(LT.PostingInfo, Bal.Balance)]
  -> [T.PostingInfo]
numberPostings ls = reverse reversed where
  withPostingNums =
    getZipList
    $ (\(li, bal) pn -> (li, bal, pn))
    <$> ZipList ls
    <*> ZipList (map T.PostingNum [0..])
  reversed =
    getZipList
    $ (\(li, bal, pn) rpn -> T.fromLibertyInfo bal pn rpn li)
    <$> ZipList (reverse withPostingNums)
    <*> ZipList (map T.RevPostingNum [0..])
-}

numberPostings ::
  NE.NonEmpty (LT.PostingInfo, Bal.Balance)
  -> NE.NonEmpty T.PostingInfo
numberPostings ls = NE.reverse reversed where
  withPostingNums = NE.zipWith f ls ns where
    f (li, bal) pn = (li, bal, pn)
    ns = fmap T.PostingNum (NE.iterate succ 0)
  reversed = NE.zipWith f wpn rpns where
    f (li, bal, pn) rpn = T.fromLibertyInfo bal pn rpn li
    wpn = NE.reverse withPostingNums
    rpns = fmap T.RevPostingNum (NE.iterate succ 0)
    
-- * Step 3 - Get visible postings only
filterToVisible ::
  (LT.PostingInfo -> Bool)
  -> NE.NonEmpty T.PostingInfo
  -> [T.PostingInfo]
filterToVisible p ps = NE.filter p' ps where
  p' pstg = p (T.toLibertyInfo pstg)

-- * Step 4 - add visible numbers
addVisibleNum ::
  [T.PostingInfo]
  -> [(T.PostingInfo, T.VisibleNum)]
addVisibleNum ls = zip ls (map T.VisibleNum [0..])

-- * Step 5 - multiply into tranches
tranches ::
  Bounded t
  => [(T.PostingInfo, T.VisibleNum)]
  -> [(T.PostingInfo, T.VisibleNum, t)]
tranches ls =
  (\(p, vn) t -> (p, vn, t))
  <$> ls
  <*> [minBound, maxBound]

-- * Step 6 - multiply to array
toArray ::
  (Bounded c, Bounded t, A.Ix c, A.Ix t)
  => [(T.PostingInfo, T.VisibleNum, t)]
  -> Maybe (A.Array (c, (T.VisibleNum, t)) T.PostingInfo)
toArray ls =
  if null ls
  then Nothing
  else let
    (_, maxVn, _) = last ls
    b = ((minBound, (T.VisibleNum 0, minBound)),
         (maxBound, (maxVn, maxBound)))
    pair c (p, vn, t) = ((c, (vn, t)), p)
    ps = pair
         <$> A.range (minBound, maxBound)
         <*> ls
    in Just $ A.array b ps

type Index c t = (c, (T.VisibleNum, t))

-- * Step 7 - Space claim

-- | Step 7 - Space claim. What different cells should do at this phase:
--
-- * Grow to fit cells - color coded blue. These should supply a Just
-- ClaimedWidth whose number indicates how wide their content will
-- be. They should do this only if their respective field is showing
-- in the final report; if the field is not showing, supply
-- Nothing. Also, if their field has no data to show (for instance,
-- this is a Flag field, and the posting has no flag), supply Nothing.
--
-- * Padding cells - these are color coded orange. They should supply
-- a Just ClaimedWidth, but only if their respective field is showing
-- and that field has data to show. In that circumstance, supply Just
-- (ClaimedWidth 1). Otherwise, supply Nothing.
--
-- * All other cells - supply Nothing.
type Claimer c t =
  A.Array (Index c t) T.PostingInfo
  -> Index c t
  -> T.PostingInfo
  -> Maybe T.ClaimedWidth

spaceClaim ::
  (A.Ix c, A.Ix t)
  => Claimer c t
  -> A.Array (Index c t) T.PostingInfo
  -> A.Array (Index c t) (T.PostingInfo, Maybe T.ClaimedWidth)
spaceClaim f = fmapArray g where
  g a i p = (p, f a i p)

-- * Step 8 - GrowToFit

-- | Step 8 - GrowToFit. What different cells should do at this phase:
--
-- * Grow to fit cells - these are color coded blue. These should
-- supply their actual data, and justify themselves to be as wide as
-- the widest cell in the column.
--
-- * Padding cells - these are color coded orange. These should supply
-- a cell that is justified to be as wide as the widest cell in the
-- column. Otherwise these cells contain no text at all (the Row
-- module takes care of supplying the necessary bottom padding lines
-- if they are needed.)
--
-- * Empty but padded cells - these are color coded yellow. Treat
-- these exactly the same as Padding cells.
--
-- * Overran cells - these are color coded light green. These should
-- supply Just 'Penny.Cabin.Row.zeroCell'.
--
-- * Allocated cells - these are color coded purple. These should
-- supply Nothing.
--
-- * Overrunning cells - these should supply Nothing.
type Grower c t =
  A.Array (Index c t) (T.PostingInfo, Maybe T.ClaimedWidth)
  -> Index c t
  -> (T.PostingInfo, Maybe T.ClaimedWidth)
  -> Maybe R.Cell

growCells ::
  (A.Ix c, A.Ix t)
  => Grower c t
  -> A.Array (Index c t) (T.PostingInfo, Maybe T.ClaimedWidth)
  -> A.Array (Index c t) (T.PostingInfo, Maybe R.Cell)
growCells f = fmapArray g where
  g a i (p, w) = (p, f a i (p, w))

-- * Step 9 - Allocation Claim

-- | Step 9 - Allocation claim. What do do at this phase:
--
-- * GrowToFit, Padding, Empty, and Overran cells - have already
-- supplied a cell. Pass that cell along using AcCell.
--
-- * Allocated cells - If the field is not selected to be in the
-- report, supply an empty cell in AcCell . If the field is selected,
-- then calculate the maximum width that the cell could use and pass
-- it in an AcWidth.
--
-- * Overrunning cells - supply AcOverrunning
type AllocationClaim c t =
  A.Array (Index c t) (T.PostingInfo, Maybe R.Cell)
  -> Index c t
  -> (T.PostingInfo, Maybe R.Cell)
  -> AcClaim

data AcClaim =
  AcCell R.Cell
  | AcWidth Int
  | AcOverrunning

allocateClaim ::
  (A.Ix c, A.Ix t)
  => AllocationClaim c t
  -> A.Array (Index c t) (T.PostingInfo, Maybe R.Cell)
  -> A.Array (Index c t) (T.PostingInfo, AcClaim)
allocateClaim f = fmapArray g where
  g a i (p, mc) = (p, f a i (p, mc))

-- * Step 10 - Allocate

-- | Step 10 - Allocate. What to do at this phase:
--
-- * GrowToFit, Padding, Empty, Overran, and Allocated cells whose
-- field is not in the report - have already supplied a cell via
-- AcCell. Pass that cell along.
--
-- * Allocated cells whose field is in the report - have supplied an
-- AcWidth. Use the minimum report width, the width of all other
-- GrowToFit and Padding cells in the row, and the share allocated to
-- other Allocated cells that are going to show in the report to
-- determine the maximum space available to the allocated
-- column. Also, compute the maximum AcWidth of the column. Create a
-- cell that is as wide as (min maxAcWidth availAllocatedSpace).
--
-- * Overrunning cells - supply Nothing.
type Allocator c t =
  A.Array (Index c t) (T.PostingInfo, AcClaim)
  -> Index c t
  -> (T.PostingInfo, AcClaim)
  -> Maybe R.Cell

allocateCells ::
  (A.Ix c, A.Ix t)
  => Allocator c t
  -> A.Array (Index c t) (T.PostingInfo, AcClaim)
  -> A.Array (Index c t) (T.PostingInfo, Maybe R.Cell)
allocateCells f = fmapArray g where
  g a i (p, w) = (p, f a i (p, w))

-- * Step 11 - Finalize

-- | Step 11. Finalize all cells, including overruns. What cells should
-- do at this phase:
--
-- * GrowToFit, Empty but padded, padding, overran, allocated cells -
-- these have already supplied a cell. Pass this cell along.
--
-- * Overrunning cells - If the corresponding field is not showing,
-- supply 'Penny.Cabin.Row.emptyCell'. If the field is showing,
-- calculate the width of the cell by using the width of the
-- appropriate cells in the top tranche row. Supply a cell that is
-- justified to exactly the correct width. (the Row module will not
-- truncate or wrap cells, so the function must do this itself.)
type Finalizer c t =
  A.Array (Index c t) (T.PostingInfo, Maybe R.Cell)
  -> Index c t
  -> (T.PostingInfo, Maybe R.Cell)
  -> R.Cell

finalize ::
  (A.Ix c, A.Ix t)
  => Finalizer c t
  -> A.Array (Index c t) (T.PostingInfo, Maybe R.Cell)
  -> CellArray c t
finalize f = CellArray . fmapArray f

-- * Step 12 - make chunks
newtype CellArray c t =
  CellArray { unCellArray :: A.Array (Index c t) R.Cell }

instance (A.Ix c, A.Ix t) => R.HasChunk (CellArray c t) where
  chunk (CellArray a) = R.chunk rows where
    rows = F.foldr R.prependRow R.emptyRows rs
    rs = fmap toRow . Ta.OneDim . Ta.rows $ a
    toRow = F.foldr R.prependCell R.emptyRow

-- * Put it all together

report ::
  (A.Ix c, A.Ix t, Bounded c, Bounded t)
  => Claimer c t
  -> Grower c t
  -> AllocationClaim c t
  -> Allocator c t
  -> Finalizer c t
  -> (LT.PostingInfo -> Bool)
  -> [LT.PostingInfo]
  -> Maybe C.Chunk
report c g ac a f p pbs =
  NE.nonEmpty pbs

  >>= (toArray
       . tranches
       . addVisibleNum
       . filterToVisible p
       . numberPostings
       . balances)

  >>= (return
       . R.chunk
       . finalize f
       . allocateCells a
       . allocateClaim ac
       . growCells g
       . spaceClaim c)
