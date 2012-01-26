module Penny.Posting where

import qualified Penny.Bits as B
import qualified Penny.Bits.Qty as Q
import qualified Penny.Bits.Price as Price
import qualified Penny.Bits.Commodity as Commodity
import qualified Penny.Bits.Amount as A
import qualified Penny.Bits.Entry as E
import qualified Penny.Total as T

import qualified Penny.Posting.Unverified.Parent as UParent
import qualified Penny.Posting.Unverified.Posting as UPosting

import Penny.Bits.Qty ( add, mult )
import qualified Penny.Posting.Parent as P
import Penny.Groups.AtLeast2 (
  AtLeast2 ( AtLeast2 ), family, toList )
import Penny.Groups.FamilyMember ( FamilyMember )
import Control.Monad.Exception.Synchronous (
  Exceptional (Exception, Success) , throw )

data Posting =
  Posting { payee :: B.Payee
          , number :: Maybe B.Number
          , cleared :: B.Cleared
          , account :: B.Account
          , entry :: E.Entry
          , price :: Maybe Price.Price
          , tags :: B.Tags
          , memo :: Maybe B.Memo
          , uid :: Maybe B.Uid
          , parent :: P.Parent }

-- | All the Postings in a Transaction:
--
-- * May have different Commodities for the Amount in the Entry.
--
-- * Must have the same Commodity for the Amount in the Value.
--
-- * Must produce a Total whose debits and credits are equal.
newtype Transaction =
  Transaction { unTransaction :: AtLeast2 Posting }
  
data Error = UnbalancedError
           | TooManyInferError
           | CouldNotInferError

-- | Get the Postings from a Transaction, with information on the
-- sibling Postings.
postingFamily :: Transaction -> [FamilyMember Posting]
postingFamily (Transaction ps) = family ps

-- | Makes transactions.
--
-- Step 1. Make sure there is at most 1 posting to infer. If more than
-- one, throw.
--
-- Step 2. Compute value of all non-infer postings and total them.
--
-- Step 3. If there are no postings to infer, total must be
-- balanced. If not, throw.
--
-- Step 4. If there is one posting to infer, total must have a
-- non-naught balance with only one commodity. If not, throw.
--
-- Step 5. Infer the one posting (if needed) and make transaction.
transaction ::
  UParent.Parent
  -> AtLeast2 UPosting.Posting
  -> Exceptional Error Transaction
transaction ps = undefined

data Cost = MustInferCost
          | CostSupplied E.Entry (Maybe Price.Price) Price.Value

cost :: UPosting.Posting -> Cost
cost p = case UPosting.cost p of
  UPosting.Blank -> MustInferCost
  (UPosting.EntryOnly e) ->
    CostSupplied e Nothing (Price.entryToValue e)
  (UPosting.EntryPrice e cpu t) ->
    CostSupplied e (Just pr) v where
      (pr, v) = Price.price t cpu e

costs :: AtLeast2 UPosting.Posting
         -> AtLeast2 (UPosting.Posting, Cost)
costs = fmap (\p -> (p, cost p))

balanced :: AtLeast2 UPosting.Cost
            -> T.Balanced
balanced a2 = T.isBalanced . mconcat . toList . fmap toValue
