{-# LANGUAGE DeriveFunctor, DeriveFoldable, DeriveTraversable #-}
{-# LANGUAGE TemplateHaskell #-}
{-# LANGUAGE TypeFamilies, FlexibleInstances, MultiParamTypeClasses #-}
{-# LANGUAGE TupleSections #-}
module Penny.Converted where

import Control.Applicative
import Control.Lens
import Control.Monad
import Data.Monoid
import Data.Sequence (Seq)
import Penny.SeqUtil
import Penny.Amount(Amount(..))
import Penny.Ledger
import Data.Foldable (Foldable)
import qualified Data.Traversable as T
import Penny.Viewpost
import Penny.Transbox

-- | A function that converts one 'Amount' to another.
newtype Converter = Converter (Amount -> Maybe Amount)

makeWrapped ''Converter

-- | For a given 'Amount', 'mappend' uses the first 'Converter' that
-- succeeds, or performs no conversion if neither 'Converter' performs
-- a conversion.  'mempty' performs no conversion.
instance Monoid Converter where
  mempty = Converter (const Nothing)
  mappend (Converter x) (Converter y) = Converter $ \a -> x a <|> y a

data Converted a = Converted
  { _converted :: Maybe Amount
  , _convertee :: a
  } deriving (Functor, Foldable, Traversable)

makeLenses ''Converted

convertPosting
  :: Ledger l
  => Converter
  -> PostingL l
  -> l (Converted (PostingL l))
convertPosting (Converter cnv) p = liftM2 f (qty p) (commodity p)
  where
    f qt cy = Converted (cnv (Amount cy qt)) p

createConverteds
  :: Ledger l
  => Converter
  -> Transbox l (Viewpost l ())
  -> Transbox l (Viewpost l (Converted ()))
createConverteds = undefined


convertTransaction
  :: Ledger l
  => Converter
  -> TransactionL l
  -> l (TransactionL l, Seq (View (Converted (PostingL l))))
convertTransaction conv txn
  = return . (txn,) . allViews
  <=< T.mapM (convertPosting conv)
  <=< postings
  $ txn

