-- | Queries on 'Tranche's.

module Penny.Queries.Tranche where

import qualified Penny.Lincoln as L
import Data.Sequence (Seq)

trancheSerset :: L.Tranche l -> L.Serset
trancheSerset (L.Tranche _ s) = s

splint :: L.Tranche l -> L.Splint l
splint (L.Tranche l _) = l

splintSerset :: L.Tranche l -> L.Serset
splintSerset (L.Tranche (L.Splint _ s _) _) = s

balances :: L.Tranche l -> L.Balances
balances (L.Tranche (L.Splint _ _ b) _) = b

sliceSerset :: L.Tranche l -> L.Serset
sliceSerset (L.Tranche (L.Splint (L.Slice _ s _ _) _ _ ) _) = s

qty :: L.Tranche l -> L.Qty
qty (L.Tranche (L.Splint (L.Slice _ _ q _) _ _) _) = q

commodity :: L.Tranche l -> L.Commodity
commodity (L.Tranche (L.Splint (L.Slice _ _ _ cy) _ _) _) = cy

clatch :: L.Tranche l -> L.Clatch l
clatch (L.Tranche (L.Splint (L.Slice cl _ _ _) _ _) _) = cl

transaction :: L.Tranche l -> L.TransactionL l
transaction t = let L.Clatch tx _ _ _ = clatch t in tx

leftSiblings :: L.Tranche l -> Seq (L.PostingL l)
leftSiblings t = let L.Clatch _ x _ _ = clatch t in x

posting :: L.Tranche l -> L.PostingL l
posting t = let L.Clatch _ _ x _ = clatch t in x

rightSiblings :: L.Tranche l -> Seq (L.PostingL l)
rightSiblings t = let L.Clatch _ _ _ x = clatch t in x

transactionMeta :: L.Ledger l => L.Tranche l -> l (Seq (L.TreeL l))
transactionMeta = L.transactionMeta . transaction

topLineSerial :: L.Ledger l => L.Tranche l -> l L.TopLineSer
topLineSerial = L.topLineSerial . transaction

postingTrees :: L.Ledger l => L.Tranche l -> l (Seq (L.TreeL l))
postingTrees = L.postingTrees . posting

trio :: L.Ledger l => L.Tranche l -> l L.Trio
trio = L.postingTrio . posting

postingSer :: L.Ledger l => L.Tranche l -> l L.PostingSer
postingSer = L.postingSerial . posting

-- | Looks for a tree matching a predicate in the posting's trees.  If
-- one is not found, looks in the transaction's trees.
best
  :: L.Ledger l
  => (L.Realm -> L.Scalar -> Bool)
  -> L.Tranche l
  -> l (Maybe (L.TreeL l))
best pd tr = do
  pts <- postingTrees tr
  mayTree <- L.findTreeInForest pd pts
  case mayTree of
    Nothing -> do
      tts <- transactionMeta tr
      L.findTreeInForest pd tts
    x -> return x

side :: L.Tranche l -> Maybe L.Side
side = L.qtySide . qty
